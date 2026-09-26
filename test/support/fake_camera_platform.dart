import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/widgets.dart';

/// A camera plugin stand-in for testing the real `CameraFrameSource`:
/// records every call in [log], and can hold `setFlashMode` or `dispose`
/// open with [flashGate] / [disposeGate] to create timing windows.
class FakeCameraPlatform extends CameraPlatform {
  final List<String> log = [];
  Completer<void>? flashGate;
  Completer<void>? disposeGate;
  int _nextId = 1;
  final _initialized = StreamController<CameraInitializedEvent>.broadcast();

  /// Cameras created and not yet disposed.
  final Set<int> open = {};

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
        CameraDescription(
          name: 'front',
          lensDirection: CameraLensDirection.front,
          sensorOrientation: 270,
        ),
        CameraDescription(
          name: 'back',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
        ),
      ];

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async {
    final id = _nextId++;
    open.add(id);
    log.add('create $id');
    return id;
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _initialized.stream.where((e) => e.cameraId == cameraId);

  /// Never emits (and never closes: the plugin waits on `.first`).
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      StreamController<CameraErrorEvent>().stream;

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    log.add('initialize $cameraId');
    scheduleMicrotask(() => _initialized.add(CameraInitializedEvent(
          cameraId,
          1280,
          720,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        )));
  }

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    log.add('flash $cameraId ${mode.name}');
    await flashGate?.future;
  }

  @override
  Future<void> setExposureMode(int cameraId, ExposureMode mode) async {}

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) {
    log.add('stream $cameraId');
    return const Stream.empty();
  }

  @override
  Widget buildPreview(int cameraId) =>
      SizedBox.expand(key: ValueKey('camera-preview-$cameraId'));

  @override
  Future<void> dispose(int cameraId) async {
    log.add('dispose $cameraId');
    await disposeGate?.future;
    open.remove(cameraId);
    log.add('disposed $cameraId');
  }
}
