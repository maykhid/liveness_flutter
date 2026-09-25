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

  /// Mean R, G, B (0–255) over the centre of [frame], for the flash
  /// challenge.
  List<double>? sampleRgb(Object frame);

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

  /// Completes when the most recently disposed source has released the
  /// camera. A new source waits for it, so a restart (or quickly pushing a
  /// new liveness screen) never tries to open a camera that is still
  /// closing.
  static Future<void> _released = Future.value();

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
  }) async {
    void handle(CameraImage image) {
      _framesSeen++;
      onFrame(image);
    }

    try {
      await _released;
    } catch (_) {}
    if (_disposed) return;

    final wantedDirection =
        _assisted ? CameraLensDirection.back : CameraLensDirection.front;
    final cameras = await availableCameras();
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == wantedDirection,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      camera,
      resolution,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21, // ignored on iOS
    );
    await controller.initialize();
    if (_disposed) {
      await controller.dispose();
      return;
    }

    // Assisted mode: the screen faces the operator, so the torch does
    // the face-lighting job instead. Best-effort (not all devices).
    if (_assisted && config.assistedTorchEnabled) {
      try {
        await controller.setFlashMode(FlashMode.torch);
      } catch (_) {}
    }

    _controller = controller;
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
        // (contours may come back empty). We don't use tracking IDs.
        enableTracking: false,
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
  List<double>? sampleRgb(Object frame) =>
      FlashChallenge.sampleCenterRgb(frame as CameraImage);

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
  Future<void> dispose() {
    _disposed = true;
    _videoWatchdog?.cancel();
    final controller = _controller;
    final detector = _faceDetector;
    // Errors are swallowed: nobody awaits a dispose, and a failed release
    // must not block the next source from trying.
    return _released = () async {
      try {
        await controller?.dispose();
      } catch (_) {}
      try {
        await detector?.close();
      } catch (_) {}
    }();
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
