import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

import '../support/fake_frame_source.dart';

void main() {
  final harness = FakeSourceHarness();
  setUp(harness.install);
  tearDown(harness.uninstall);

  late LivenessController controller;
  late List<LivenessResult> results;

  Future<void> pump(
    WidgetTester tester, {
    List<LivenessAction> actions = const [LivenessAction.smile],
    bool shuffle = false,
  }) async {
    usePhoneScreen(tester);
    controller = LivenessController();
    addTearDown(controller.dispose);
    results = [];
    await tester.pumpWidget(MaterialApp(
      home: LivenessDetector(
        controller: controller,
        showCloseButton: false,
        config: LivenessConfig(actions: actions, shuffleActions: shuffle),
        onResult: results.add,
      ),
    ));
    await tester.pump();
  }

  group('C1 LivenessController', () {
    testWidgets('cancel() ends the session with one cancelled result',
        (tester) async {
      await pump(tester);
      expect(find.byIcon(Icons.close), findsNothing);
      await harness.step(tester, [face()]);
      expect(controller.state.phase, LivenessPhase.performingAction);

      controller.cancel();
      await tester.pump(const Duration(seconds: 1));
      expect(results, hasLength(1));
      expect(results.single.failureReason, LivenessFailureReason.cancelled);
      expect(results.single.metadata['cancelledBy'], 'user');

      controller.cancel(); // no-op once ended
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(results, hasLength(1));
    });

    testWidgets('restart() starts a new session with a new sessionId',
        (tester) async {
      await pump(tester);
      final firstId = controller.sessionId;
      final firstSource = harness.source;
      expect(firstId, isNotNull);
      await harness.step(tester, [face()]);

      final restarted = controller.restart();
      await tester.pump();
      await tester.pump();
      await expectLater(restarted, completes);

      // The interrupted session still got exactly one result.
      expect(results, hasLength(1));
      expect(results.single.metadata['cancelledBy'], 'restart');
      expect(results.single.sessionId, firstId);
      expect(firstSource.disposed, isTrue);

      expect(controller.sessionId, isNot(firstId));
      expect(harness.source, isNot(same(firstSource)));
      expect(controller.state.phase, LivenessPhase.searchingFace);

      // The new session runs to completion on its own.
      await harness.step(tester, [face()]);
      await harness.hold(tester, [face(smile: 0.9)], 700);
      await tester.pump(const Duration(seconds: 1));
      expect(results, hasLength(2));
      expect(results.last.success, isTrue);
      expect(results.last.sessionId, controller.sessionId);
    });

    testWidgets('restart() after a finished session delivers no extra result',
        (tester) async {
      await pump(tester);
      await harness.step(tester, [face()]);
      await harness.hold(tester, [face(smile: 0.9)], 700);
      await tester.pump(const Duration(seconds: 1));
      expect(results.single.success, isTrue);

      controller.restart();
      await tester.pump();
      await tester.pump();
      expect(results, hasLength(1));
      expect(controller.state.phase, LivenessPhase.searchingFace);
    });

    testWidgets('state and actionPlan track the session; listeners fire',
        (tester) async {
      await pump(
        tester,
        actions: const [
          LivenessAction.smile,
          LivenessAction.blink,
          LivenessAction.lookLeft,
        ],
        shuffle: true,
      );
      var notifications = 0;
      controller.addListener(() => notifications++);

      expect(controller.actionPlan.toSet(), {
        LivenessAction.smile,
        LivenessAction.blink,
        LivenessAction.lookLeft,
      });
      await harness.step(tester, [face()]);
      expect(controller.state.currentAction, controller.actionPlan.first);
      expect(notifications, greaterThan(0));
    });

    testWidgets('restart() throws when no detector is attached',
        (tester) async {
      final lonely = LivenessController();
      addTearDown(lonely.dispose);
      expect(lonely.isAttached, isFalse);
      expect(lonely.state.phase, LivenessPhase.initializing);
      expect(lonely.restart, throwsStateError);
    });

    testWidgets('the controller detaches when the detector goes away',
        (tester) async {
      await pump(tester);
      expect(controller.isAttached, isTrue);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(controller.isAttached, isFalse);
      expect(controller.sessionId, isNull);
      expect(results.single.metadata['cancelledBy'], 'dispose');
    });
  });
}
