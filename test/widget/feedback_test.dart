import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

import '../support/fake_frame_source.dart';

void main() {
  final harness = FakeSourceHarness();
  setUp(harness.install);
  tearDown(harness.uninstall);

  late List<LivenessFeedback> feedback;
  late List<String> haptics;

  Future<void> pump(WidgetTester tester, {bool haptic = false}) async {
    usePhoneScreen(tester);
    feedback = [];
    haptics = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(MaterialApp(
      home: LivenessDetector(
        config: LivenessConfig(
          actions: const [LivenessAction.smile],
          hapticFeedback: haptic,
        ),
        onResult: (_) {},
        onFeedback: feedback.add,
      ),
    ));
    await tester.pump();
  }

  Future<void> passSmile(WidgetTester tester) async {
    await harness.step(tester, [face()]);
    await harness.hold(tester, [face(smile: 0.9)], 700);
    await tester.pump(const Duration(seconds: 1));
  }

  group('C6 onFeedback', () {
    testWidgets('a passing session reports each moment once, in order',
        (tester) async {
      await pump(tester);
      await passSmile(tester);
      expect(feedback.map((f) => f.type), [
        LivenessFeedbackType.actionStarted,
        LivenessFeedbackType.actionProgressHalf,
        LivenessFeedbackType.actionCompleted,
        LivenessFeedbackType.sessionSucceeded,
      ]);
      expect(feedback.first.action, LivenessAction.smile);
      expect(feedback.first.index, 0);
    });

    testWidgets('a failure reports sessionFailed with its reason',
        (tester) async {
      await pump(tester);
      await harness.step(tester, [face()]);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump(const Duration(seconds: 1));
      expect(feedback.last.type, LivenessFeedbackType.sessionFailed);
      expect(feedback.last.reason, LivenessFailureReason.cancelled);
    });
  });

  group('C6 hapticFeedback', () {
    testWidgets('off by default', (tester) async {
      await pump(tester);
      await passSmile(tester);
      expect(haptics, isEmpty);
    });

    testWidgets('light tick per action, stronger one on success',
        (tester) async {
      await pump(tester, haptic: true);
      await passSmile(tester);
      expect(haptics, [
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.mediumImpact',
      ]);
    });

    testWidgets('no failure haptic for a user cancel', (tester) async {
      await pump(tester, haptic: true);
      await harness.step(tester, [face()]);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump(const Duration(seconds: 1));
      expect(haptics, isEmpty);
    });
  });

  testWidgets('C6 the instruction is a screen-reader live region',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    // Let the instruction's cross-fade finish.
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.getSemantics(find.text('Position your face in the oval')),
      matchesSemantics(label: 'Position your face in the oval', isLiveRegion: true),
    );
    handle.dispose();
  });
}
