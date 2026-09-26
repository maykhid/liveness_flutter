import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';
import 'package:liveness_flutter_example/recipes/fintech/account.dart';
import 'package:liveness_flutter_example/recipes/fintech/brand.dart';
import 'package:liveness_flutter_example/recipes/fintech/face_capture_screen.dart';
import 'package:liveness_flutter_example/recipes/fintech/main.dart';
import 'package:liveness_flutter_example/recipes/fintech/outcome_screens.dart';

import '../support/no_camera.dart';

LivenessResult result({required bool success, LivenessFailureReason? reason}) =>
    LivenessResult(
      success: success,
      completedActions: const [],
      failureReason: reason,
      startedAt: DateTime(2026),
      finishedAt: DateTime(2026),
    );

Widget app(Widget home) => MaterialApp(theme: Brand.theme(), home: home);

void main() {
  setUp(() => accountTier.value = 1);

  testWidgets('home offers the upgrade and opens the intro', (tester) async {
    await tester.pumpWidget(const AcmePayApp());
    expect(find.text('Upgrade to Tier 2'), findsOneWidget);
    await tester.tap(find.text('Upgrade to Tier 2'));
    await tester.pumpAndSettle();
    expect(find.text('Start face check'), findsOneWidget);
  });

  testWidgets('the capture screen builds and routes a failure to help',
      (tester) async {
    useNoCamera(); // the session ends with systemError
    await tester.pumpWidget(app(const FaceCaptureScreen()));
    await tester.pump();
    expect(find.text('Face check'), findsOneWidget);
    await advance(tester);
    await tester.pumpAndSettle();
    expect(
      find.text(Brand.failureHelp(LivenessFailureReason.systemError).title),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
  });

  testWidgets('the top bar sits under the notch, on one line',
      (tester) async {
    useNoCamera();
    tester.view.physicalSize = const Size(1170, 2532); // 390 × 844
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 141); // 47 pt notch
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const FaceCaptureScreen()));
    await tester.pump();

    final close = tester.getCenter(find.byIcon(Icons.close));
    final title = tester.getCenter(find.text('Face check'));
    final chip = tester.getCenter(find.text('Step 3 of 3'));
    // Below the notch, within a standard 56 pt toolbar.
    expect(close.dy, inInclusiveRange(47, 47 + 56));
    // One line.
    expect(title.dy, closeTo(close.dy, 0.5));
    expect(chip.dy, closeTo(close.dy, 0.5));
    await advance(tester); // let the session's timers finish
  });

  testWidgets('the title is centred on the screen', (tester) async {
    // The test font draws every letter as a full square, making the title
    // and chip about twice their real width, too wide to centre on a
    // phone-sized screen. A wider one tests the centring itself.
    useNoCamera();
    tester.view.physicalSize = const Size(1800, 2532); // 600 × 844
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const FaceCaptureScreen()));
    await tester.pump();
    expect(tester.getCenter(find.text('Face check')).dx, closeTo(300, 0.5));
    await advance(tester);
  });

  testWidgets('a passing check unlocks Tier 2', (tester) async {
    await tester.pumpWidget(
        app(VerifyingScreen(result: result(success: true))));
    expect(find.text('Verifying your face…'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('You’re verified'), findsOneWidget);
    expect(accountTier.value, 2);
  });

  testWidgets('denied camera access shows the in-screen permission page',
      (tester) async {
    useNoCamera(code: 'CameraAccessDenied');
    await tester.pumpWidget(app(const FaceCaptureScreen()));
    await advance(tester);
    expect(find.text('Allow camera access'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
  });

  for (final reason in [...LivenessFailureReason.values, null]) {
    testWidgets('failure screen for ${reason?.name ?? 'no reason'}',
        (tester) async {
      await tester.pumpWidget(app(FailureScreen(reason: reason)));
      final help = Brand.failureHelp(reason);
      expect(find.text(help.title), findsOneWidget);
      expect(help.tips, isNotEmpty);
    });
  }

  test('every action has brand wording', () {
    for (final action in LivenessAction.values) {
      expect(Brand.instructionFor(action).title, isNotEmpty);
    }
  });

  test('the action pool always yields a motion action', () {
    const motion = {
      LivenessAction.blink,
      LivenessAction.nod,
      LivenessAction.openMouth,
      LivenessAction.drawCircleWithNose,
    };
    final pool = Brand.livenessConfig.actions;
    final poseOnly = pool.where((a) => !motion.contains(a)).length;
    expect(poseOnly, lessThan(Brand.livenessConfig.randomActionCount!));
  });
}
