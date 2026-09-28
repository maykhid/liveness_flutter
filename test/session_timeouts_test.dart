import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

FaceSnapshot face(
  int t, {
  double smile = 0.05,
  double yaw = 0,
}) =>
    FaceSnapshot(
      timestampMs: t,
      smileProbability: smile,
      leftEyeOpenProbability: 0.95,
      rightEyeOpenProbability: 0.95,
      headEulerAngleX: 0,
      headEulerAngleY: yaw,
      headEulerAngleZ: 0,
      boundingBox: const Rect.fromLTWH(0.3, 0.3, 0.4, 0.4),
    );

void main() {
  group('B1 session timeouts', () {
    test('searching for a face fails with sessionTimeout', () {
      final session = LivenessSession(
        const LivenessConfig(
          actions: [LivenessAction.smile],
          sessionTimeout: Duration(seconds: 30),
        ),
      )..start();
      for (var t = 0; t <= 30000; t += 100) {
        session.onFrame(faces: const [], faceInPosition: false, timestampMs: t);
      }
      expect(session.current.phase, LivenessPhase.searchingFace);

      session.onFrame(
          faces: const [], faceInPosition: false, timestampMs: 30100);
      expect(session.current.phase, LivenessPhase.failed);
      expect(
          session.current.failureReason, LivenessFailureReason.sessionTimeout);
    });

    test('centering (face present, never in position) also times out', () {
      final session = LivenessSession(
        const LivenessConfig(
          actions: [LivenessAction.smile],
          sessionTimeout: Duration(seconds: 5),
        ),
      )..start();
      for (var t = 0; t <= 6000; t += 100) {
        session.onFrame(faces: [face(t)], faceInPosition: false, timestampMs: t);
      }
      expect(
          session.current.failureReason, LivenessFailureReason.sessionTimeout);
    });

    test('sessionTimeout: null disables the whole-session limit', () {
      final session = LivenessSession(
        const LivenessConfig(
          actions: [LivenessAction.smile],
          sessionTimeout: null,
        ),
      )..start();
      for (var t = 0; t <= 600000; t += 1000) {
        session.onFrame(faces: const [], faceInPosition: false, timestampMs: t);
      }
      expect(session.current.phase, LivenessPhase.searchingFace);
    });

    test('awaiting neutral fails after neutralTimeout', () {
      final session = LivenessSession(
        const LivenessConfig(
          actions: [LivenessAction.lookLeft, LivenessAction.smile],
          neutralTimeout: Duration(seconds: 10),
        ),
      )..start();
      session.onFrame(faces: [face(0)], faceInPosition: true, timestampMs: 0);
      // lookLeft held from 100 completes at 500.
      for (var t = 100; t <= 500; t += 100) {
        session.onFrame(
            faces: [face(t, yaw: 40)], faceInPosition: true, timestampMs: t);
      }
      expect(session.current.phase, LivenessPhase.awaitingNeutral);

      // Head stays turned for the full 10 s…
      for (var t = 600; t <= 10500; t += 100) {
        session.onFrame(
            faces: [face(t, yaw: 40)], faceInPosition: true, timestampMs: t);
      }
      expect(session.current.phase, LivenessPhase.awaitingNeutral);

      // …and one frame more ends it.
      session.onFrame(
          faces: [face(10600, yaw: 40)],
          faceInPosition: true,
          timestampMs: 10600);
      expect(session.current.phase, LivenessPhase.failed);
      expect(
          session.current.failureReason, LivenessFailureReason.actionTimeout);
      expect(session.metadata['timeoutPhase'], 'awaitingNeutral');
    });

    test('a quality hold (too dark) still counts toward actionTimeout', () {
      final session = LivenessSession(
        const LivenessConfig(
          actions: [LivenessAction.smile],
          actionTimeout: Duration(seconds: 5),
        ),
      )..start();
      session.onFrame(faces: [face(0)], faceInPosition: true, timestampMs: 0);
      expect(session.current.phase, LivenessPhase.performingAction);

      for (var t = 100; t <= 5100; t += 100) {
        session.onFrame(
          faces: const [],
          faceInPosition: false,
          timestampMs: t,
          guidance: FaceGuidance.lowLight,
          qualityHold: true,
        );
      }
      expect(session.current.phase, LivenessPhase.failed);
      expect(
          session.current.failureReason, LivenessFailureReason.actionTimeout);
    });

    test('tick() fires timeouts when no frames arrive', () {
      final session = LivenessSession(
        const LivenessConfig(
          actions: [LivenessAction.smile],
          actionTimeout: Duration(seconds: 5),
        ),
      )..start();
      session.onFrame(faces: [face(0)], faceInPosition: true, timestampMs: 0);
      session.tick(4000);
      expect(session.current.phase, LivenessPhase.performingAction);
      session.tick(5001);
      expect(
          session.current.failureReason, LivenessFailureReason.actionTimeout);
    });

    test('tick() alone starts and enforces the session clock', () {
      final session = LivenessSession(
        const LivenessConfig(
          actions: [LivenessAction.smile],
          sessionTimeout: Duration(seconds: 3),
        ),
      )..start();
      session.tick(1000);
      session.tick(4000);
      expect(session.current.phase, LivenessPhase.searchingFace);
      session.tick(4001);
      expect(
          session.current.failureReason, LivenessFailureReason.sessionTimeout);
    });

    test('tick() before start() does nothing', () {
      final session = LivenessSession(
        const LivenessConfig(actions: [LivenessAction.smile]),
      );
      session.tick(999999999);
      expect(session.current.phase, LivenessPhase.initializing);
    });
  });
}
