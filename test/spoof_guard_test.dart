import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

FaceSnapshot face(int t, {double yaw = 0, double pitch = 0}) => FaceSnapshot(
      timestampMs: t,
      headEulerAngleX: pitch,
      headEulerAngleY: yaw,
      boundingBox: const Rect.fromLTWH(0.3, 0.3, 0.4, 0.4),
    );

void main() {
  test('replay suspected after a long run of identical hashes', () {
    final guard = SpoofGuard(duplicateStreakLimit: 15);
    // 15 frames = 14 repeats after the first: not yet suspected.
    for (var i = 0; i < 15; i++) {
      guard.onFrame(hash: 12345, face: face(i * 100));
    }
    expect(guard.replaySuspected, false);
    // 16th identical frame = 15 consecutive repeats: suspected.
    guard.onFrame(hash: 12345, face: face(1600));
    expect(guard.replaySuspected, true);
  });

  test('changing hashes never trip the replay guard', () {
    final guard = SpoofGuard();
    for (var i = 0; i < 100; i++) {
      guard.onFrame(hash: i, face: face(i * 100));
    }
    expect(guard.replaySuspected, false);
    expect(guard.totalDuplicates, 0);
  });

  test('natural micro-motion produces no penalty', () {
    final guard = SpoofGuard(motionWindowSize: 10);
    for (var i = 0; i < 50; i++) {
      // Realistic jitter: ±1.5 degrees.
      guard.onFrame(
        hash: i,
        face: face(i * 100, yaw: (i % 3) * 1.5, pitch: (i % 2) * 1.0),
      );
    }
    expect(guard.lowMotionWindows, 0);
    expect(guard.confidencePenalty, 0);
  });

  test('perfectly still head accumulates low-motion windows', () {
    final guard = SpoofGuard(motionWindowSize: 10);
    for (var i = 0; i < 50; i++) {
      guard.onFrame(hash: i, face: face(i * 100, yaw: 5.0, pitch: 2.0));
    }
    expect(guard.lowMotionWindows, greaterThan(0));
    expect(guard.confidencePenalty, greaterThan(0));
    // Soft signal only — must never hard-fail.
    expect(guard.replaySuspected, false);
  });
}
