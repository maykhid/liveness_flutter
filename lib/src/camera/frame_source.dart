import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../detection/flash_challenge.dart';
import 'detection_geometry.dart';
import '../models/models.dart';
import 'face_mapper.dart';
import 'frame_converter.dart';
import 'frame_quality.dart';

/// Internal seam between `LivenessDetector` and the camera + ML Kit, so the
/// widget can be tested with scripted faces instead of a device.
///
/// Frames are opaque `Object`s: only the source that produced a frame can
/// read it.
abstract class LivenessFrameSource {
  /// Monotonic milliseconds that frames are stamped with. Also drives the
  /// session's timeouts.
  int get elapsedMs;

  /// Opens the camera and face detector, then delivers frames to [onFrame]
  /// until [stop]. Throws if the camera can't be opened. [onError] reports
  /// failures after start that end the session (e.g. the video fallback
  /// can't restart the stream).
  Future<void> start(
    void Function(Object frame) onFrame, {
    required void Function(Object error, StackTrace stackTrace) onError,
  });

  /// The camera preview, or null until [start] has completed.
  Widget? buildPreview(BuildContext context);

  /// How face coordinates relate to the displayed preview, or null until
  /// known (after the first [detectFaces]).
  CameraGeometry? get geometry;

  /// Cheap brightness / sharpness / hash metrics.
  FrameQuality? analyzeQuality(Object frame);

  /// Runs face detection on [frame] and returns normalised snapshots
  /// stamped with [timestampMs].
  Future<List<FaceSnapshot>> detectFaces(Object frame, int timestampMs);

  /// Encodes [frame] as a JPEG. The pixels are copied synchronously, before
  /// this returns, so the caller may drop the frame straight away.
  /// [background] runs the encode in an isolate.
  Future<Uint8List?> encodeJpeg(
    Object frame, {
    required int maxDimension,
    required int quality,
    bool background = true,
  });

  /// Mean R, G, B (0–255) for the flash challenge: over [faceBox] (face
  /// space, as in [FaceSnapshot.boundingBox]) when given, else over the
  /// centre of [frame].
  List<double>? sampleRgb(Object frame, {Rect? faceBox});

  /// Best-effort: freeze (or release) auto-exposure so the flash
  /// challenge's colour change isn't compensated away. White balance can't
  /// be locked through `package:camera`.
  Future<void> lockExposure(bool locked);

  /// Facts for `LivenessResult.metadata` (e.g. `videoUnavailable`).
  Map<String, Object?> get metadata;

  /// Stops frames, the torch and any recording. Returns the video path if
  /// a non-empty recording was made.
  Future<String?> stop();

  /// Releases the camera and detector. Safe to call while [start] is
  /// still running.
  Future<void> dispose();
}

/// Replaces the real camera source in tests. Not exported.
@visibleForTesting
LivenessFrameSource Function(LivenessConfig config)?
    debugLivenessFrameSourceFactory;

/// Creates the frame source for a `LivenessDetector`.
LivenessFrameSource createFrameSource(
  LivenessConfig config,
  ResolutionPreset resolution,
) =>
    debugLivenessFrameSourceFactory?.call(config) ??
    CameraFrameSource(config: config, resolution: resolution);

/// The production source: `package:camera` frames analysed by ML Kit.
class CameraFrameSource implements LivenessFrameSource {
  CameraFrameSource({required this.config, required this.resolution});

  final LivenessConfig config;
  final ResolutionPreset resolution;

  /// The most recently started source. A new source waits for this one's
  /// release before opening the camera, so a restart (or quickly pushing a
  /// new liveness screen) never opens a camera that is still closing —
  /// even though the old run is disposed *after* the new one starts.
  static CameraFrameSource? _latest;

  /// Completes once this source has released its camera (or never had one).
  final Completer<void> _released = Completer<void>();

  /// The in-flight [start], so [dispose] can wait for it to wind down.
  Future<void>? _starting;

