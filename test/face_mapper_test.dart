import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:liveness_flutter/src/camera/face_mapper.dart';

Face mlFace({double pitch = 0, double yaw = 0, double roll = 0}) => Face(
      boundingBox: const Rect.fromLTWH(100, 100, 200, 200),
      landmarks: const {},
      contours: const {},
      headEulerAngleX: pitch,
      headEulerAngleY: yaw,
      headEulerAngleZ: roll,
    );

void main() {
  FaceMapper mapper({required bool android, bool invertPitch = false}) =>
      FaceMapper(
        mirrorYaw: true,
        uprightCoordinates: android,
        invertPitch: invertPitch,
      );

  double? pitchOf(FaceMapper m, double raw) => m
      .map(
        mlFace(pitch: raw),
        imageSize: const Size(480, 640),
        rotation: InputImageRotation.rotation0deg,
        timestampMs: 0,
      )
      .headEulerAngleX;

  group('B8 pitch normalisation', () {
    test('pitch passes through unchanged on both platforms by default', () {
      expect(pitchOf(mapper(android: true), 10), 10);
      expect(pitchOf(mapper(android: false), 10), 10);
    });

    test('invertPitch flips the sign on both platforms', () {
      expect(pitchOf(mapper(android: true, invertPitch: true), 10), -10);
      expect(pitchOf(mapper(android: false, invertPitch: true), 10), -10);
    });

    test('invertPitch leaves yaw and roll alone', () {
      final plain = mapper(android: true).map(
        mlFace(yaw: 20, roll: 5),
        imageSize: const Size(480, 640),
        rotation: InputImageRotation.rotation0deg,
        timestampMs: 0,
      );
      final inverted = mapper(android: true, invertPitch: true).map(
        mlFace(yaw: 20, roll: 5),
        imageSize: const Size(480, 640),
        rotation: InputImageRotation.rotation0deg,
        timestampMs: 0,
      );
      expect(inverted.headEulerAngleY, plain.headEulerAngleY);
      expect(inverted.headEulerAngleZ, plain.headEulerAngleZ);
    });
  });
}
