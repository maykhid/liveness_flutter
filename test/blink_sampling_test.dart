import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

import 'support/fake_frame_source.dart' as fake;

FaceSnapshot eyes(int t, double open) => FaceSnapshot(
      timestampMs: t,
      leftEyeOpenProbability: open,
      rightEyeOpenProbability: open,
      boundingBox: const Rect.fromLTWH(0.3, 0.3, 0.4, 0.4),
    );

/// One blink with the eyes fully shut for [closedMs], lids moving for
/// 10 ms either side (half-open readings), sampled every [intervalMs]
/// from a random phase. Returns whether the detector saw a blink.
bool blinkDetected(Random rng, {required int intervalMs, int closedMs = 60}) {
  final detector = BlinkDetector(const DetectorTuning());
  final blinkStart = 500 + rng.nextInt(intervalMs);
  double openness(int t) {
    final rel = t - blinkStart;
    if (rel < -10 || rel > closedMs + 10) return 0.95;
    if (rel < 0 || rel > closedMs) return 0.45; // lids moving
    return 0.05;
  }

  for (var t = 0; t < 1500; t += intervalMs) {
    if (detector.update(eyes(t, openness(t))).completed) return true;
  }
  return false;
}

void main() {
  group('D1 blink sampling', () {
    test('a 60 ms closure is caught ≥ 95 % of the time at 20 fps', () {
      final rng = Random(11);
      var hits = 0;
      const runs = 2000;
      for (var i = 0; i < runs; i++) {
        if (blinkDetected(rng, intervalMs: 50)) hits++;
      }
      expect(hits / runs, greaterThanOrEqualTo(0.95));
    });

    test('(for reference) at 10 fps it is missed a large share of the time',
        () {
      final rng = Random(11);
      var hits = 0;
      const runs = 2000;
      for (var i = 0; i < runs; i++) {
        if (blinkDetected(rng, intervalMs: 100)) hits++;
      }
      expect(hits / runs, lessThan(0.9));
    });

    test('a half-shut frame between open frames counts as a blink', () {
      final d = BlinkDetector(const DetectorTuning());
      d.update(eyes(0, 0.95));
      d.update(eyes(50, 0.35));
      expect(d.update(eyes(100, 0.95)).completed, isTrue);
    });

    test('partial closes can be switched off', () {
      final d = BlinkDetector(
          const DetectorTuning(blinkPartialCloseThreshold: 0.25));
      d.update(eyes(0, 0.95));
      d.update(eyes(50, 0.35));
      expect(d.update(eyes(100, 0.95)).completed, isFalse);
    });

    test('a long squint does not count', () {
      final d = BlinkDetector(const DetectorTuning());
      d.update(eyes(0, 0.95));
      for (var t = 50; t <= 2000; t += 50) {
        d.update(eyes(t, 0.35));
      }
      expect(d.update(eyes(2050, 0.95)).completed, isFalse);
    });
  });

  group('D1 ML throttle', () {
    final harness = fake.FakeSourceHarness();
    setUp(harness.install);
    tearDown(harness.uninstall);

    Future<int> detectionsDuring(
        WidgetTester tester, LivenessAction action) async {
      fake.usePhoneScreen(tester);
      await tester.pumpWidget(MaterialApp(
        home: LivenessDetector(
          config: LivenessConfig(actions: [action]),
          onResult: (_) {},
        ),
      ));
      await tester.pump();
      await harness.step(tester, [fake.face()]); // action starts
      final before = harness.source.detections;
      for (var i = 0; i < 20; i++) {
        await harness.step(tester, [fake.face()], ms: 50);
      }
      return harness.source.detections - before;
    }

    testWidgets('blink actions are analysed at ~20 fps', (tester) async {
      expect(await detectionsDuring(tester, LivenessAction.blink),
          greaterThanOrEqualTo(18));
    });

    testWidgets('other actions stay at ~10 fps', (tester) async {
      expect(await detectionsDuring(tester, LivenessAction.smile),
          lessThanOrEqualTo(11));
    });
  });
}
