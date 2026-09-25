import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

FaceSnapshot faceAt(int t, Rect box) => FaceSnapshot(
      timestampMs: t,
      smileProbability: 0.05,
      leftEyeOpenProbability: 0.95,
      rightEyeOpenProbability: 0.95,
      headEulerAngleX: 0,
      headEulerAngleY: 0,
      headEulerAngleZ: 0,
      boundingBox: box,
    );

const user = Rect.fromLTWH(0.3, 0.3, 0.4, 0.4); // area 0.16
const tiny = Rect.fromLTWH(0.85, 0.05, 0.08, 0.08); // area 0.0064
const similar = Rect.fromLTWH(0.0, 0.0, 0.35, 0.35); // area 0.1225

void main() {
  group('B4 multiple faces', () {
    test('a tiny background face for one frame does not fail', () {
      final session = LivenessSession(
        const LivenessConfig(actions: [LivenessAction.smile]),
      )..start();
      session.onFrame(
          faces: [faceAt(0, user)], faceInPosition: true, timestampMs: 0);
      session.onFrame(
        faces: [faceAt(100, tiny), faceAt(100, user)],
        faceInPosition: true,
        timestampMs: 100,
      );
      session.onFrame(
          faces: [faceAt(200, user)], faceInPosition: true, timestampMs: 200);
      expect(session.current.phase, LivenessPhase.performingAction);
    });

    test('a tiny background face is ignored even when persistent', () {
      final session = LivenessSession(
        const LivenessConfig(actions: [LivenessAction.smile]),
      )..start();
      for (var t = 0; t <= 3000; t += 100) {
        session.onFrame(
          faces: [faceAt(t, tiny), faceAt(t, user)],
          faceInPosition: true,
          timestampMs: t,
        );
      }
      expect(session.current.phase, LivenessPhase.performingAction);
    });

    test('a comparable second face for one frame only pauses', () {
      final session = LivenessSession(
        const LivenessConfig(actions: [LivenessAction.smile]),
      )..start();
      session.onFrame(
          faces: [faceAt(0, user)], faceInPosition: true, timestampMs: 0);
      session.onFrame(
        faces: [faceAt(100, user), faceAt(100, similar)],
        faceInPosition: true,
        timestampMs: 100,
      );
      expect(session.current.phase, LivenessPhase.performingAction);
      expect(session.current.guidance, FaceGuidance.multipleFaces);
      expect(session.current.faceInPosition, isFalse);

      session.onFrame(
          faces: [faceAt(200, user)], faceInPosition: true, timestampMs: 200);
      expect(session.current.guidance, FaceGuidance.none);
    });

    test('two comparable faces for more than 500 ms fail', () {
      final session = LivenessSession(
        const LivenessConfig(actions: [LivenessAction.smile]),
      )..start();
      session.onFrame(
          faces: [faceAt(0, user)], faceInPosition: true, timestampMs: 0);
      for (var t = 100; t <= 600; t += 100) {
        session.onFrame(
          faces: [faceAt(t, user), faceAt(t, similar)],
          faceInPosition: true,
          timestampMs: t,
        );
      }
      expect(session.current.phase, LivenessPhase.performingAction);
      session.onFrame(
        faces: [faceAt(700, user), faceAt(700, similar)],
        faceInPosition: true,
        timestampMs: 700,
      );
      expect(session.current.phase, LivenessPhase.failed);
      expect(
          session.current.failureReason, LivenessFailureReason.multipleFaces);
    });

    test('the grace period restarts when the second face leaves', () {
      final session = LivenessSession(
        const LivenessConfig(actions: [LivenessAction.smile]),
      )..start();
      for (var t = 0; t <= 2000; t += 100) {
        final both = (t ~/ 100).isEven;
        session.onFrame(
          faces: [faceAt(t, user), if (both) faceAt(t, similar)],
          faceInPosition: true,
          timestampMs: t,
        );
      }
      expect(session.current.phase, LivenessPhase.performingAction);
    });

    test('failOnMultipleFaces: false never fails', () {
      final session = LivenessSession(
        const LivenessConfig(
          actions: [LivenessAction.smile],
          failOnMultipleFaces: false,
        ),
      )..start();
      for (var t = 0; t <= 3000; t += 100) {
        session.onFrame(
          faces: [faceAt(t, user), faceAt(t, similar)],
          faceInPosition: true,
          timestampMs: t,
        );
      }
      expect(session.current.phase, LivenessPhase.performingAction);
    });

    test('relevantFaces picks the largest face as primary', () {
      final faces = [faceAt(0, similar), faceAt(0, tiny), faceAt(0, user)];
      final relevant = LivenessSession.relevantFaces(faces);
      expect(relevant.first.boundingBox, user);
      expect(relevant.map((f) => f.boundingBox), [user, similar]);
    });

    test('relevantFaces respects minAreaRatio', () {
      final faces = [faceAt(0, user), faceAt(0, similar)];
      expect(
        LivenessSession.relevantFaces(faces, minAreaRatio: 0.9),
        hasLength(1),
      );
    });
  });
}