  final Stopwatch _clock = Stopwatch()..start();
  CameraController? _controller;
  FaceDetector? _faceDetector;
  FrameConverter? _converter;
  FaceMapper? _mapper;
  CameraDescription? _camera;
  CameraGeometry? _geometry;
  bool _videoActive = false;
  Timer? _videoWatchdog;
  int _framesSeen = 0;
  bool _stopped = false;
  bool _disposed = false;
  final Map<String, Object?> _metadata = {};

  bool get _assisted => config.cameraMode == LivenessCameraMode.assisted;

  bool get _needsContours =>
      config.effectiveActions.contains(LivenessAction.openMouth) ||
      config.effectiveActions.contains(LivenessAction.fullTeethSmile);

  bool get _needsLandmarks =>
      config.effectiveActions.contains(LivenessAction.drawCircleWithNose);

  @override
  int get elapsedMs => _clock.elapsedMilliseconds;

  @override
  Map<String, Object?> get metadata => Map.unmodifiable(_metadata);

  @override
  Future<void> start(
    void Function(Object frame) onFrame, {
    required void Function(Object error, StackTrace stackTrace) onError,
  }) =>
      _starting = _start(onFrame, onError: onError);

  /// After every `await`, [_disposed] is checked: once disposed, startup
  /// stops and [dispose] (which waits for this) closes whatever was opened.
  Future<void> _start(
    void Function(Object frame) onFrame, {
    required void Function(Object error, StackTrace stackTrace) onError,
  }) async {
    void handle(CameraImage image) {
      _framesSeen++;
      onFrame(image);
    }

    final previous = _latest;
    _latest = this;
    if (previous != null && previous != this) {
      // Bounded: a camera whose release hangs (or a previous screen that
      // is still open) must not block this one forever.
      try {
        await previous._released.future.timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    if (_disposed) return;

    final wantedDirection =
        _assisted ? CameraLensDirection.back : CameraLensDirection.front;
    final cameras = await availableCameras();
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == wantedDirection,
      orElse: () => cameras.first,
    );

    if (_disposed) return;
    final controller = _controller = CameraController(
      camera,
      resolution,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21, // ignored on iOS
    );
    await controller.initialize();
    if (_disposed) return;

    // Assisted mode: the screen faces the operator, so the torch does
    // the face-lighting job instead. Best-effort (not all devices).
    if (_assisted && config.assistedTorchEnabled) {
      try {
        await controller.setFlashMode(FlashMode.torch);
      } catch (_) {}
      if (_disposed) return;
    }

    _camera = camera;
    _converter = FrameConverter(camera: camera, controller: controller);
    // The back camera isn't mirrored like the front one, so the
    // left/right sign convention flips in assisted mode.
    final effectiveMirror = camera.lensDirection == CameraLensDirection.front
        ? config.mirrorYaw
        : !config.mirrorYaw;
    _mapper = FaceMapper(
      mirrorYaw: effectiveMirror,
      uprightCoordinates: Platform.isAndroid,
      invertPitch: config.invertPitch,
    );
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        // ML Kit: contour detection should not be combined with tracking
        // (contours may come back empty). Tracking IDs feed the identity
        // check, so it's on whenever no action needs contours.
        enableTracking: !_needsContours,
        enableContours: _needsContours,
        enableLandmarks: _needsLandmarks,
        performanceMode: FaceDetectorMode.fast,
      ),
    );

