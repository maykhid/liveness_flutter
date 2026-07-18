import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../camera/face_mapper.dart';
import '../camera/frame_converter.dart';
import '../controller/liveness_session.dart';
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
    _session = LivenessSession(widget.config);
    _session.addEventListener(_onSessionEvent);
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        front,
        widget.cameraResolution,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21, // ignored on iOS
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      _cameraController = controller;
      _converter = FrameConverter(camera: front, controller: controller);
      _mapper = FaceMapper(
        mirrorYaw: widget.config.mirrorYaw,
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

  int _lastProcessedMs = 0;

  Future<void> _onFrame(CameraImage image) async {
    _lastFrame = image;
    _framesSeen++;
    if (_finished) return;
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
      _session.onFrame(
        faces: snapshots,
        faceInPosition: primary != null && _isInPosition(primary),
        timestampMs: now,
      );
    } catch (e, st) {
      widget.onError?.call(e, st);
    } finally {
      _busy = false;
    }
  }

  /// Face must be roughly centered and large enough. Uses box *area* rather
  /// than width so the check works whether coordinates are in portrait
  /// (Android upright) or landscape (iOS buffer) space.
  bool _isInPosition(FaceSnapshot face) {
    final box = face.boundingBox;
    final cx = box.center.dx;
    final cy = box.center.dy;
    final centered = (cx - 0.5).abs() < 0.25 && (cy - 0.5).abs() < 0.25;
    final area = box.width * box.height;
    final sized = area > 0.04 && area < 0.75;
    return centered && sized;
  }

  void _onSessionEvent(LivenessEvent event) {
    switch (event) {
      case ReferenceReadyEvent():
        if (widget.config.captureImages && widget.config.captureReferenceImage) {
          _captureFrame(null);
        }
      case ActionStartedEvent(:final action, :final index):
        widget.onActionStarted?.call(action, index);
      case ActionCompletedEvent(:final action, :final index):
        widget.onActionCompleted?.call(action, index);
        if (widget.config.captureImages) _captureFrame(action);
      case SessionCompletedEvent():
        _finish(success: true);
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

    final result = LivenessResult(
      success: success,
      completedActions: _session.current.completedActions,
      failureReason: reason,
      images: List.unmodifiable(_images),
      frameSequence: List.unmodifiable(_frames),
      videoPath: _videoPath,
      startedAt: _startedAt,
      finishedAt: DateTime.now(),
      metadata: {..._session.metadata, ..._extraMetadata},
    );

    // Let the final UI state (success/failure) render briefly before
    // handing off.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (mounted) await widget.onResult(result);
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
          ],
        );
      },
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
