import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';
// CameraException comes from the camera plugin the package depends on.
import 'package:camera/camera.dart' show CameraException;

import '../support/fake_frame_source.dart';

void main() {
  final harness = FakeSourceHarness();
  setUp(harness.install);
  tearDown(harness.uninstall);

  for (final code in const [
    'CameraAccessDenied',
    'CameraAccessDeniedWithoutPrompt',
    'CameraAccessRestricted',
    'cameraPermission',
  ]) {
    testWidgets('D2 $code → permissionDenied', (tester) async {
      usePhoneScreen(tester);
      harness.nextStartError = CameraException(code, 'denied');
      final results = <LivenessResult>[];
      await tester.pumpWidget(MaterialApp(
        home: LivenessDetector(
          config: const LivenessConfig(actions: [LivenessAction.blink]),
          onResult: results.add,
        ),
      ));
      await tester.pump(const Duration(seconds: 1));
      expect(results.single.failureReason,
          LivenessFailureReason.permissionDenied);
      expect(find.text('Camera access is needed — allow it in Settings'),
          findsOneWidget);
    });
  }

  testWidgets('D2 other camera errors stay systemError', (tester) async {
    usePhoneScreen(tester);
    harness.nextStartError = CameraException('CameraBusy', 'in use');
    final results = <LivenessResult>[];
    await tester.pumpWidget(MaterialApp(
      home: LivenessDetector(
        config: const LivenessConfig(actions: [LivenessAction.blink]),
        onResult: results.add,
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(results.single.failureReason, LivenessFailureReason.systemError);
  });

  testWidgets('D2 permissionDeniedBuilder renders and can retry',
      (tester) async {
    usePhoneScreen(tester);
    harness.nextStartError = CameraException('CameraAccessDenied', 'denied');
    final controller = LivenessController();
    addTearDown(controller.dispose);
    final results = <LivenessResult>[];
    await tester.pumpWidget(MaterialApp(
      home: LivenessDetector(
        controller: controller,
        config: const LivenessConfig(actions: [LivenessAction.blink]),
        onResult: results.add,
        permissionDeniedBuilder: (context, retry) => TextButton(
          onPressed: retry,
          child: const Text('Open settings, then retry'),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Open settings, then retry'), findsOneWidget);

    // Access granted meanwhile: the retry's new source starts normally.
    harness.nextStartError = null;
    await tester.tap(find.text('Open settings, then retry'));
    await tester.pump();
    await tester.pump();
    expect(controller.state.phase, LivenessPhase.searchingFace);
    expect(find.text('Open settings, then retry'), findsNothing);
    expect(results, hasLength(1));
  });
}