    if (config.captureVideo) {
      await controller.startVideoRecording(onAvailable: handle);
      _videoActive = true;
      // Some Android devices can't stream analysis frames while
      // recording (CameraX use-case limits). If no frames arrive
      // shortly, drop video and continue the session on a plain stream
      // rather than hanging. Reported via metadata['videoUnavailable'].
      _videoWatchdog = Timer(const Duration(milliseconds: 2500), () async {
        if (_framesSeen > 0 || _stopped || _disposed) return;
        try {
          await controller.stopVideoRecording(); // discard
        } catch (_) {}
        _videoActive = false;
        _metadata['videoUnavailable'] = true;
        try {
          await controller.startImageStream(handle);
        } catch (e, st) {
          onError(e, st);
        }
      });
    } else {
      await controller.startImageStream(handle);
    }
  }

  @override
  Widget? buildPreview(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    return _FullScreenPreview(controller: controller);
  }

  @override
  CameraGeometry? get geometry => _geometry;

  @override
  FrameQuality? analyzeQuality(Object frame) =>
      FrameQualityAnalyzer.analyze(frame as CameraImage);

  @override
  Future<List<FaceSnapshot>> detectFaces(Object frame, int timestampMs) async {
    final converter = _converter;
    final detector = _faceDetector;
    final mapper = _mapper;
    if (converter == null || detector == null || mapper == null) {
      return const [];
    }
    final inputImage = converter.toInputImage(frame as CameraImage);
    if (inputImage == null) return const [];

    final faces = await detector.processImage(inputImage);
    final metadata = inputImage.metadata!;
    _geometry = (
      faceSpaceSize: mapper.faceSpaceSize(metadata.size, metadata.rotation),
      rotationDegrees: metadata.rotation.rawValue,
      mirrored: _camera?.lensDirection == CameraLensDirection.front,
    );
    return faces
        .map((f) => mapper.map(
              f,
              imageSize: metadata.size,
              rotation: metadata.rotation,
              timestampMs: timestampMs,
            ))
        .toList();
  }

  @override
  Future<Uint8List?> encodeJpeg(
    Object frame, {
    required int maxDimension,
    required int quality,
    bool background = true,
  }) {
    // Not async: the copy must happen before this returns.
    final raw = _converter?.toRaw(frame as CameraImage);
    if (raw == null) return Future.value(null);
    final request =
        EncodeRequest(raw, maxDimension: maxDimension, quality: quality);
    return background
        ? compute(encodeRawFrame, request)
        : Future.sync(() => encodeRawFrame(request));
  }

  @override
  List<double>? sampleRgb(Object frame, {Rect? faceBox}) {
    final image = frame as CameraImage;
    final geometry = _geometry;
    if (faceBox == null || geometry == null) {
      return FlashChallenge.sampleCenterRgb(image);
    }
    return FlashChallenge.sampleRgb(
      image,
      region: faceSpaceToBuffer(
        faceBox,
        rotationDegrees: geometry.rotationDegrees,
        uprightCoordinates: Platform.isAndroid,
      ),
    );
  }

  @override
  Future<void> lockExposure(bool locked) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setExposureMode(
        locked ? ExposureMode.locked : ExposureMode.auto,
      );
    } catch (_) {}
  }

  @override
  Future<String?> stop() async {
    _stopped = true;
    _videoWatchdog?.cancel();
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    // Torch off before teardown (assisted mode).
    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {}
    if (_videoActive && controller.value.isRecordingVideo) {
      final file = await controller.stopVideoRecording();
      // Guard against silently-broken recordings (empty files).
      if (await File(file.path).length() > 0) return file.path;
      _metadata['videoUnavailable'] = true;
    } else if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
    return null;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return _released.future;
    _disposed = true;
    _videoWatchdog?.cancel();
    // Let an in-flight start reach its next check and stop, so everything
    // it opened is known before releasing it.
    try {
      await _starting;
    } catch (_) {}
    // Errors are swallowed: nobody awaits a dispose, and a failed release
    // must not block the next source from trying.
    try {
      await _controller?.dispose();
    } catch (_) {}
    try {
      await _faceDetector?.close();
    } catch (_) {}
    if (_latest == this) _latest = null;
    _released.complete();
  }
}

/// Cover-fits the camera preview to the space this widget is given (not
/// the whole screen) and clips the overflow. `DetectionGeometry` maps the
/// on-screen target into the camera image with the same cover-fit, so what
/// is drawn and what is detected line up even under an app bar.
class _FullScreenPreview extends StatelessWidget {
  const _FullScreenPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    // Width / height of the sensor image, landscape (e.g. 1280 / 720).
    final sensorAspect = controller.value.aspectRatio;
    final portrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final shownAspect = portrait ? 1 / sensorAspect : sensorAspect;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: 1000 * shownAspect,
          height: 1000,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}
