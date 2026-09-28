import 'dart:math';
import 'dart:typed_data';
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

  group('S6 near-duplicate frames', () {
    final rng = Random(3);
    final base = Uint8List.fromList(
        List.generate(3600, (_) => 40 + rng.nextInt(170)));

    /// [base] with each sample moved by up to ±[jitter] levels.
    Uint8List noisy(int jitter) => Uint8List.fromList([
          for (final v in base)
            (v + (jitter == 0 ? 0 : rng.nextInt(2 * jitter + 1) - jitter))
                .clamp(0, 255),
        ]);

    FaceSnapshot at(int t, {double dx = 0}) => FaceSnapshot(
          timestampMs: t,
          headEulerAngleX: 0,
          headEulerAngleY: 0,
          boundingBox: Rect.fromLTWH(0.3 + dx, 0.3, 0.4, 0.4),
        );

    /// A re-encoded still: ~30 % of samples off by one level.
    Uint8List reencoded() => Uint8List.fromList([
          for (final v in base)
            rng.nextDouble() < 0.3 ? (v + 1).clamp(0, 255) : v,
        ]);

    test('a near-identical feed with a frozen face box is flagged softly', () {
      final guard = SpoofGuard();
      for (var i = 0; i < 20; i++) {
        // Different hash each frame (tiny re-encoding changes), so the
        // exact-duplicate check can't see it.
        guard.onFrame(hash: i, face: at(i * 100), luma: reencoded());
      }
      expect(guard.replaySuspected, isFalse, reason: 'never a hard fail');
      expect(guard.nearDuplicateRuns, 1);
      expect(guard.confidencePenalty, greaterThanOrEqualTo(0.15));
      expect(guard.metadata['confidence_nearDuplicateRuns'], 1);
    });

    test('live sensor noise is not a near-duplicate', () {
      final guard = SpoofGuard();
      for (var i = 0; i < 40; i++) {
        guard.onFrame(hash: i, face: at(i * 100), luma: noisy(4));
      }
      expect(guard.nearDuplicateFrames, 0);
    });

    test('a moving face box is not a near-duplicate', () {
      final guard = SpoofGuard();
      for (var i = 0; i < 40; i++) {
        guard.onFrame(
          hash: i,
          face: at(i * 100, dx: (i % 3) * 0.004),
          luma: noisy(0),
        );
      }
      expect(guard.nearDuplicateRuns, 0);
    });

    test('without luma samples nothing is judged', () {
      final guard = SpoofGuard();
      for (var i = 0; i < 40; i++) {
        guard.onFrame(hash: i, face: at(i * 100));
      }
      expect(guard.nearDuplicateFrames, 0);
    });
  });
}
