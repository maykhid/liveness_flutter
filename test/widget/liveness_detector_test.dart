import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

import '../support/fake_frame_source.dart';

void main() {
  final harness = FakeSourceHarness();
  setUp(harness.install);
  tearDown(harness.uninstall);

  Future<List<LivenessResult>> pumpDetector(
    WidgetTester tester, {
    LivenessConfig config = const LivenessConfig(
      actions: [LivenessAction.smile],
      capture: {CaptureType.images},
    ),
  }) async {
    final results = <LivenessResult>[];
    await tester.pumpWidget(MaterialApp(
      home: LivenessDetector(
        config: config,
        onResult: results.add,
      ),
    ));
    await tester.pump();
    return results;
  }

  group('T1 fake frame source', () {
    testWidgets('a scripted smile session succeeds once with evidence',
        (tester) async {
      final results = await pumpDetector(tester);
      expect(harness.source.started, isTrue);
      expect(find.byKey(const ValueKey('fake-preview')), findsOneWidget);

      await harness.step(tester, [face()]); // reference + smile starts
      await harness.hold(tester, [face(smile: 0.9)], 700);
      await tester.pump(const Duration(seconds: 1));

      expect(results, hasLength(1));
      final result = results.single;
      expect(result.success, isTrue);
      expect(result.completedActions, [LivenessAction.smile]);
      expect(result.images.map((i) => i.kind),
          [CaptureKind.reference, CaptureKind.peak]);
      expect(harness.source.stopped, isTrue);
    });

    testWidgets('a camera that fails to open ends with one systemError',
        (tester) async {
      harness.nextStartError = StateError('no camera');
      final results = <LivenessResult>[];
      final errors = <Object>[];
      await tester.pumpWidget(MaterialApp(
        home: LivenessDetector(
          config: const LivenessConfig(actions: [LivenessAction.smile]),
          onResult: results.add,
          onError: (e, _) => errors.add(e),
        ),
      ));
      await tester.pump(const Duration(seconds: 1));
      expect(errors.single, isA<StateError>());
      expect(results.single.failureReason, LivenessFailureReason.systemError);
    });
  });
}
