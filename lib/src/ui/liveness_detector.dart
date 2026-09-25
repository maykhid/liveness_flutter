import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart' show ResolutionPreset;
import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../camera/detection_geometry.dart';
import '../camera/frame_quality.dart';
import '../camera/frame_source.dart';
import '../controller/liveness_session.dart';
import '../detection/flash_challenge.dart';
import '../detection/spoof_guard.dart';
import '../models/models.dart';
import '../theme/liveness_theme.dart';
import 'liveness_overlay.dart';

part 'liveness_controller.dart';

/// Signature for overriding parts of the built-in UI.
typedef LivenessWidgetBuilder = Widget Function(
  BuildContext context,
  LivenessSessionState state,
);

/// Drop-in liveness detection widget.
///
/// ```dart
/// LivenessDetector(
///   config: LivenessConfig(
///     actions: [LivenessAction.blink, LivenessAction.smile],
///     capture: {CaptureType.images},
///   ),
///   onResult: (result) async { /* send to your backend */ },
/// )
/// ```
class LivenessDetector extends StatefulWidget {
  const LivenessDetector({
    super.key,
    required this.config,
    required this.onResult,
    this.theme = const LivenessTheme(),
    this.onActionStarted,
    this.onActionCompleted,
    this.onError,
    this.overlayBuilder,
    this.instructionBuilder,
    this.showCloseButton = true,
    this.cameraResolution = ResolutionPreset.high,
    this.showDebugOverlay = false,
    this.controller,
    this.targetRegion,
    this.instructionAlignment = const Alignment(0, 0.72),
    this.closeButtonBuilder,
  });

  /// Read once, when the widget is first inserted. Changing it on a
  /// rebuild has no effect on a running session; give the widget a new
  /// `key` to start a fresh session with a different config.
  final LivenessConfig config;

  /// Called exactly once when the session ends: success, failure, or
  /// cancel — including when the widget is removed before the session
  /// finished (route popped, system back).
  ///
  /// In that last case the result is `cancelled` with
  /// `metadata['cancelledBy'] == 'dispose'`, it is delivered synchronously
  /// from `dispose()` (not awaited), and **the widget's `BuildContext` is
  /// already unmounted**. Guard navigation with `context.mounted`, e.g.
  /// `if (context.mounted) Navigator.pop(context, result);`. Captures still
  /// being encoded at that moment are not included.
  ///
  /// `metadata['cancelledBy']` is `'user'` (close button or
  /// [LivenessController.cancel]), `'lifecycle'` (app sent to background),
  /// `'restart'` ([LivenessController.restart]) or `'dispose'`.
  final FutureOr<void> Function(LivenessResult result) onResult;

  final LivenessTheme theme;

  /// Fired when an action becomes the current instruction.
  ///
  /// May be sync or async; the return value is intentionally NOT awaited —
  /// detection must never stall on integrator code. Kick off long work
  /// (uploads, analytics) freely; it runs concurrently with the session.
  final FutureOr<void> Function(LivenessAction action, int index)?
      onActionStarted;

  /// Fired once each time an action is successfully completed, in execution
  /// order (index is the position in the executed sequence).
  ///
  /// Same contract as [onActionStarted]: sync or async, never awaited.
  /// For the captured frame belonging to this action, use the result in
  /// [onResult] — images are tagged with their action.
  final FutureOr<void> Function(LivenessAction action, int index)?
      onActionCompleted;

  final void Function(Object error, StackTrace stackTrace)? onError;

  /// Replaces the scrim/oval overlay entirely. The built-in oval still
  /// defines where the face must be unless you also set [targetRegion].
  final LivenessWidgetBuilder? overlayBuilder;

  /// Where on screen the face must be, normalised to the widget (0..1),
  /// e.g. `Rect.fromLTWH(0.15, 0.2, 0.7, 0.5)`. Use it with a custom
  /// [overlayBuilder] so your own window drives detection. Its shape is
  /// `theme.ovalShape`. When null, the theme's oval is used.
  final Rect? targetRegion;

  /// Replaces the instruction panel.
  final LivenessWidgetBuilder? instructionBuilder;

  /// Shows the close button (built-in, or [closeButtonBuilder]'s).
  final bool showCloseButton;

