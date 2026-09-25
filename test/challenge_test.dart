import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

FaceSnapshot f(int t, {double smile = 0.05, double yaw = 0}) => FaceSnapshot(
      timestampMs: t,
      smileProbability: smile,
      leftEyeOpenProbability: 0.95,
      rightEyeOpenProbability: 0.95,
      headEulerAngleX: 0,
      headEulerAngleY: yaw,
      headEulerAngleZ: 0,
      boundingBox: const Rect.fromLTWH(0.3, 0.3, 0.4, 0.4),
    );

final t0 = DateTime.utc(2026, 9, 25, 12);

LivenessChallenge challenge({
  List<LivenessAction> actions = const [
    LivenessAction.lookLeft,
    LivenessAction.smile,
  ],
  Duration validFor = const Duration(minutes: 5),
}) =>
    LivenessChallenge(
      nonce: 'n-123',
      actions: actions,
      expiresAt: t0.add(validFor),
    );

void main() {
  group('S1 LivenessChallenge in the session', () {
    test('runs the challenge order, ignoring actions and shuffle', () {
      final session = LivenessSession(
        LivenessConfig(
          actions: const [],
          shuffleActions: true,
          challenge: challenge(),
        ),
        now: () => t0,
      );
      expect(session.actionOrder, [LivenessAction.lookLeft, LivenessAction.smile]);
      expect(session.current.totalActions, 2);
    });

    test('an expired challenge fails at start', () {
      final session = LivenessSession(
        LivenessConfig(actions: const [], challenge: challenge()),
        now: () => t0.add(const Duration(minutes: 6)),
      )..start();
      expect(session.current.phase, LivenessPhase.failed);
      expect(session.current.failureReason,
          LivenessFailureReason.challengeExpired);
    });

    test('a challenge that expires mid-session fails at completion', () {
      var now = t0;
      final session = LivenessSession(
        LivenessConfig(
          actions: const [],
          challenge: challenge(actions: const [LivenessAction.smile]),
        ),
        now: () => now,
      )..start();
      session.onFrame(faces: [f(0)], faceInPosition: true, timestampMs: 0);
      session.onFrame(
          faces: [f(100, smile: 0.9)], faceInPosition: true, timestampMs: 100);
      now = t0.add(const Duration(minutes: 10));
      session.onFrame(
          faces: [f(700, smile: 0.9)], faceInPosition: true, timestampMs: 700);
      expect(session.current.failureReason,
          LivenessFailureReason.challengeExpired);
    });

    test('validation: challenge actions and nonce must be non-empty', () {
      expect(
        () => LivenessSession(LivenessConfig(
          actions: const [LivenessAction.blink],
          challenge: challenge(actions: const []),
        )),
        throwsArgumentError,
      );
      expect(
        () => LivenessSession(LivenessConfig(
          actions: const [],
          challenge: LivenessChallenge(
            nonce: '',
            actions: const [LivenessAction.blink],
            expiresAt: t0,
          ),
        )),
        throwsArgumentError,
      );
    });
  });

  group('S1 result integrity fields', () {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final expectedSha = sha256.convert(bytes).toString();
    final result = LivenessResult(
      success: true,
      completedActions: const [LivenessAction.blink, LivenessAction.smile],
      images: [
        CapturedImage(
          bytes: bytes,
          action: LivenessAction.blink,
          timestampMs: 500,
          kind: CaptureKind.peak,
        ),
      ],
      startedAt: t0,
      finishedAt: t0.add(const Duration(seconds: 4)),
      sessionId: 'LV-1',
      nonce: 'n-123',
      attestation: 'token',
    );

    test('toJson carries nonce, attestation and per-image SHA-256', () {
      final json = result.toJson();
      expect(json['nonce'], 'n-123');
      expect(json['attestation'], 'token');
      final images = json['images']! as List;
      expect(images.single, {
        'action': 'blink',
        'kind': 'peak',
        'timestampMs': 500,
        'sha256': expectedSha,
      });
      // Still JSON-encodable.
      expect(() => jsonEncode(json), returnsNormally);
    });

    test('attestationPayload is a simple, rebuildable string', () {
      expect(result.attestationPayload, 'LV-1|n-123|true|blink,smile|$expectedSha');
      expect(
        result.attestationPayloadHash,
        sha256.convert(utf8.encode(result.attestationPayload)).bytes,
      );
    });
  });
}
