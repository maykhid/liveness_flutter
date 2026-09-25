import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

FaceSnapshot f(int t, {double yaw = 0}) => FaceSnapshot(
      timestampMs: t,
      smileProbability: 0.05,
      leftEyeOpenProbability: 0.95,
      rightEyeOpenProbability: 0.95,
      headEulerAngleX: 0,
      headEulerAngleY: yaw,
      headEulerAngleZ: 0,
      boundingBox: const Rect.fromLTWH(0.3, 0.3, 0.4, 0.4),
    );

LivenessSession lookLeftSession() => LivenessSession(
      const LivenessConfig(actions: [LivenessAction.lookLeft]),
    )..start();

void main() {
  group('B6 brief dropouts keep hold progress', () {
    test('one empty frame mid-hold: completes at the original time', () {
      final s = lookLeftSession();
      s.onFrame(faces: [f(0)], faceInPosition: true, timestampMs: 0);
      s.onFrame(faces: [f(100, yaw: 30)], faceInPosition: true, timestampMs: 100);
      s.onFrame(faces: const [], faceInPosition: false, timestampMs: 200);
      expect(s.current.phase, LivenessPhase.performingAction);
      s.onFrame(faces: [f(300, yaw: 30)], faceInPosition: true, timestampMs: 300);
      expect(s.current.phase, LivenessPhase.performingAction);
      // Hold began at 100; poseHold is 400 ms.
      s.onFrame(faces: [f(500, yaw: 30)], faceInPosition: true, timestampMs: 500);
      expect(s.current.phase, LivenessPhase.completed);
    });

    test('one bad-quality frame mid-hold: completes at the original time', () {
      final s = lookLeftSession();
      s.onFrame(faces: [f(0)], faceInPosition: true, timestampMs: 0);
      s.onFrame(faces: [f(100, yaw: 30)], faceInPosition: true, timestampMs: 100);
      s.onFrame(
        faces: const [],
        faceInPosition: false,
        timestampMs: 200,
        guidance: FaceGuidance.blurry,
        qualityHold: true,
      );
      s.onFrame(faces: [f(300, yaw: 30)], faceInPosition: true, timestampMs: 300);
      s.onFrame(faces: [f(500, yaw: 30)], faceInPosition: true, timestampMs: 500);
      expect(s.current.phase, LivenessPhase.completed);
    });

    test('a quality pause longer than faceLostGrace restarts the hold', () {
      final s = lookLeftSession();
      s.onFrame(faces: [f(0)], faceInPosition: true, timestampMs: 0);
      s.onFrame(faces: [f(100, yaw: 30)], faceInPosition: true, timestampMs: 100);
      for (var t = 200; t <= 2000; t += 100) {
        s.onFrame(
          faces: const [],
          faceInPosition: false,
          timestampMs: t,
          guidance: FaceGuidance.lowLight,
          qualityHold: true,
        );
      }
      // Would already be "held" 2 s if the gap counted. It must not.
      s.onFrame(
          faces: [f(2100, yaw: 30)], faceInPosition: true, timestampMs: 2100);
      expect(s.current.phase, LivenessPhase.performingAction);
      s.onFrame(
          faces: [f(2500, yaw: 30)], faceInPosition: true, timestampMs: 2500);
      expect(s.current.phase, LivenessPhase.completed);
    });

    test('a dropout past faceLostGrace still fails', () {
      final s = lookLeftSession();
      s.onFrame(faces: [f(0)], faceInPosition: true, timestampMs: 0);
      s.onFrame(faces: [f(100, yaw: 30)], faceInPosition: true, timestampMs: 100);
      s.onFrame(faces: const [], faceInPosition: false, timestampMs: 200);
      s.onFrame(faces: const [], faceInPosition: false, timestampMs: 1100);
      expect(s.current.failureReason, LivenessFailureReason.faceLost);
    });
  });
}
