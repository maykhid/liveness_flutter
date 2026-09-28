import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';
import 'package:liveness_flutter/src/camera/detection_geometry.dart';
import 'package:liveness_flutter/src/camera/frame_source.dart';

/// A scripted frame: the faces "ML Kit" will report, and optional quality.
class FakeFrame {
  FakeFrame(this.faces, this.quality, this.id);
  final List<FaceSnapshot> faces;
  final FrameQuality? quality;
  final int id;
}

/// Stands in for the camera + ML Kit. Time comes from the test binding's
/// fake clock, so it advances with `tester.pump(duration)`.
class FakeFrameSource implements LivenessFrameSource {
  FakeFrameSource(this.config);

  final LivenessConfig config;
  final DateTime _t0 = TestWidgetsFlutterBinding.instance.clock.now();
  void Function(Object frame)? _onFrame;
  int _nextId = 0;

  /// Portrait phone camera with upright coordinates, front lens.
  @override
  CameraGeometry? geometry = (
    faceSpaceSize: const Size(720, 1280),
    rotationDegrees: 270,
    mirrored: true,
  );

  bool started = false;
  bool stopped = false;
  bool disposed = false;
  Object? startError;

  /// When set, `start` waits for it (a camera that's slow to open).
  Completer<void>? startGate;

  /// How long each JPEG encode takes.
  Duration encodeDelay = Duration.zero;

  /// 'start', 'started', 'stop' in the order they happened.
  final List<String> events = [];
  final List<int> encodedFrameIds = [];

  @override
  int get elapsedMs => TestWidgetsFlutterBinding.instance.clock
      .now()
      .difference(_t0)
      .inMilliseconds;

  @override
  Future<void> start(
    void Function(Object frame) onFrame, {
    required void Function(Object error, StackTrace stackTrace) onError,
  }) async {
    events.add('start');
    await startGate?.future;
    final error = startError;
    if (error != null) throw error;
    _onFrame = onFrame;
    started = true;
    events.add('started');
  }

  /// Delivers one frame with [faces] to the widget.
  void emit(List<FaceSnapshot> faces, {FrameQuality? quality}) =>
      _onFrame?.call(FakeFrame(faces, quality, _nextId++));

  @override
  Widget? buildPreview(BuildContext context) =>
      const ColoredBox(key: ValueKey('fake-preview'), color: Color(0xFF202020));

  @override
  FrameQuality? analyzeQuality(Object frame) {
    final f = frame as FakeFrame;
    // Distinct hash per frame, like real sensor noise.
    return f.quality ??
        FrameQuality(brightness: 0.5, sharpness: 0.2, hash: f.id + 1);
  }

  /// How many frames went through "ML Kit".
  int detections = 0;

  @override
  Future<List<FaceSnapshot>> detectFaces(Object frame, int timestampMs) async {
    detections++;
    return [for (final f in (frame as FakeFrame).faces) restamp(f, timestampMs)];
  }

  @override
  Future<Uint8List?> encodeJpeg(
    Object frame, {
    required int maxDimension,
    required int quality,
    bool background = true,
  }) {
    final id = (frame as FakeFrame).id;
    encodedFrameIds.add(id);
    final bytes = Uint8List.fromList([0xFF, 0xD8, id & 0xFF]);
    return encodeDelay == Duration.zero
        ? Future.value(bytes)
        : Future.delayed(encodeDelay, () => bytes);
  }

  /// RGB returned for flash-challenge samples; tests can script it.
  List<double> Function(int elapsedMs) rgb = (_) => const [120, 110, 100];
  final List<Rect?> sampledFaceBoxes = [];
  final List<bool> exposureLocks = [];

  @override
  List<double>? sampleRgb(Object frame, {Rect? faceBox}) {
    sampledFaceBoxes.add(faceBox);
    return rgb(elapsedMs);
  }

  @override
  Future<void> lockExposure(bool locked) async => exposureLocks.add(locked);

  @override
  Map<String, Object?> get metadata => const {};

  @override
  Future<String?> stop() async {
    events.add('stop');
    stopped = true;
    return null;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

FaceSnapshot restamp(FaceSnapshot f, int t) => FaceSnapshot(
      timestampMs: t,
      smileProbability: f.smileProbability,
      leftEyeOpenProbability: f.leftEyeOpenProbability,
      rightEyeOpenProbability: f.rightEyeOpenProbability,
      headEulerAngleX: f.headEulerAngleX,
      headEulerAngleY: f.headEulerAngleY,
      headEulerAngleZ: f.headEulerAngleZ,
      noseBase: f.noseBase,
      mouthOpenRatio: f.mouthOpenRatio,
      boundingBox: f.boundingBox,
      trackingId: f.trackingId,
    );

/// A centred, neutral face. Override fields for actions.
FaceSnapshot face({
  double smile = 0.05,
  double eyes = 0.95,
  double yaw = 0,
  double pitch = 0,
  Rect box = const Rect.fromLTWH(0.3, 0.3, 0.4, 0.4),
  int? trackingId,
}) =>
    FaceSnapshot(
      trackingId: trackingId,
      timestampMs: 0,
      smileProbability: smile,
      leftEyeOpenProbability: eyes,
      rightEyeOpenProbability: eyes,
      headEulerAngleX: pitch,
      headEulerAngleY: yaw,
      headEulerAngleZ: 0,
      boundingBox: box,
    );

/// Installs a [FakeFrameSource] for widget tests and hands it back via
/// [current] once the widget creates it.
class FakeSourceHarness {
  FakeFrameSource? current;

  /// Makes the next source's `start` throw this.
  Object? nextStartError;

  /// Makes the next source's `start` wait for this.
  Completer<void>? nextStartGate;

  void install() {
    current = null;
    nextStartError = null;
    nextStartGate = null;
    debugLivenessFrameSourceFactory = (config) => current =
        FakeFrameSource(config)
          ..startError = nextStartError
          ..startGate = nextStartGate;
  }

  void uninstall() => debugLivenessFrameSourceFactory = null;

  FakeFrameSource get source => current!;

  /// Advances time by [ms], then delivers one frame with [faces].
  Future<void> step(
    WidgetTester tester,
    List<FaceSnapshot> faces, {
    int ms = 100,
    FrameQuality? quality,
  }) async {
    await tester.pump(Duration(milliseconds: ms));
    source.emit(faces, quality: quality);
    await tester.pump();
  }

  /// Runs frames of [faces] for [durationMs].
  Future<void> hold(
    WidgetTester tester,
    List<FaceSnapshot> faces,
    int durationMs,
  ) async {
    for (var t = 0; t < durationMs; t += 100) {
      await step(tester, faces);
    }
  }
}

/// A 360×780 portrait phone screen (the camera geometry above assumes
/// portrait). Resets itself after the test.
void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}
