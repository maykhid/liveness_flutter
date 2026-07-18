import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

FaceSnapshot frame({
  required int t,
  double? smile,
  double? leftEye,
  double? rightEye,
  double? pitch,
  double? yaw,
  double? roll,
  Offset? nose,
  double? mouthOpen,
  Rect box = const Rect.fromLTWH(0.3, 0.3, 0.4, 0.4),
}) {
  return FaceSnapshot(
    timestampMs: t,
    smileProbability: smile,
    leftEyeOpenProbability: leftEye,
    rightEyeOpenProbability: rightEye,
    headEulerAngleX: pitch,
    headEulerAngleY: yaw,
    headEulerAngleZ: roll,
    noseBase: nose,
    mouthOpenRatio: mouthOpen,
    boundingBox: box,
  );
}

void main() {
  const tuning = DetectorTuning();

  group('BlinkDetector', () {
    test('completes on open -> closed -> open', () {
      final d = BlinkDetector(tuning);
      expect(d.update(frame(t: 0, leftEye: 0.9, rightEye: 0.9)).completed, false);
      expect(d.update(frame(t: 100, leftEye: 0.1, rightEye: 0.1)).completed, false);
      expect(d.update(frame(t: 300, leftEye: 0.9, rightEye: 0.9)).completed, true);
    });

    test('restarts if eyes stay closed too long', () {
      final d = BlinkDetector(tuning);
      d.update(frame(t: 0, leftEye: 0.9, rightEye: 0.9));
      d.update(frame(t: 100, leftEye: 0.1, rightEye: 0.1));
      // Held closed past blinkMaxDuration.
      final update = d.update(frame(t: 2000, leftEye: 0.1, rightEye: 0.1));
      expect(update.completed, false);
      expect(update.progress, 0);
    });
  });

  group('SmileDetector', () {
    test('requires hold duration', () {
      final d = SmileDetector(tuning, fullTeeth: false);
      expect(d.update(frame(t: 0, smile: 0.9)).completed, false);
      expect(d.update(frame(t: 200, smile: 0.9)).completed, false);
      expect(d.update(frame(t: 600, smile: 0.9)).completed, true);
    });

    test('resets when smile drops', () {
      final d = SmileDetector(tuning, fullTeeth: false);
      d.update(frame(t: 0, smile: 0.9));
      d.update(frame(t: 300, smile: 0.2)); // dropped
      expect(d.update(frame(t: 400, smile: 0.9)).completed, false);
      expect(d.update(frame(t: 950, smile: 0.9)).completed, true);
    });

    test('full teeth needs mouth open when contours available', () {
      final d = SmileDetector(tuning, fullTeeth: true);
      d.update(frame(t: 0, smile: 0.95, mouthOpen: 0.02));
      expect(d.update(frame(t: 600, smile: 0.95, mouthOpen: 0.02)).completed,
          false);
      d.update(frame(t: 700, smile: 0.95, mouthOpen: 0.3));
      expect(
          d.update(frame(t: 1300, smile: 0.95, mouthOpen: 0.3)).completed, true);
    });
  });

  group('EyesClosedDetector', () {
    test('completes after hold', () {
      final d = EyesClosedDetector(tuning);
      expect(d.update(frame(t: 0, leftEye: 0.1, rightEye: 0.1)).completed, false);
      expect(
          d.update(frame(t: 1000, leftEye: 0.1, rightEye: 0.1)).completed, false);
      expect(
          d.update(frame(t: 2100, leftEye: 0.1, rightEye: 0.1)).completed, true);
    });

    test('resets if eyes open early', () {
      final d = EyesClosedDetector(tuning);
      d.update(frame(t: 0, leftEye: 0.1, rightEye: 0.1));
      d.update(frame(t: 1000, leftEye: 0.9, rightEye: 0.9));
      expect(
          d.update(frame(t: 2100, leftEye: 0.1, rightEye: 0.1)).completed, false);
    });
  });

  group('NodDetector', () {
    test('completes neutral -> down -> back', () {
      final d = NodDetector(tuning);
      d.update(frame(t: 0, pitch: 0));
      d.update(frame(t: 200, pitch: -20));
      expect(d.update(frame(t: 400, pitch: 0)).completed, true);
    });
  });

  group('HeadPoseDetector', () {
    test('lookLeft completes after held yaw', () {
      final d = HeadPoseDetector(tuning, action: LivenessAction.lookLeft);
      expect(d.update(frame(t: 0, yaw: 30)).completed, false);
      expect(d.update(frame(t: 500, yaw: 30)).completed, true);
    });

    test('lookRight uses negative yaw', () {
      final d = HeadPoseDetector(tuning, action: LivenessAction.lookRight);
      expect(d.update(frame(t: 0, yaw: -30)).completed, false);
      expect(d.update(frame(t: 500, yaw: -30)).completed, true);
    });

    test('does not complete below threshold', () {
      final d = HeadPoseDetector(tuning, action: LivenessAction.lookLeft);
      d.update(frame(t: 0, yaw: 10));
      expect(d.update(frame(t: 1000, yaw: 10)).completed, false);
    });
  });

  group('OpenMouthDetector', () {
    test('completes after held open mouth', () {
      final d = OpenMouthDetector(tuning);
      expect(d.update(frame(t: 0, mouthOpen: 0.5)).completed, false);
      expect(d.update(frame(t: 600, mouthOpen: 0.5)).completed, true);
    });
  });

  group('CircleNoseDetector', () {
    test('completes after a full head circle (yaw/pitch)', () {
      final d = CircleNoseDetector(tuning);
      const radius = 15.0; // degrees of head deflection
      DetectorUpdate? last;
      // Sweep 360 degrees in 24 steps over 3 seconds.
      for (var i = 0; i <= 24; i++) {
        final angle = i * (2 * math.pi / 24);
        last = d.update(frame(
          t: i * 125,
          yaw: radius * math.cos(angle),
          pitch: radius * math.sin(angle),
        ));
        if (last.completed) break;
      }
      expect(last!.completed, true);
    });

    test('does not complete for a static head', () {
      final d = CircleNoseDetector(tuning);
      DetectorUpdate? last;
      for (var i = 0; i < 30; i++) {
        last = d.update(frame(t: i * 100, yaw: 8, pitch: 0));
      }
      expect(last!.completed, false);
    });

    test('back-and-forth motion does not accumulate sweep', () {
      final d = CircleNoseDetector(tuning);
      DetectorUpdate? last;
      // Oscillate yaw only: angle flips between 0 and 180 via center, but
      // passing under circleMinRadius clears _lastAngle each crossing.
      for (var i = 0; i < 40; i++) {
        final yaw = (i % 4 < 2) ? 15.0 : -15.0;
        last = d.update(frame(t: i * 100, yaw: yaw, pitch: 0));
      }
      expect(last!.completed, false);
    });
  });
}
