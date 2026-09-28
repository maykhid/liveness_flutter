import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

FaceSnapshot f(
  int t, {
  double eyes = 0.95,
  double pitch = 0,
  double yaw = 0,
  double smile = 0.05,
}) =>
    FaceSnapshot(
      timestampMs: t,
      smileProbability: smile,
      leftEyeOpenProbability: eyes,
      rightEyeOpenProbability: eyes,
      headEulerAngleX: pitch,
      headEulerAngleY: yaw,
      headEulerAngleZ: 0,
      boundingBox: const Rect.fromLTWH(0.3, 0.3, 0.4, 0.4),
    );

/// Feeds [frames] and returns the timestamps flagged as peaks, plus the
/// completion timestamp.
(List<int> peaks, int? doneAt) run(
    ActionDetector d, List<FaceSnapshot> frames) {
  final peaks = <int>[];
  int? doneAt;
  for (final frame in frames) {
    final u = d.update(frame);
    if (u.isPeak) peaks.add(frame.timestampMs);
    if (u.completed) {
      doneAt = frame.timestampMs;
      break;
    }
  }
  return (peaks, doneAt);
}

void main() {
  const tuning = DetectorTuning();

  group('B5 isPeak', () {
    test('blink: the first eyes-closed frame, not the reopen', () {
      final (peaks, doneAt) = run(BlinkDetector(tuning), [
        f(0),
        f(100, eyes: 0.5), // half-closed: not yet
        f(200, eyes: 0.1), // shut → peak
        f(300, eyes: 0.1),
        f(400), // reopened → done
      ]);
      expect(peaks, [200]);
      expect(doneAt, 400);
    });

    test('nod: the deepest pitch, not the return to neutral', () {
      final (peaks, doneAt) = run(NodDetector(tuning), [
        f(0),
        f(100, pitch: -8),
        f(200, pitch: -14), // past threshold → peak
        f(300, pitch: -22), // deeper → peak
        f(400, pitch: -18), // shallower → not a peak
        f(500, pitch: -1), // back up → done
      ]);
      expect(peaks, [200, 300]);
      expect(peaks.last, 300);
      expect(doneAt, 500);
    });

    test('lookLeft: the start of the hold, not its end', () {
      final (peaks, doneAt) = run(
        HeadPoseDetector(tuning, action: LivenessAction.lookLeft),
        [
          f(0),
          f(100, yaw: 15), // approaching
          f(200, yaw: 30), // past threshold → hold starts → peak
          f(400, yaw: 32),
          f(600, yaw: 31), // 400 ms held → done
        ],
      );
      expect(peaks, [200]);
      expect(doneAt, 600);
    });

    test('a broken hold marks a new peak when it restarts', () {
      final (peaks, _) = run(SmileDetector(tuning, fullTeeth: false), [
        f(0, smile: 0.9),
        f(100, smile: 0.2),
        f(200, smile: 0.9),
        f(800, smile: 0.9),
      ]);
      expect(peaks, [0, 200]);
    });

    test('eyesClosed: the start of the closed hold', () {
      final (peaks, _) = run(EyesClosedDetector(tuning), [
        f(0),
        f(100, eyes: 0.1),
        f(1000, eyes: 0.1),
        f(2200, eyes: 0.1),
      ]);
      expect(peaks, [100]);
    });
  });

  test('B5 session emits ActionPeakEvent before ActionCompletedEvent', () {
    final session = LivenessSession(
      const LivenessConfig(actions: [LivenessAction.blink]),
    )..start();
    final events = <LivenessEvent>[];
    session.addEventListener(events.add);

    session.onFrame(faces: [f(0)], faceInPosition: true, timestampMs: 0);
    session.onFrame(faces: [f(100)], faceInPosition: true, timestampMs: 100);
    session.onFrame(
        faces: [f(200, eyes: 0.1)], faceInPosition: true, timestampMs: 200);
    session.onFrame(faces: [f(300)], faceInPosition: true, timestampMs: 300);

    final peak = events.whereType<ActionPeakEvent>().single;
    expect(peak.action, LivenessAction.blink);
    expect(peak.index, 0);
    expect(peak.timestampMs, 200);
    expect(
      events.indexOf(peak),
      lessThan(events.indexWhere((e) => e is ActionCompletedEvent)),
    );
  });
}