  /// Builds your own close button; call `onClose` to cancel the session.
  /// Placed at `theme.closeButtonAlignment` inside the safe area.
  final Widget Function(BuildContext context, VoidCallback onClose)?
      closeButtonBuilder;

  /// Where the instruction panel sits.
  final AlignmentGeometry instructionAlignment;

  final ResolutionPreset cameraResolution;

  /// Show live detection values on screen (euler angles, eye/smile
  /// probabilities, brightness, sharpness, replay-guard counters). For
  /// development and threshold tuning — leave off in production.
  final bool showDebugOverlay;

  /// Optional handle to read state, cancel or restart from outside the
  /// widget (e.g. a custom close button when [showCloseButton] is false).
  /// When null, the widget uses an internal one.
  final LivenessController? controller;

  @override
  State<LivenessDetector> createState() => _LivenessDetectorState();
}

class _LivenessDetectorState extends State<LivenessDetector> {
  LivenessController? _internalController;
  int _generation = 0;

  LivenessController get _controller =>
      widget.controller ?? (_internalController ??= LivenessController());

  @override
  void initState() {
    super.initState();
    _controller._host = this;
  }

  @override
  void didUpdateWidget(LivenessDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.controller ?? _internalController;
    if (old != _controller) {
      old?._host = null;
      if (old != null &&
          old == _internalController &&
          widget.controller != null) {
        _internalController = null;
        old.dispose();
      }
      _controller._host = this;
    }
  }

  /// Ends the current run (its result is still delivered) and starts a new
  /// one with a fresh session, session ID and shuffle.
  Future<void> _restart() {
    _controller._currentRun?._markRestart();
    final started = _controller._expectRun();
    setState(() => _generation++);
    return started;
  }

  @override
  void dispose() {
    if (_controller._host == this) _controller._host = null;
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _LivenessRun(
        key: ValueKey(_generation),
        detector: widget,
        controller: _controller,
      );
}

/// One liveness session. Replaced wholesale (new key) on restart, so no
/// per-session state can leak into the next session.
class _LivenessRun extends StatefulWidget {
  const _LivenessRun({
    super.key,
    required this.detector,
    required this.controller,
  });

  final LivenessDetector detector;
  final LivenessController controller;

  @override
  State<_LivenessRun> createState() => _LivenessRunState();
}

class _LivenessRunState extends State<_LivenessRun>
    with WidgetsBindingObserver {
  LivenessDetector get _d => widget.detector;

  late final LivenessFrameSource _source;
  bool _sourceReady = false;
  late LivenessSession _session;

  late final DateTime _startedAt;

  bool _busy = false;
  bool _finished = false;
  bool _resultDelivered = false;
  LivenessResult? _builtResult;
  String? _cancelledBy;
  Object? _lastFrame;

  /// The frame most recently handed to the session (i.e. what the
  /// detectors actually judged), and the latest peak frame for the
  /// current action.
  Object? _analysedFrame;
  ({Object frame, int index, int timestampMs})? _peak;
  final List<CapturedImage> _images = [];
  final List<CapturedImage> _frames = [];
  final List<Future<void>> _pendingEncodes = [];
  int _lastSeqCaptureMs = 0;
  int _seqInFlight = 0;
  Timer? _ticker;
  final Map<String, Object?> _extraMetadata = {};
  String? _videoPath;

  final SpoofGuard _spoofGuard = SpoofGuard();
  FlashChallenge? _flashChallenge;
  final ValueNotifier<Color?> _flashTint = ValueNotifier(null);
  Size? _viewSize;
  double _flashPenalty = 0;
  late final String _sessionId;
  FrameQuality? _lastQuality;
  FaceSnapshot? _lastSnapshot;
  int _qualityViolations = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startedAt = DateTime.now();
    _sessionId = _generateSessionId();
    _source = createFrameSource(_d.config, _d.cameraResolution);
    try {
      _session = LivenessSession(_d.config);
    } on ArgumentError catch (e, st) {
      // Invalid config: never touch the camera. A placeholder session
      // carries the failed state so the UI and result path work as usual.
      _configError = (e, st);
      _session = LivenessSession(
        const LivenessConfig(actions: [LivenessAction.blink]),
      );
    }
    _session.addEventListener(_onSessionEvent);
    _session.state.addListener(_onStateChanged);
    widget.controller._attach(this);
    _init();
  }

