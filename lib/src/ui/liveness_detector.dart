import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart' show ResolutionPreset;
import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../camera/frame_quality.dart';
import '../camera/frame_source.dart';
import '../controller/liveness_session.dart';
import '../detection/flash_challenge.dart';
import '../detection/spoof_guard.dart';
import '../models/models.dart';
import '../theme/liveness_theme.dart';
import 'liveness_overlay.dart';

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
  /// `metadata['cancelledBy']` is `'user'` (close button or controller),
  /// `'lifecycle'` (app sent to background) or `'dispose'`.
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

  /// Replaces the scrim/oval overlay entirely.
  final LivenessWidgetBuilder? overlayBuilder;

  /// Replaces the instruction panel.
  final LivenessWidgetBuilder? instructionBuilder;

  final bool showCloseButton;
  final ResolutionPreset cameraResolution;

  /// Show live detection values on screen (euler angles, eye/smile
  /// probabilities, brightness, sharpness, replay-guard counters). For
  /// development and threshold tuning — leave off in production.
  final bool showDebugOverlay;

  @override
  State<LivenessDetector> createState() => _LivenessDetectorState();
}

class _LivenessDetectorState extends State<LivenessDetector>
    with WidgetsBindingObserver {
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
    _source = createFrameSource(widget.config, widget.cameraResolution);
    try {
      _session = LivenessSession(widget.config);
    } on ArgumentError catch (e, st) {
      // Invalid config: never touch the camera. A placeholder session
      // carries the failed state so the UI and result path work as usual.
      _configError = (e, st);
      _session = LivenessSession(
        const LivenessConfig(actions: [LivenessAction.blink]),
      );
    }
    _session.addEventListener(_onSessionEvent);
    _init();
  }

  (ArgumentError, StackTrace)? _configError;

  Future<void> _init() async {
    final configError = _configError;
    if (configError != null) {
      final (error, stackTrace) = configError;
      widget.onError?.call(error, stackTrace);
      _extraMetadata['configError'] = error.toString();
      _session.systemError();
      return;
    }
    if (widget.config.boostScreenBrightness) {
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
          widget.onError?.call(e, st);
          _session.systemError();
        },
      );
      if (!mounted) return;
      _sourceReady = true;

      _session.start();
      // Timeouts must fire even if the camera stops delivering frames.
      _ticker = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _session.tick(_source.elapsedMs),
      );
      setState(() {});
    } catch (e, st) {
      widget.onError?.call(e, st);
      _session.systemError();
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
      final config = widget.config;
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
          if (widget.showDebugOverlay && mounted) setState(() {});
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
              : _positionIssue(primary);

      _analysedFrame = image;
      _session.onFrame(
        faces: relevant,
        faceInPosition: positionIssue == null,
        timestampMs: now,
        guidance: positionIssue ?? FaceGuidance.none,
        spoofSuspected: config.enableReplayGuard && _spoofGuard.replaySuspected,
      );
      if (widget.showDebugOverlay && mounted) setState(() {});
    } catch (e, st) {
      widget.onError?.call(e, st);
    } finally {
      _busy = false;
    }
  }

  /// Returns the specific positioning problem, or null when the face is
  /// usable. Uses box *area* rather than width so the check works whether
  /// coordinates are in portrait (Android upright) or landscape (iOS
  /// buffer) space.
  FaceGuidance? _positionIssue(FaceSnapshot face) {
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
        if (widget.config.captureImages &&
            widget.config.captureReferenceImage) {
          _captureFrame(null, kind: CaptureKind.reference);
        }
      case ActionStartedEvent(:final action, :final index):
        _peak = null;
        widget.onActionStarted?.call(action, index);
      case ActionPeakEvent(:final index, :final timestampMs):
        final frame = _analysedFrame;
        if (frame != null) {
          _peak = (frame: frame, index: index, timestampMs: timestampMs);
        }
      case ActionCompletedEvent(:final action, :final index):
        widget.onActionCompleted?.call(action, index);
        if (widget.config.captureImages) {
          final peak = _peak;
          if (widget.config.captureAtPeak &&
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
            widget.config.cameraMode == LivenessCameraMode.assisted;
        if (widget.config.enableFlashChallenge && !assisted) {
          _runFlashChallenge().whenComplete(() => _finish(success: true));
        } else {
          if (widget.config.enableFlashChallenge && assisted) {
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
    final maxDimension = widget.config.maxImageDimension;
    final quality = widget.config.jpegQuality;
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
        widget.onError?.call(e, st);
        // Isolate failed: encode synchronously rather than lose the capture.
        try {
          bytes = await _source.encodeJpeg(
            source,
            maxDimension: maxDimension,
            quality: quality,
            background: false,
          );
        } catch (e, st) {
          widget.onError?.call(e, st);
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
    if (!widget.config.captureFrameSequence) return;
    // Only capture while the session is actively verifying.
    final phase = _session.current.phase;
    if (phase != LivenessPhase.performingAction &&
        phase != LivenessPhase.awaitingNeutral) {
      return;
    }
    final now = _source.elapsedMs;
    final intervalMs = 1000 ~/ widget.config.frameSequenceFps.clamp(1, 15);
    if (now - _lastSeqCaptureMs < intervalMs) return;
    if (_frames.length + _seqInFlight >= widget.config.frameSequenceMaxFrames) {
      return;
    }
    if (_seqInFlight >= 3) return; // don't queue up if encoding lags

    _lastSeqCaptureMs = now;
    _seqInFlight++;
    final encoding = _source.encodeJpeg(
      image,
      maxDimension: widget.config.maxImageDimension,
      quality: widget.config.jpegQuality,
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
        widget.onError?.call(e, st);
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
      widget.onError?.call(e, st);
    }
    _extraMetadata.addAll(_source.metadata);

    // Wait for background JPEG encodes to drain (bounded).
    await Future.wait(_pendingEncodes)
        .timeout(const Duration(seconds: 5), onTimeout: () => const []);

    final result = _builtResult = _buildResult(success: success, reason: reason);

    // Let the final UI state (success/failure) render briefly before
    // handing off.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (_resultDelivered) return; // disposed meanwhile; already delivered
    _resultDelivered = true;
    await widget.onResult(result);
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
    final completedRatio = widget.config.actions.isEmpty
        ? 0.0
        : _session.current.completedActions.length /
            widget.config.actions.length;
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
        'cameraMode': widget.config.cameraMode.name,
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
      _cancelledBy = 'dispose';
      result = _buildResult(
        success: false,
        reason: LivenessFailureReason.cancelled,
      );
    }
    try {
      final pending = widget.onResult(result);
      if (pending is Future<void>) {
        pending.catchError((Object e, StackTrace st) {
          widget.onError?.call(e, st);
        });
      }
    } catch (e, st) {
      widget.onError?.call(e, st);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _finished = true;
    _deliverOnDispose();
    _ticker?.cancel();
    _flashTint.dispose();
    if (widget.config.boostScreenBrightness) {
      // Restore the user's brightness (fire-and-forget).
      ScreenBrightness.instance
          .resetApplicationScreenBrightness()
          .catchError((_) {});
    }
    final videoPath = _videoPath;
    if (widget.config.autoDeleteVideo && videoPath != null) {
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
    return ValueListenableBuilder<LivenessSessionState>(
      valueListenable: _session.state,
      builder: (context, state, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            preview ?? const ColoredBox(color: Colors.black),

            // Overlay (scrim + oval + progress).
            if (widget.overlayBuilder != null)
              widget.overlayBuilder!(context, state)
            else
              CustomPaint(
                painter: LivenessOverlayPainter(
                  theme: widget.theme,
                  faceInPosition: state.faceInPosition,
                  progress: state.phase == LivenessPhase.completed
                      ? 1
                      : state.overallProgress,
                  phase: state.phase,
                ),
              ),

            // Instructions.
            Align(
              alignment: const Alignment(0, 0.72),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: widget.instructionBuilder != null
                    ? widget.instructionBuilder!(context, state)
                    : DefaultInstructionPanel(
                        state: state,
                        theme: widget.theme,
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
                  color: tint?.withValues(alpha: .75) ?? Colors.transparent,
                  alignment: Alignment.center,
                  child: tint == null
                      ? null
                      : Text(
                          widget.theme.strings.holdStill,
                          style: widget.theme.instructionStyle,
                        ),
                ),
              ),
            ),

            if (widget.showCloseButton)
              SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: _cancel,
                  ),
                ),
              ),

            if (widget.showDebugOverlay)
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
