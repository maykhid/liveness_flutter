import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';

/// Device capability checks for liveness capture.
class LivenessCapabilities {
  LivenessCapabilities._();

  static bool? _videoSupport;

  /// Whether this device can record video *while* streaming analysis frames
  /// (required for `CaptureType.video`, since detection runs on the stream).
  ///
  /// There is no reliable upfront API for this: the camera plugin doesn't
  /// expose CameraX use-case combinations, and hardware-level flags only
  /// describe guarantees, not actual behavior. So this probes empirically —
  /// it briefly opens the front camera, starts a recording with a frame
  /// stream, and checks that frames arrive and a non-empty file results.
  ///
  /// Takes ~2–3 seconds on first call; the result is cached for the process.
  /// Call it during onboarding/loading — NOT while another camera session is
  /// active (the camera is exclusive).
  ///
  /// On iOS this returns true without probing (recording + streaming is
  /// supported there).
  static Future<bool> supportsVideoCapture({
    Duration probeDuration = const Duration(milliseconds: 2000),
  }) async {
    if (_videoSupport != null) return _videoSupport!;
    if (Platform.isIOS) return _videoSupport = true;

    CameraController? controller;
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await controller.initialize();

      var framesSeen = 0;
      await controller.startVideoRecording(onAvailable: (_) => framesSeen++);
      await Future<void>.delayed(probeDuration);
      final file = await controller.stopVideoRecording();

      final fileOk = await File(file.path).length() > 0;
      // Require a healthy stream, not one or two stray frames.
      _videoSupport = fileOk && framesSeen >= 5;
      // Clean up the probe artifact.
      unawaited(File(file.path).delete().catchError((_) => File(file.path)));
    } catch (_) {
      _videoSupport = false;
    } finally {
      await controller?.dispose();
    }
    return _videoSupport!;
  }

  /// Clears the cached probe result (e.g. for testing).
  static void reset() => _videoSupport = null;
}