  void _onStateChanged() => widget.controller._scheduleNotify();

  @override
  void didUpdateWidget(_LivenessRun oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._detach(this);
      widget.controller._attach(this);
    }
  }

  /// Called just before a restart replaces this run.
  void _markRestart() {
    if (!_finished && !_session.isTerminal) _cancelledBy = 'restart';
  }

  (ArgumentError, StackTrace)? _configError;

  Future<void> _init() async {
    final configError = _configError;
    if (configError != null) {
      final (error, stackTrace) = configError;
      _d.onError?.call(error, stackTrace);
      _extraMetadata['configError'] = error.toString();
      _session.systemError();
      widget.controller._runStarted(this);
      return;
    }
    if (_d.config.boostScreenBrightness) {
      // Best-effort: brightness control can be unavailable (e.g. some
      // OEMs); never block (or even delay) the session on it.
      try {
        unawaited(ScreenBrightness.instance
            .setApplicationScreenBrightness(1.0)
            .catchError((Object _) {}));
      } catch (_) {}
    }
    try {
      await _source.start(
        _onFrame,
        onError: (e, st) {
          _d.onError?.call(e, st);
          _session.systemError();
        },
      );
      if (!mounted) return;
      _sourceReady = true;
      widget.controller._runStarted(this);

      _session.start();
      // Timeouts must fire even if the camera stops delivering frames.
      _ticker = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _session.tick(_source.elapsedMs),
      );
      setState(() {});
    } catch (e, st) {
      _d.onError?.call(e, st);
      _session.systemError();
      if (mounted) widget.controller._runStarted(this);
    }
  }

  static String _generateSessionId() {
    final random = Random.secure();
    final suffix = List.generate(
      8,
      (_) => random.nextInt(16).toRadixString(16),
    ).join().toUpperCase();
    final stamp = DateTime.now()
        .millisecondsSinceEpoch
        .toRadixString(16)
        .toUpperCase()
        .padLeft(12, '0');
    return 'LV-$stamp-$suffix';
  }

  int _lastProcessedMs = 0;

  Future<void> _onFrame(Object image) async {
    _lastFrame = image;
    if (_finished) return;

    // Flash challenge active: sample colors on every frame, skip ML.
    final challenge = _flashChallenge;
    if (challenge != null) {
      final rgb = _source.sampleRgb(image);
      if (rgb != null) challenge.addSample(rgb);
      return;
    }

    _maybeCaptureSequenceFrame(image);
    if (_busy) return;

    // Throttle ML to ~10 fps.
    final now = _source.elapsedMs;
    if (now - _lastProcessedMs < 100) return;
    _lastProcessedMs = now;
    _busy = true;

    try {
      // Cheap quality metrics + replay hash (subsampled luma, <1 ms).
      final config = _d.config;
      FrameQuality? quality;
      if (config.enableQualityChecks || config.enableReplayGuard) {
        quality = _source.analyzeQuality(image);
        _lastQuality = quality;
      }

      // Unusable frame: pause with guidance rather than running detection
      // on garbage. Skips the (pointless) ML call entirely.
      if (config.enableQualityChecks && quality != null) {
        final qualityIssue = quality.issueFor(config);
        if (qualityIssue != null) {
          _qualityViolations++;
          _analysedFrame = image;
          _session.onFrame(
            faces: const [],
            faceInPosition: false,
            timestampMs: now,
            guidance: qualityIssue,
            qualityHold: true,
          );
          if (_d.showDebugOverlay && mounted) setState(() {});
          return;
        }
      }

      final snapshots = await _source.detectFaces(image, now);
      if (!mounted || _finished) return;

      final relevant = LivenessSession.relevantFaces(
        snapshots,
        minAreaRatio: config.tuning.secondaryFaceMinAreaRatio,
      );

      final primary = relevant.isEmpty ? null : relevant.first;
      _lastSnapshot = primary;

      _spoofGuard.onFrame(hash: quality?.hash, face: primary);

      final positionIssue = primary == null
          ? FaceGuidance.noFace
          : relevant.length > 1
              ? FaceGuidance.multipleFaces
              : _positionIssueFor(primary);

      _analysedFrame = image;
      _session.onFrame(
        faces: relevant,
        faceInPosition: positionIssue == null,
        timestampMs: now,
        guidance: positionIssue ?? FaceGuidance.none,
        spoofSuspected: config.enableReplayGuard && _spoofGuard.replaySuspected,
      );
      if (_d.showDebugOverlay && mounted) setState(() {});
    } catch (e, st) {
      _d.onError?.call(e, st);
    } finally {
      _busy = false;
    }
  }

  /// Maps the on-screen target (the theme's oval, or [LivenessDetector
  /// .targetRegion]) into face space. Null until the view size and camera
  /// geometry are known.
  DetectionGeometry? _geometry() {
    final view = _viewSize;
    final camera = _source.geometry;
    if (view == null || view.isEmpty || camera == null) return null;
    return DetectionGeometry(
      viewSize: view,
      faceSpaceSize: camera.faceSpaceSize,
      rotationDegrees: camera.rotationDegrees,
      mirrored: camera.mirrored,
    );
  }

  /// The specific positioning problem, or null when the face is in the
  /// target drawn on screen.
  FaceGuidance? _positionIssueFor(FaceSnapshot face) {
    final geometry = _geometry();
    final view = _viewSize;
    if (geometry == null || view == null) return _fallbackPositionIssue(face);
    final screenRect = _d.targetRegion ??
        LivenessOverlayPainter.normalizedTargetRect(view, _d.theme);
    final zone = TargetZone(
      geometry.viewRectToFace(screenRect),
      _d.theme.ovalShape,
    );
    return zone.issueFor(face, _d.config.tuning);
  }

  /// Used only before the view and camera geometry are known: the face
  /// must be near the image centre at a sensible size. Box *area* works
  /// whether coordinates are portrait or landscape.
  FaceGuidance? _fallbackPositionIssue(FaceSnapshot face) {
    final box = face.boundingBox;
    final area = box.width * box.height;
    if (area <= 0.04) return FaceGuidance.tooFar;
    if (area >= 0.75) return FaceGuidance.tooClose;
    final cx = box.center.dx;
    final cy = box.center.dy;
    if ((cx - 0.5).abs() >= 0.25 || (cy - 0.5).abs() >= 0.25) {
      return FaceGuidance.notCentered;
    }
    return null;
  }

  void _onSessionEvent(LivenessEvent event) {
    switch (event) {
      case ReferenceReadyEvent():
        if (_d.config.captureImages &&
            _d.config.captureReferenceImage) {
          _captureFrame(null, kind: CaptureKind.reference);
        }
      case ActionStartedEvent(:final action, :final index):
        _peak = null;
        _d.onActionStarted?.call(action, index);
      case ActionPeakEvent(:final index, :final timestampMs):
        final frame = _analysedFrame;
        if (frame != null) {
          _peak = (frame: frame, index: index, timestampMs: timestampMs);
        }
      case ActionCompletedEvent(:final action, :final index):
        _d.onActionCompleted?.call(action, index);
        if (_d.config.captureImages) {
          final peak = _peak;
          if (_d.config.captureAtPeak &&
              peak != null &&
              peak.index == index) {
            _captureFrame(
              action,
              kind: CaptureKind.peak,
              frame: peak.frame,
              timestampMs: peak.timestampMs,
            );
          } else {
            _captureFrame(action, kind: CaptureKind.completion);
          }
        }
        _peak = null;
      case SessionCompletedEvent():
        final assisted =
            _d.config.cameraMode == LivenessCameraMode.assisted;
        if (_d.config.enableFlashChallenge && !assisted) {
          _runFlashChallenge().whenComplete(() => _finish(success: true));
        } else {
          if (_d.config.enableFlashChallenge && assisted) {
            // Screen faces the operator, not the subject — the challenge
            // is physically meaningless here.
            _extraMetadata['flashChallenge'] = 'skippedAssistedMode';
          }
          _finish(success: true);
        }
      case SessionFailedEvent(:final reason):
        _finish(success: false, reason: reason);
    }
  }

  /// Per-action capture: copy the frame cheaply, encode in a background
  /// isolate, collect the result. Order is restored by timestamp at finish.
  void _captureFrame(
    LivenessAction? action, {
    required CaptureKind kind,
    Object? frame,
    int? timestampMs,
  }) {
    final source = frame ?? _analysedFrame ?? _lastFrame;
    if (source == null) return;
    final ts = timestampMs ?? _source.elapsedMs;
    final maxDimension = _d.config.maxImageDimension;
    final quality = _d.config.jpegQuality;
    // Copies the pixels now; the encode itself runs in an isolate.
    final encoding = _source.encodeJpeg(
      source,
      maxDimension: maxDimension,
      quality: quality,
    );
    _pendingEncodes.add(() async {
      Uint8List? bytes;
      try {
        bytes = await encoding;
      } catch (e, st) {
        _d.onError?.call(e, st);
        // Isolate failed: encode synchronously rather than lose the capture.
        try {
          bytes = await _source.encodeJpeg(
            source,
            maxDimension: maxDimension,
            quality: quality,
            background: false,
          );
        } catch (e, st) {
          _d.onError?.call(e, st);
        }
      }
      if (bytes != null) {
        _images.add(
          CapturedImage(
            bytes: bytes,
            action: action,
            timestampMs: ts,
            kind: kind,
          ),
        );
      }
    }());
  }

  /// Steady-rate frame-sequence capture ([CaptureType.frameSequence]).
  void _maybeCaptureSequenceFrame(Object image) {
    if (!_d.config.captureFrameSequence) return;
    // Only capture while the session is actively verifying.
    final phase = _session.current.phase;
    if (phase != LivenessPhase.performingAction &&
        phase != LivenessPhase.awaitingNeutral) {
      return;
    }
    final now = _source.elapsedMs;
    final intervalMs = 1000 ~/ _d.config.frameSequenceFps.clamp(1, 15);
    if (now - _lastSeqCaptureMs < intervalMs) return;
    if (_frames.length + _seqInFlight >= _d.config.frameSequenceMaxFrames) {
      return;
    }
    if (_seqInFlight >= 3) return; // don't queue up if encoding lags

    _lastSeqCaptureMs = now;
    _seqInFlight++;
    final encoding = _source.encodeJpeg(
      image,
      maxDimension: _d.config.maxImageDimension,
      quality: _d.config.jpegQuality,
    );
    _pendingEncodes.add(() async {
      try {
        final bytes = await encoding;
        if (bytes != null) {
          _frames.add(
            CapturedImage(
              bytes: bytes,
              action: null,
              timestampMs: now,
              kind: CaptureKind.sequence,
            ),
          );
        }
      } catch (e, st) {
        // Sequence frames are lossy by design — skip on failure, no
        // synchronous fallback (that would jank the pipeline repeatedly).
        _d.onError?.call(e, st);
      } finally {
        _seqInFlight--;
      }
    }());
  }

  Future<void> _finish({
    required bool success,
    LivenessFailureReason? reason,
  }) async {
    if (_finished) return;
    _finished = true;

    _ticker?.cancel();
    try {
      _videoPath = await _source.stop();
    } catch (e, st) {
      _d.onError?.call(e, st);
    }
    _extraMetadata.addAll(_source.metadata);

    // Wait for background JPEG encodes to drain (bounded).
    await Future.wait(_pendingEncodes)
        .timeout(const Duration(seconds: 5), onTimeout: () => const []);

    final result = _builtResult = _buildResult(success: success, reason: reason);

    // Let the final UI state (success/failure) render briefly before
    // handing off.
    await Future<void>.delayed(_d.theme.resultHoldDuration);
    if (_resultDelivered) return; // disposed meanwhile; already delivered
    _resultDelivered = true;
    await _d.onResult(result);
  }

  /// Snapshot of everything collected so far. Synchronous, so `dispose`
  /// can use it.
  LivenessResult _buildResult({
    required bool success,
    LivenessFailureReason? reason,
  }) {
    final images = List.of(_images)
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    final frames = List.of(_frames)
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));

    // Composite confidence: clean sessions on a real camera score ≥ 0.9.
    final completedRatio = _d.config.actions.isEmpty
        ? 0.0
        : _session.current.completedActions.length /
            _d.config.actions.length;
    var confidence = success ? 1.0 : 0.5 * completedRatio;
    confidence -= _spoofGuard.confidencePenalty;
    confidence -= (_qualityViolations * 0.005).clamp(0.0, 0.2);
    confidence -= _flashPenalty;
    confidence = confidence.clamp(0.0, 1.0);

    return LivenessResult(
      success: success,
      completedActions: _session.current.completedActions,
      failureReason: reason,
      images: List.unmodifiable(images),
      frameSequence: List.unmodifiable(frames),
      videoPath: _videoPath,
      startedAt: _startedAt,
      finishedAt: DateTime.now(),
      confidenceScore: confidence,
      sessionId: _sessionId,
      metadata: {
        ..._session.metadata,
        ..._extraMetadata,
        ..._spoofGuard.metadata,
        'confidence_qualityViolations': _qualityViolations,
        'cameraMode': _d.config.cameraMode.name,
        if (reason == LivenessFailureReason.cancelled)
          'cancelledBy': _cancelledBy ?? 'user',
      },
    );
  }

  /// ~2.6 s: 600 ms untinted baseline, then three ~650 ms color tints in a
  /// random order. Camera keeps streaming; [_onFrame] collects color
  /// samples. Result is a confidence penalty + metadata, never a hard fail.
  Future<void> _runFlashChallenge() async {
    if (_finished) return;
    final challenge = FlashChallenge();
    _flashChallenge = challenge;
    try {
      challenge.phase = -1;
      _flashTint.value = null;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      for (var i = 0; i < challenge.colors.length; i++) {
        if (_finished || !mounted) break;
        challenge.phase = i;
        _flashTint.value = challenge.colors[i].tint;
        await Future<void>.delayed(const Duration(milliseconds: 650));
      }
    } finally {
      _flashTint.value = null;
      _flashChallenge = null;
    }
    final passed = challenge.evaluate();
    _extraMetadata.addAll(challenge.metadataFor(passed));
    if (passed == false) _flashPenalty = 0.35;
  }

  void _cancel({String by = 'user'}) {
    if (_finished || _session.isTerminal) return;
    _cancelledBy = by;
    _session.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !_finished) {
      _cancel(by: 'lifecycle');
    }
  }

  /// Delivers the result from `dispose()`: synchronously, never awaited,
  /// and shielded so a throwing `onResult` can't break teardown.
  void _deliverOnDispose() {
    if (_resultDelivered) return;
    _resultDelivered = true;
    // A session that already ended keeps its real outcome (e.g. a success
    // whose result hold was cut short); otherwise it's a cancel.
    final state = _session.current;
    final LivenessResult result;
    if (_builtResult != null) {
      result = _builtResult!;
    } else if (state.phase == LivenessPhase.completed) {
      result = _buildResult(success: true);
    } else if (state.phase == LivenessPhase.failed) {
      result = _buildResult(success: false, reason: state.failureReason);
    } else {
      _cancelledBy ??= 'dispose';
      result = _buildResult(
        success: false,
        reason: LivenessFailureReason.cancelled,
      );
    }
    try {
      final pending = _d.onResult(result);
      if (pending is Future<void>) {
        pending.catchError((Object e, StackTrace st) {
          _d.onError?.call(e, st);
        });
      }
    } catch (e, st) {
      _d.onError?.call(e, st);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _finished = true;
    _deliverOnDispose();
    widget.controller._detach(this);
    _ticker?.cancel();
    _flashTint.dispose();
    if (_d.config.boostScreenBrightness) {
      // Restore the user's brightness (fire-and-forget).
      ScreenBrightness.instance
          .resetApplicationScreenBrightness()
          .catchError((_) {});
    }
    final videoPath = _videoPath;
    if (_d.config.autoDeleteVideo && videoPath != null) {
      // Fire-and-forget; the file is in temp storage anyway.
      File(videoPath).delete().catchError((_) => File(videoPath));
    }
    _source.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _sourceReady ? _source.buildPreview(context) : null;
    return LayoutBuilder(builder: (context, constraints) {
      // Detection maps the on-screen target using the size it's drawn at.
      _viewSize = constraints.biggest;
      return _buildLayers(preview);
    });
  }

  Widget _buildLayers(Widget? preview) {
    return ValueListenableBuilder<LivenessSessionState>(
      valueListenable: _session.state,
      builder: (context, state, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            preview ?? const ColoredBox(color: Colors.black),

            // Overlay (scrim + oval + progress).
            if (_d.overlayBuilder != null)
              _d.overlayBuilder!(context, state)
            else
              CustomPaint(
                painter: LivenessOverlayPainter(
                  theme: _d.theme,
                  faceInPosition: state.faceInPosition,
                  progress: state.phase == LivenessPhase.completed
                      ? 1
                      : state.overallProgress,
                  phase: state.phase,
                ),
              ),

            // Instructions.
            Align(
              alignment: _d.instructionAlignment,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _d.instructionBuilder != null
                    ? _d.instructionBuilder!(context, state)
                    : DefaultInstructionPanel(
                        state: state,
                        theme: _d.theme,
                      ),
              ),
            ),

            // Color-flash challenge tint (drawn over everything except the
            // close button and debug panel).
            ValueListenableBuilder<Color?>(
              valueListenable: _flashTint,
              builder: (context, tint, _) => IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  color: tint?.withValues(alpha: _d.theme.flashTintOpacity) ??
                      Colors.transparent,
                  alignment: Alignment.center,
                  child: tint == null
                      ? null
                      : Text(
                          _d.theme.strings.holdStill,
                          style: _d.theme.instructionStyle,
                        ),
                ),
              ),
            ),

            if (_d.showCloseButton)
              SafeArea(
                child: Align(
                  alignment: _d.theme.closeButtonAlignment,
                  child: _d.closeButtonBuilder?.call(context, _cancel) ??
                      IconButton(
                        icon: Icon(Icons.close, color: _d.theme.closeIconColor),
                        tooltip: _d.theme.strings.close,
                        onPressed: _cancel,
                      ),
                ),
              ),

            if (_d.showDebugOverlay)
              IgnorePointer(
                child: CustomPaint(
                  painter: _DebugFaceBoxPainter(
                    box: _lastSnapshot?.boundingBox,
                    geometry: _geometry(),
                  ),
                ),
              ),

            if (_d.showDebugOverlay)
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: _DebugPanel(
                    snapshot: _lastSnapshot,
                    quality: _lastQuality,
                    spoofGuard: _spoofGuard,
                    state: state,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Draws the detected face box where the detector thinks it is on screen.
/// If it sits on the face, the screen → camera mapping is right for this
/// device.
class _DebugFaceBoxPainter extends CustomPainter {
  _DebugFaceBoxPainter({required this.box, required this.geometry});

  final Rect? box;
  final DetectionGeometry? geometry;

  @override
  void paint(Canvas canvas, Size size) {
    final b = box;
    final g = geometry;
    if (b == null || g == null) return;
    final r = g.faceRectToView(b);
    canvas.drawRect(
      Rect.fromLTRB(
        r.left * size.width,
        r.top * size.height,
        r.right * size.width,
        r.bottom * size.height,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.greenAccent,
    );
  }

  @override
  bool shouldRepaint(_DebugFaceBoxPainter old) =>
      old.box != box || old.geometry != geometry;
}

/// Live detection values for development and threshold tuning.
class _DebugPanel extends StatelessWidget {
  const _DebugPanel({
    required this.snapshot,
    required this.quality,
    required this.spoofGuard,
    required this.state,
  });

  final FaceSnapshot? snapshot;
  final FrameQuality? quality;
  final SpoofGuard spoofGuard;
  final LivenessSessionState state;

  String _fmt(double? v) => v == null ? '—' : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final q = quality;
    final lines = <String>[
      'phase: ${state.phase.name}',
      'guidance: ${state.guidance.name}',
      if (s != null) ...[
        'yaw: ${_fmt(s.headEulerAngleY)}  pitch: ${_fmt(s.headEulerAngleX)}',
        'roll: ${_fmt(s.headEulerAngleZ)}',
        'smile: ${_fmt(s.smileProbability)}',
        'eyeL: ${_fmt(s.leftEyeOpenProbability)}  eyeR: ${_fmt(s.rightEyeOpenProbability)}',
        'mouth: ${_fmt(s.mouthOpenRatio)}',
      ] else
        'face: none',
      if (q != null)
        'light: ${_fmt(q.brightness)}  sharp: ${_fmt(q.sharpness)}',
      'dupes: ${spoofGuard.totalDuplicates}  '
          'still: ${spoofGuard.lowMotionWindows}/${spoofGuard.totalMotionWindows}',
    ];

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        lines.join('\n'),
        style: const TextStyle(
          color: Colors.greenAccent,
          fontSize: 11,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
