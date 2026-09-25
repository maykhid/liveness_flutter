import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';
import 'package:liveness_flutter/src/camera/detection_geometry.dart';

/// Simulates the widget's timing: 600 ms baseline, then three 650 ms
/// colour phases, one frame every 33 ms. Each frame's face-region mean is
/// (120, 110, 100) plus uniform ±[noise] per channel, plus [reflection]
/// levels on the flashed channel.
FlashChallenge simulate(
  int seed, {
  double reflection = 0,
  double noise = 10,
  int allowedMisses = 0,
  Set<int> unreflectedPhases = const {},
  List<double>? firstFramesOfPhase,
}) {
  final rng = Random(seed);
  final challenge =
      FlashChallenge(random: Random(seed + 1), allowedMisses: allowedMisses);
  var t = 0;
  double n() => (rng.nextDouble() * 2 - 1) * noise;

  void run(int phase, int durationMs) {
    challenge.beginPhase(phase, t);
    final phaseStart = t;
    for (; t < phaseStart + durationMs; t += 33) {
      final rgb = [120 + n(), 110 + n(), 100 + n()];
      if (firstFramesOfPhase != null && t - phaseStart < 150) {
        challenge.addSample(firstFramesOfPhase, timestampMs: t);
        continue;
      }
      if (phase >= 0 && !unreflectedPhases.contains(phase)) {
        rgb[challenge.colors[phase].index] += reflection;
      }
      challenge.addSample(rgb, timestampMs: t);
    }
  }

  run(-1, 600);
  for (var i = 0; i < 3; i++) {
    run(i, 650);
  }
  return challenge;
}

/// The pre-0.5 criterion, kept here to document the improvement: mean
/// chromaticity per phase (no settle window), the flashed channel must
/// rise > 0.004 and rise most, one miss allowed.
bool? legacyEvaluate(int seed, {double noise = 10}) {
  final rng = Random(seed);
  final colors = [0, 1, 2]..shuffle(Random(seed + 1));
  double n() => (rng.nextDouble() * 2 - 1) * noise;
  List<double> chroma(int frames) {
    var r = 0.0, g = 0.0, b = 0.0;
    for (var i = 0; i < frames; i++) {
      final s = [120 + n(), 110 + n(), 100 + n()];
      final sum = s[0] + s[1] + s[2];
      r += s[0] / sum;
      g += s[1] / sum;
      b += s[2] / sum;
    }
    return [r / frames, g / frames, b / frames];
  }

  final base = chroma(19);
  var correct = 0;
  for (var i = 0; i < 3; i++) {
    final flash = chroma(20);
    final deltas = [for (var c = 0; c < 3; c++) flash[c] - base[c]];
    final expected = colors[i];
    if (deltas[expected] > 0.004 && deltas[expected] == deltas.reduce(max)) {
      correct++;
    }
  }
  return correct >= 2;
}

void main() {
  group('S5 flash challenge', () {
    const trials = 2000;

    test('pure noise passes under 1 % of the time', () {
      var passes = 0;
      for (var seed = 0; seed < trials; seed++) {
        if (simulate(seed).evaluate() == true) passes++;
      }
      expect(passes / trials, lessThan(0.01));
    });

    test('(for reference) the old criterion passed noise far more often', () {
      // ~5 % under this noise model (the audit measured ~10 % under its
      // own). The new criterion: 0 of 5,000 in the same simulation.
      var passes = 0;
      for (var seed = 0; seed < trials; seed++) {
        if (legacyEvaluate(seed) == true) passes++;
      }
      expect(passes / trials, greaterThan(0.03));
    });

    test('a clear reflection passes', () {
      var passes = 0;
      for (var seed = 0; seed < trials; seed++) {
        if (simulate(seed, reflection: 25).evaluate() == true) passes++;
      }
      expect(passes / trials, greaterThan(0.99));
    });

    test('a steady scene with a modest reflection passes', () {
      for (var seed = 0; seed < 50; seed++) {
        expect(simulate(seed, reflection: 8, noise: 1).evaluate(), isTrue);
      }
    });

    test('all phases must be reflected by default', () {
      for (var seed = 0; seed < 50; seed++) {
        expect(
          simulate(seed, reflection: 25, unreflectedPhases: {1}).evaluate(),
          isFalse,
        );
      }
    });

    test('allowedMisses lets one phase fail', () {
      for (var seed = 0; seed < 50; seed++) {
        expect(
          simulate(seed,
                  reflection: 25, unreflectedPhases: {1}, allowedMisses: 1)
              .evaluate(),
          isTrue,
        );
      }
    });

    test('the first 150 ms of each phase is ignored', () {
      // Garbage while the display and camera catch up must not matter.
      for (var seed = 0; seed < 50; seed++) {
        expect(
          simulate(seed,
                  reflection: 25,
                  noise: 2,
                  firstFramesOfPhase: const [255, 0, 0])
              .evaluate(),
          isTrue,
        );
      }
    });

    test('too few samples is inconclusive', () {
      final c = FlashChallenge()
        ..beginPhase(-1, 0)
        ..addSample(const [120, 110, 100], timestampMs: 200);
      expect(c.evaluate(), isNull);
    });
  });

  group('S5 faceSpaceToBuffer', () {
    const box = Rect.fromLTRB(0.2, 0.1, 0.5, 0.4);

    test('iOS (buffer coordinates) is unchanged', () {
      expect(
        faceSpaceToBuffer(box, rotationDegrees: 90, uprightCoordinates: false),
        box,
      );
    });

    test('Android upright → buffer undoes the rotation', () {
      Rect map(int r) =>
          faceSpaceToBuffer(box, rotationDegrees: r, uprightCoordinates: true);
      expect(map(0), box);
      // 90° clockwise put the buffer's left edge on top.
      expect(map(90), const Rect.fromLTRB(0.1, 0.5, 0.4, 0.8));
      expect(map(270), const Rect.fromLTRB(0.6, 0.2, 0.9, 0.5));
      expect(map(180), const Rect.fromLTRB(0.5, 0.6, 0.8, 0.9));
    });

    test('agrees with DetectionGeometry for a quarter turn', () {
      for (final r in [90, 270]) {
        final g = DetectionGeometry(
          viewSize: const Size(720, 1280),
          faceSpaceSize: const Size(1280, 720),
          rotationDegrees: r,
          mirrored: false,
        );
        final viaGeometry = g.viewRectToFace(box);
        final viaHelper = faceSpaceToBuffer(box,
            rotationDegrees: r, uprightCoordinates: true);
        expect((viaGeometry.left - viaHelper.left).abs(), lessThan(1e-9));
        expect((viaGeometry.bottom - viaHelper.bottom).abs(), lessThan(1e-9));
      }
    });
  });
}
