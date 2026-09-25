import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';
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

  bool started = false;
  bool stopped = false;
  bool disposed = false;
  Object? startError;
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
    final error = startError;
    if (error != null) throw error;
    _onFrame = onFrame;
    started = true;
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

  @override
  Future<List<FaceSnapshot>> detectFaces(Object frame, int timestampMs) async =>
      [for (final f in (frame as FakeFrame).faces) restamp(f, timestampMs)];

  @override
  Future<Uint8List?> encodeJpeg(
    Object frame, {
    required int maxDimension,
    required int quality,
    bool background = true,
  }) {
    final id = (frame as FakeFrame).id;
    encodedFrameIds.add(id);
    return Future.value(Uint8List.fromList([0xFF, 0xD8, id & 0xFF]));
  }

  @override
  List<double>? sampleRgb(Object frame) => const [120, 110, 100];

  @override
  Map<String, Object?> get metadata => const {};

  @override
  Future<String?> stop() async {
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
}) =>
    FaceSnapshot(
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

  void install() {
    current = null;
    nextStartError = null;
    debugLivenessFrameSourceFactory = (config) => current =
        FakeFrameSource(config)..startError = nextStartError;
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
