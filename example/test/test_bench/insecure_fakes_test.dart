import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';
import 'package:liveness_flutter_example/src/demo_security.dart';

void main() {
  final server = FakeChallengeServer.instance;

  LivenessResult resultFor(
    LivenessChallenge? c, {
    List<LivenessAction>? done,
    String? attestation,
    List<CapturedImage>? images,
  }) =>
      LivenessResult(
        success: true,
        completedActions: done ?? c?.actions ?? const [LivenessAction.blink],
        images: images ??
            [
              CapturedImage(
                bytes: Uint8List.fromList([1, 2, 3]),
                action: LivenessAction.blink,
                timestampMs: 400,
                kind: CaptureKind.peak,
              ),
            ],
        startedAt: DateTime.now(),
        finishedAt: DateTime.now(),
        sessionId: 'LV-TEST',
        nonce: c?.nonce,
        attestation: attestation,
      );

  Check find(List<Check> checks, String prefix) =>
      checks.firstWhere((c) => c.name.startsWith(prefix));

  test('issued challenges include a motion action', () {
    for (var i = 0; i < 50; i++) {
      final c = server.issue(pool: LivenessAction.values, count: 3);
      expect(c.actions, hasLength(3));
      expect(
        c.actions.any({
          LivenessAction.blink,
          LivenessAction.nod,
          LivenessAction.openMouth,
          LivenessAction.drawCircleWithNose,
        }.contains),
        isTrue,
      );
    }
  });

  test('a correct session passes every check', () async {
    final c = server.issue(pool: LivenessAction.values, count: 2);
    final unsigned = resultFor(c);
    final token =
        await const DemoAttestor().attest(unsigned.attestationPayloadHash);
    final checks = server.verify(resultFor(c, attestation: token));
    expect(checks.where((c) => c.passed == false), isEmpty,
        reason: checks.map((c) => '${c.name}: ${c.detail}').join('\n'));
    expect(find(checks, 'Nonce').passed, isTrue);
    expect(find(checks, 'Action order').passed, isTrue);
    expect(find(checks, 'Media').passed, isTrue);
    expect(find(checks, 'Attestation').passed, isTrue);
  });

  test('a replayed nonce fails', () {
    final c = server.issue(pool: LivenessAction.values, count: 2);
    server.verify(resultFor(c));
    expect(find(server.verify(resultFor(c)), 'Nonce').passed, isFalse);
  });

  test('the wrong order fails', () {
    final c = server.issue(pool: LivenessAction.values, count: 3);
    final checks =
        server.verify(resultFor(c, done: c.actions.reversed.toList()));
    expect(find(checks, 'Action order').passed, isFalse);
  });

  test('a token for different media fails attestation', () async {
    final c = server.issue(pool: LivenessAction.values, count: 2);
    final token = await const DemoAttestor()
        .attest(resultFor(c).attestationPayloadHash);
    final swapped = resultFor(c, attestation: token, images: [
      CapturedImage(
        bytes: Uint8List.fromList([9, 9, 9]),
        action: LivenessAction.blink,
        timestampMs: 400,
        kind: CaptureKind.peak,
      ),
    ]);
    expect(find(server.verify(swapped), 'Attestation').passed, isFalse);
  });

  test('sessions without a challenge skip the nonce checks', () {
    final checks = server.verify(resultFor(null));
    expect(find(checks, 'Server challenge').passed, isNull);
  });
}
