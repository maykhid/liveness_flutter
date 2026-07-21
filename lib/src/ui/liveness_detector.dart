import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../camera/face_mapper.dart';
import '../camera/frame_converter.dart';
import '../camera/frame_quality.dart';
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

  final LivenessConfig config;

  /// Called exactly once when the session ends (success, failure, or cancel).
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
  CameraController? _cameraController;
  FaceDetector? _faceDetector;
  FrameConverter? _converter;
  FaceMapper? _mapper;
  late LivenessSession _session;

  final Stopwatch _clock = Stopwatch()..start();
  late final DateTime _startedAt;

  bool _busy = false;
  bool _finished = false;
  CameraImage? _lastFrame;
  final List<CapturedImage> _images = [];
  final List<CapturedImage> _frames = [];
  final List<Future<void>> _pendingEncodes = [];
  int _lastSeqCaptureMs = 0;
  int _seqInFlight = 0;
  int _framesSeen = 0;
  bool _videoActive = false;
  Timer? _videoWatchdog;
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

  bool get _needsContours =>
      widget.config.actions.contains(LivenessAction.openMouth) ||
      widget.config.actions.contains(LivenessAction.fullTeethSmile);

  bool get _needsLandmarks =>
      widget.config.actions.contains(LivenessAction.drawCircleWithNose);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startedAt = DateTime.now();
    _sessionId = _generateSessionId();
    _session = LivenessSession(widget.config);
    _session.addEventListener(_onSessionEvent);
    _init();
  }

  Future<void> _init() async {
    if (widget.config.boostScreenBrightness) {
      // Best-effort: brightness control can be unavailable (e.g. some
      // OEMs); never block the session on it.
      try {
        await ScreenBrightness.instance.setApplicationScreenBrightness(1.0);
      } catch (_) {}
    }
    try {
      final assisted = widget.config.cameraMode == LivenessCameraMode.assisted;
      final wantedDirection =
          assisted ? CameraLensDirection.back : CameraLensDirection.front;

      final cameras = await availableCameras();
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == wantedDirection,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        camera,
        widget.cameraResolution,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21, // ignored on iOS
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      // Assisted mode: the screen faces the operator, so the torch does
      // the face-lighting job instead. Best-effort (not all devices).
      if (assisted && widget.config.assistedTorchEnabled) {
        try {
          await controller.setFlashMode(FlashMode.torch);
        } catch (_) {}
      }

      _cameraController = controller;
      _converter = FrameConverter(camera: camera, controller: controller);
      // The back camera isn't mirrored like the front one, so the
      // left/right sign convention flips in assisted mode.
      final effectiveMirror = camera.lensDirection == CameraLensDirection.front
          ? widget.config.mirrorYaw
          : !widget.config.mirrorYaw;
      _mapper = FaceMapper(
        mirrorYaw: effectiveMirror,
        uprightCoordinates: Platform.isAndroid,
      );
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          // ML Kit: contour detection should not be combined with tracking
          // (contours may come back empty). We don't use tracking IDs.
          enableTracking: false,
          enableContours: _needsContours,
          enableLandmarks: _needsLandmarks,
          performanceMode: FaceDetectorMode.fast,
        ),
      );

      if (widget.config.captureVideo) {
        await controller.startVideoRecording(onAvailable: _onFrame);
        _videoActive = true;
        // Some Android devices can't stream analysis frames while
        // recording (CameraX use-case limits). If no frames arrive
        // shortly, drop video and continue the session on a plain stream
        // rather than hanging. Reported via metadata['videoUnavailable'].
        _videoWatchdog = Timer(const Duration(milliseconds: 2500), () async {
          if (_framesSeen > 0 || _finished || !mounted) return;
          try {
            await controller.stopVideoRecording(); // discard
          } catch (_) {}
          _videoActive = false;
          _extraMetadata['videoUnavailable'] = true;
          try {
            await controller.startImageStream(_onFrame);
          } catch (e, st) {
            widget.onError?.call(e, st);
            _session.systemError();
          }
        });
      } else {
        await controller.startImageStream(_onFrame);
      }

      _session.start();
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

  Future<void> _onFrame(CameraImage image) async {
    _lastFrame = image;
    _framesSeen++;
    if (_finished) return;

    // Flash challenge active: sample colors on every frame, skip ML.
    final challenge = _flashChallenge;
    if (challenge != null) {
      final rgb = FlashChallenge.sampleCenterRgb(image);
      if (rgb != null) challenge.addSample(rgb);
      return;
    }

    _maybeCaptureSequenceFrame(image);
    if (_busy) return;

    // Throttle ML to ~10 fps.
    final now = _clock.elapsedMilliseconds;
    if (now - _lastProcessedMs < 100) return;
    _lastProcessedMs = now;
    _busy = true;

    try {
      final converter = _converter;
      final detector = _faceDetector;
      final mapper = _mapper;
      if (converter == null || detector == null || mapper == null) return;

      // Cheap quality metrics + replay hash (subsampled luma, <1 ms).
      final config = widget.config;
      FrameQuality? quality;
      if (config.enableQualityChecks || config.enableReplayGuard) {
        quality = FrameQualityAnalyzer.analyze(image);
        _lastQuality = quality;
      }

      // Unusable frame: pause with guidance rather than running detection
      // on garbage. Skips the (pointless) ML call entirely.
      if (config.enableQualityChecks && quality != null) {
        final FaceGuidance? qualityIssue =
            quality.brightness < config.brightnessMin
                ? FaceGuidance.lowLight
                : quality.brightness > config.brightnessMax
                    ? FaceGuidance.lowLight
                    : quality.sharpness < config.sharpnessMin
                        ? FaceGuidance.blurry
                        : null;
        if (qualityIssue != null) {
          _qualityViolations++;
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

      final inputImage = converter.toInputImage(image);
      if (inputImage == null) return;

      final faces = await detector.processImage(inputImage);
      if (!mounted || _finished) return;

      final metadata = inputImage.metadata!;
      final snapshots = faces
          .map((f) => mapper.map(
                f,
                imageSize: metadata.size,
                rotation: metadata.rotation,
                timestampMs: now,
              ))
          .toList();

      final primary = snapshots.isEmpty ? null : snapshots.first;
      _lastSnapshot = primary;

      _spoofGuard.onFrame(hash: quality?.hash, face: primary);

      final positionIssue = primary == null
          ? FaceGuidance.noFace
          : snapshots.length > 1
              ? FaceGuidance.multipleFaces
              : _positionIssue(primary);

      _session.onFrame(
        faces: snapshots,
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
          _captureFrame(null);
        }
      case ActionStartedEvent(:final action, :final index):
        widget.onActionStarted?.call(action, index);
      case ActionCompletedEvent(:final action, :final index):
        widget.onActionCompleted?.call(action, index);
        if (widget.config.captureImages) _captureFrame(action);
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
  void _captureFrame(LivenessAction? action) {
    final frame = _lastFrame;
    final converter = _converter;
    if (frame == null || converter == null) return;
    final raw = converter.toRaw(frame);
    if (raw == null) return;
    final ts = _clock.elapsedMilliseconds;
    final request = EncodeRequest(
      raw,
      maxDimension: widget.config.maxImageDimension,
      quality: widget.config.jpegQuality,
    );
    _pendingEncodes.add(() async {
      Uint8List? bytes;
      try {
        bytes = await compute(encodeRawFrame, request);
      } catch (e, st) {
        widget.onError?.call(e, st);
        // Isolate failed: encode synchronously rather than lose the capture.
        bytes = encodeRawFrame(request);
      }
      if (bytes != null) {
        _images.add(
          CapturedImage(bytes: bytes, action: action, timestampMs: ts),
        );
      }
    }());
  }

  /// Steady-rate frame-sequence capture ([CaptureType.frameSequence]).
  void _maybeCaptureSequenceFrame(CameraImage image) {
    if (!widget.config.captureFrameSequence) return;
    // Only capture while the session is actively verifying.
    final phase = _session.current.phase;
    if (phase != LivenessPhase.performingAction &&
        phase != LivenessPhase.awaitingNeutral) {
      return;
    }
    final now = _clock.elapsedMilliseconds;
    final intervalMs = 1000 ~/ widget.config.frameSequenceFps.clamp(1, 15);
    if (now - _lastSeqCaptureMs < intervalMs) return;
    if (_frames.length + _seqInFlight >= widget.config.frameSequenceMaxFrames) {
      return;
    }
    if (_seqInFlight >= 3) return; // don't queue up if encoding lags

    final raw = _converter?.toRaw(image);
    if (raw == null) return;
    _lastSeqCaptureMs = now;
    _seqInFlight++;
    final request = EncodeRequest(
      raw,
      maxDimension: widget.config.maxImageDimension,
      quality: widget.config.jpegQuality,
    );
    _pendingEncodes.add(() async {
      try {
        final bytes = await compute(encodeRawFrame, request);
        if (bytes != null) {
          _frames.add(
            CapturedImage(bytes: bytes, action: null, timestampMs: now),
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

    _videoWatchdog?.cancel();
    final controller = _cameraController;
    try {
      if (controller != null && controller.value.isInitialized) {
        // Torch off before teardown (assisted mode).
        try {
          await controller.setFlashMode(FlashMode.off);
        } catch (_) {}
        if (_videoActive && controller.value.isRecordingVideo) {
          final file = await controller.stopVideoRecording();
          // Guard against silently-broken recordings (empty files).
          if (await File(file.path).length() > 0) {
            _videoPath = file.path;
          } else {
            _extraMetadata['videoUnavailable'] = true;
          }
        } else if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      }
    } catch (e, st) {
      widget.onError?.call(e, st);
    }

    // Wait for background JPEG encodes to drain (bounded).
    await Future.wait(_pendingEncodes)
        .timeout(const Duration(seconds: 5), onTimeout: () => const []);
    _images.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    _frames.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));

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

    final result = LivenessResult(
      success: success,
      completedActions: _session.current.completedActions,
      failureReason: reason,
      images: List.unmodifiable(_images),
      frameSequence: List.unmodifiable(_frames),
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
      },
    );

    // Let the final UI state (success/failure) render briefly before
    // handing off.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (mounted) await widget.onResult(result);
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

  void _cancel() => _session.cancel();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !_finished) {
      _session.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _finished = true;
    _videoWatchdog?.cancel();
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
    _cameraController?.dispose();
    _faceDetector?.close();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;
    return ValueListenableBuilder<LivenessSessionState>(
      valueListenable: _session.state,
      builder: (context, state, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null && controller.value.isInitialized)
              _FullScreenPreview(controller: controller)
            else
              const ColoredBox(color: Colors.black),

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

/// Cover-fits the camera preview to the available space.
class _FullScreenPreview extends StatelessWidget {
  const _FullScreenPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final previewRatio = controller.value.aspectRatio;
    // Camera aspect ratio is width/height in landscape sensor terms.
    final scale = size.aspectRatio * previewRatio;
    return Transform.scale(
      scale: scale < 1 ? 1 / scale : scale,
      child: Center(child: CameraPreview(controller)),
    );
  }
}
