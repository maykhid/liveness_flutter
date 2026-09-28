import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

import '../support/fake_frame_source.dart';

// Widget-level regressions from the code review.
void main() {
  final harness = FakeSourceHarness();
  setUp(harness.install);
  tearDown(harness.uninstall);

  Future<void> advance(WidgetTester tester, int ms) async {
    for (var t = 0; t < ms; t += 100) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('leaving during the flash challenge is not a pass',
      (tester) async {
    usePhoneScreen(tester);
    final results = <LivenessResult>[];
    await tester.pumpWidget(MaterialApp(
      home: LivenessDetector(
        config: const LivenessConfig(
          actions: [LivenessAction.smile],
          enableFlashChallenge: true,
        ),
        onResult: results.add,
      ),
    ));
    await tester.pump();
    await harness.step(tester, [face()]);
    await harness.hold(tester, [face(smile: 0.9)], 700);
    // Actions done; the ~2.5 s colour flash is running.
    await advance(tester, 800);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await advance(tester, 3000);

    expect(tester.takeException(), isNull,
        reason: 'the flash must not touch disposed state');
    final result = results.single;
    expect(result.success, isFalse);
    expect(result.failureReason, LivenessFailureReason.cancelled);
    expect(result.metadata['cancelledBy'], 'dispose');
    expect(result.metadata['flashChallenge'], 'interrupted');
  });

  testWidgets('a cancel during camera startup stays cancelled',
      (tester) async {
    usePhoneScreen(tester);
    harness.nextStartGate = Completer<void>();
    final controller = LivenessController();
    addTearDown(controller.dispose);
    final results = <LivenessResult>[];
    await tester.pumpWidget(MaterialApp(
      home: LivenessDetector(
        controller: controller,
        config: const LivenessConfig(actions: [LivenessAction.smile]),
        onResult: results.add,
      ),
    ));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close)); // camera still opening
    await advance(tester, 1000);
    expect(results.single.failureReason, LivenessFailureReason.cancelled);

    harness.nextStartGate!.complete(); // the camera finishes opening
    await advance(tester, 1000);
    expect(controller.state.phase, LivenessPhase.failed,
        reason: 'the session must not come back to life');
    expect(harness.source.events.last, 'stop',
        reason: 'the camera that opened late must be stopped again');
    expect(results, hasLength(1));
  });

  testWidgets('failOnMultipleFaces: false lets the session run with a '
      'second face in view', (tester) async {
    usePhoneScreen(tester);
    final controller = LivenessController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: LivenessDetector(
        controller: controller,
        config: const LivenessConfig(
          actions: [LivenessAction.smile],
          failOnMultipleFaces: false,
        ),
        onResult: (_) {},
      ),
    ));
    await tester.pump();
    final second = face(box: const Rect.fromLTWH(0.32, 0.3, 0.38, 0.38));
    await harness.step(tester, [face(), second]);
    expect(controller.state.phase, LivenessPhase.performingAction);
    expect(controller.state.faceInPosition, isTrue);
    await harness.hold(tester, [face(smile: 0.9), second], 700);
    expect(controller.state.phase, LivenessPhase.completed);
    await advance(tester, 1000);
  });

  testWidgets('the delivered result is exactly the one that was attested',
      (tester) async {
    usePhoneScreen(tester);
    final attestor = _SlowAttestor();
    final results = <LivenessResult>[];
    await tester.pumpWidget(MaterialApp(
      home: LivenessDetector(
        config: LivenessConfig(
          actions: const [LivenessAction.smile],
          capture: const {CaptureType.images},
          attestor: attestor,
        ),
        onResult: results.add,
      ),
    ));
    await tester.pump();
    // Photos take 6 s to encode: longer than the 5 s the result waits, so
    // they finish while the 3 s attestation is running.
    harness.source.encodeDelay = const Duration(seconds: 6);
    await harness.step(tester, [face()]);
    await harness.hold(tester, [face(smile: 0.9)], 700);
    await advance(tester, 12000);

    final result = results.single;
    expect(attestor.signed, hasLength(1));
    expect(result.attestationPayloadHash, attestor.signed.single,
        reason: 'the server would reject a result that differs from what '
            'was signed');
  });
}

class _SlowAttestor extends LivenessAttestor {
  final signed = <Uint8List>[];

  @override
  Future<String> attest(Uint8List payloadHash) async {
    signed.add(payloadHash);
    await Future<void>.delayed(const Duration(seconds: 3));
    return 'token';
  }
}
