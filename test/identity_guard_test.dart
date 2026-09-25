import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:liveness_flutter/liveness_flutter.dart';
import 'package:liveness_flutter/src/camera/face_mapper.dart';

FaceSnapshot f({
  int? id,
  (double, double)? signature,
  double yaw = 0,
}) =>
    FaceSnapshot(
      timestampMs: 0,
      boundingBox: const Rect.fromLTWH(0.3, 0.3, 0.4, 0.4),
      trackingId: id,
      identitySignature: signature,
      headEulerAngleX: 0,
      headEulerAngleY: yaw,
    );

void main() {
  group('S2 IdentityGuard: tracking IDs', () {
    test('a change while the face stayed in view is a face change', () {
      final g = IdentityGuard()
        ..onFrame(f(id: 1))
        ..onFrame(f(id: 1))
        ..onFrame(f(id: 2));
      expect(g.faceChanged, isTrue);
      expect(g.continuousTrackingIdChanges, 1);
      expect(g.confidencePenalty, greaterThan(0));
    });

    test('a change after the face left is only counted', () {
      final g = IdentityGuard()
        ..onFrame(f(id: 1))
        ..onFrame(null)
        ..onFrame(f(id: 2));
      expect(g.faceChanged, isFalse);
      expect(g.trackingIdChanges, 1);
      expect(g.confidencePenalty, 0);
      expect(g.metadata['identity_trackingIdChanges'], 1);
    });

    test('no tracking IDs (contour mode) never flags', () {
      final g = IdentityGuard();
      for (var i = 0; i < 20; i++) {
        g.onFrame(f());
      }
      expect(g.faceChanged, isFalse);
    });
  });

  group('S2 IdentityGuard: geometry signature', () {
    test('a large jump in near-frontal geometry is counted', () {
      final g = IdentityGuard();
      for (var i = 0; i < 5; i++) {
        g.onFrame(f(signature: (0.50, 0.30)));
      }
      g.onFrame(f(signature: (0.52, 0.31))); // normal jitter
      g.onFrame(f(signature: (0.70, 0.30))); // +40 %
      expect(g.signatureFrames, 2);
      expect(g.signatureJumps, 1);
      expect(g.confidencePenalty, 0, reason: 'reported only');
    });

    test('turned heads are not compared', () {
      final g = IdentityGuard();
      for (var i = 0; i < 5; i++) {
        g.onFrame(f(signature: (0.50, 0.30)));
      }
      g.onFrame(f(signature: (0.30, 0.30), yaw: 30));
      expect(g.signatureJumps, 0);
    });
  });

  group('S2 FaceMapper identity signature', () {
    Face mlFace(double scale) {
      FaceLandmark lm(FaceLandmarkType t, double x, double y) => FaceLandmark(
            type: t,
            position: Point((x * scale).round(), (y * scale).round()),
          );
      return Face(
        boundingBox: Rect.fromLTWH(100 * scale, 100 * scale, 200 * scale,
            200 * scale),
        landmarks: {
          FaceLandmarkType.leftEye: lm(FaceLandmarkType.leftEye, 150, 170),
          FaceLandmarkType.rightEye: lm(FaceLandmarkType.rightEye, 250, 170),
          FaceLandmarkType.noseBase: lm(FaceLandmarkType.noseBase, 200, 230),
          FaceLandmarkType.bottomMouth:
              lm(FaceLandmarkType.bottomMouth, 200, 270),
        },
        contours: const {},
      );
    }

    const mapper = FaceMapper(mirrorYaw: true, uprightCoordinates: true);
    (double, double)? signatureOf(Face face) => mapper
        .map(face,
            imageSize: const Size(1280, 1280),
            rotation: InputImageRotation.rotation0deg,
            timestampMs: 0)
        .identitySignature;

    test('computed from landmarks, relative to face size', () {
      final (a, b) = signatureOf(mlFace(1))!;
      expect(a, closeTo(100 / 200, 1e-9));
      expect(b, closeTo(40 / 200, 1e-9));
    });

    test('independent of how close the face is', () {
      final near = signatureOf(mlFace(2))!;
      final far = signatureOf(mlFace(1))!;
      expect(near.$1, closeTo(far.$1, 1e-9));
      expect(near.$2, closeTo(far.$2, 1e-9));
    });

    test('null without landmarks or contours', () {
      final face = Face(
        boundingBox: const Rect.fromLTWH(0, 0, 10, 10),
        landmarks: const {},
        contours: const {},
      );
      expect(signatureOf(face), isNull);
    });
  });

  test('S2 session fails with faceChanged when told to', () {
    final session = LivenessSession(
      const LivenessConfig(actions: [LivenessAction.smile]),
    )..start();
    session.onFrame(
      faces: [f(id: 1)],
      faceInPosition: true,
      timestampMs: 0,
      faceChanged: true,
    );
    expect(session.current.failureReason, LivenessFailureReason.faceChanged);
  });
}
