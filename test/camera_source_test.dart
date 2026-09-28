import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';
import 'package:liveness_flutter/src/camera/frame_source.dart';

import 'support/fake_camera_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeCameraPlatform platform;
  late CameraPlatform original;

  const mlKit = MethodChannel('google_mlkit_face_detector');

  setUp(() {
    original = CameraPlatform.instance;
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    // FaceDetector.close() is a platform call; answer it.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mlKit, (_) async => null);
  });
  tearDown(() {
    // Never leave a gate shut for the next test.
    for (final gate in [platform.disposeGate, platform.flashGate]) {
      if (gate != null && !gate.isCompleted) gate.complete();
    }
    CameraPlatform.instance = original;
  });

  CameraFrameSource source({bool assisted = false}) => CameraFrameSource(
        config: LivenessConfig(
          actions: const [LivenessAction.blink],
          cameraMode: assisted
              ? LivenessCameraMode.assisted
              : LivenessCameraMode.selfService,
        ),
        resolution: ResolutionPreset.low,
      );

  void ignoreErrors(Object e, StackTrace st) {}

  test('a restarted source opens its camera only after the old one is released',
      () async {
    final first = source();
    await first.start((_) {}, onError: ignoreErrors);
    platform.disposeGate = Completer();

    // A restart's order: the new run starts in initState, the old run is
    // disposed later in the same frame.
    final second = source();
    final secondStarted = second.start((_) {}, onError: ignoreErrors);
    final firstReleased = first.dispose();
    await pumpEventQueue();
    expect(platform.log, isNot(contains('create 2')),
        reason: 'camera 2 must wait until camera 1 is released');

    platform.disposeGate!.complete();
    await firstReleased;
    await secondStarted;
    expect(platform.log.indexOf('disposed 1'),
        lessThan(platform.log.indexOf('create 2')));
    await second.dispose();
    expect(platform.open, isEmpty);
  });

  test('disposing during startup releases the camera and never streams',
      () async {
    platform.flashGate = Completer();
    // Assisted mode turns the torch on during startup: a window to dispose in.
    final s = source(assisted: true);
    final started = s.start((_) {}, onError: ignoreErrors);
    await pumpEventQueue();
    expect(platform.log, contains('flash 1 torch'));

    var released = false;
    final release = s.dispose().then((_) => released = true);
    await pumpEventQueue();
    expect(released, isFalse,
        reason: 'release must not report done while the camera is open');

    platform.flashGate!.complete();
    await started;
    await release;
    expect(platform.open, isEmpty, reason: 'the camera was left open');
    expect(platform.log, isNot(contains('stream 1')),
        reason: 'frames started after dispose');
  });

  testWidgets('the preview cover-fits the space it is given, not the screen',
      (tester) async {
    tester.view.physicalSize = const Size(1170, 2532); // 390 × 844
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final s = source();
    await tester.runAsync(() => s.start((_) {}, onError: ignoreErrors));
    // Under a 144 pt app bar: the detector gets 390 × 700.
    await tester.pumpWidget(MaterialApp(
      home: Column(children: [
        const SizedBox(height: 144),
        SizedBox(
          width: 390,
          height: 700,
          child: Builder(builder: (context) => s.buildPreview(context)!),
        ),
      ]),
    ));

    // 1280×720 camera, shown portrait (0.5625) and covering 390 × 700:
    // scaled to the height, 393.75 wide, centred.
    final rect = tester.getRect(find.byKey(const ValueKey('camera-preview-1')));
    expect(rect.height, closeTo(700, 0.5));
    expect(rect.width, closeTo(393.75, 0.5));
    expect(rect.center.dx, closeTo(195, 0.5));
    expect(rect.center.dy, closeTo(144 + 350, 0.5));
    // Nothing is drawn outside its space (e.g. over the app bar).
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('camera-preview-1')),
        matching: find.byType(ClipRect),
      ),
      findsWidgets,
    );
    await tester.runAsync(s.dispose);
  });
}
