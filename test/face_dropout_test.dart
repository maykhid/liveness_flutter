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
      for (var t = 2200; t <= 2500; t += 100) {
        s.onFrame(faces: [f(t, yaw: 30)], faceInPosition: true, timestampMs: t);
      }
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

    test('a face gap longer than the hold does not count as holding', () {
      // Review finding: pose seen at 100, face lost until 700, pose at 800
      // used to complete on those two frames.
      final s = lookLeftSession();
      s.onFrame(faces: [f(0)], faceInPosition: true, timestampMs: 0);
      s.onFrame(faces: [f(100, yaw: 30)], faceInPosition: true, timestampMs: 100);
      for (var t = 200; t <= 700; t += 100) {
        s.onFrame(faces: const [], faceInPosition: false, timestampMs: t);
      }
      s.onFrame(faces: [f(800, yaw: 30)], faceInPosition: true, timestampMs: 800);
      expect(s.current.phase, LivenessPhase.performingAction);
      // It completes once enough *seen* time has passed.
      for (var t = 900; t <= 1100; t += 100) {
        s.onFrame(faces: [f(t, yaw: 30)], faceInPosition: true, timestampMs: t);
      }
      expect(s.current.phase, LivenessPhase.completed);
    });

    test('a camera stall does not count as holding', () {
      // No frames at all between 100 and 700.
      final s = lookLeftSession();
      s.onFrame(faces: [f(0)], faceInPosition: true, timestampMs: 0);
      s.onFrame(faces: [f(100, yaw: 30)], faceInPosition: true, timestampMs: 100);
      s.onFrame(faces: [f(700, yaw: 30)], faceInPosition: true, timestampMs: 700);
      expect(s.current.phase, LivenessPhase.performingAction);
    });

    test('dark frames do not clear a face-lost timer', () {
      final s = lookLeftSession();
      s.onFrame(faces: [f(0)], faceInPosition: true, timestampMs: 0);
      s.onFrame(faces: const [], faceInPosition: false, timestampMs: 100);
      // Alternating dark (quality-held) and face-less frames: the face is
      // never seen again, so it must still count as lost.
      for (var t = 200; t <= 1100; t += 100) {
        s.onFrame(
          faces: const [],
          faceInPosition: false,
          timestampMs: t,
          guidance: FaceGuidance.lowLight,
          qualityHold: t % 200 == 0,
        );
      }
      expect(s.current.failureReason, LivenessFailureReason.faceLost);
    });
  });
}
