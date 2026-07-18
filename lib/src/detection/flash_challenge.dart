import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:camera/camera.dart';

/// Screen-reflection ("color flash") challenge.
///
/// After the actions succeed, the screen is tinted with a short sequence of
/// randomly ordered colors. A real face, lit by the phone screen, reflects
/// each color — the matching channel of the camera image rises measurably.
/// A replayed video can't know this session's random color order, so its
/// "face" doesn't respond.
///
/// This is a *soft* signal: it works well indoors, but in bright daylight
/// the screen contributes too little light to measure reliably. A failed
/// challenge therefore lowers `confidenceScore` (and is reported in
/// `metadata`) rather than failing the session.
class FlashChallenge {
  FlashChallenge({Random? random})
      : colors = List.of(_channels)..shuffle(random ?? Random.secure());

  static const _channels = [Channel.red, Channel.green, Channel.blue];

  /// Randomized per session.
  final List<Channel> colors;

  /// -1 = baseline (no tint), 0.. = index into [colors].
  int phase = -1;

  final Map<int, List<List<double>>> _samples = {};

  /// Feed one frame's mean center-region RGB (0–255 each).
  void addSample(List<double> rgb) =>
      (_samples[phase] ??= []).add(rgb);

  /// Chromaticity (channel share of total) averaged over a phase's samples.
  List<double>? _chroma(int phase) {
    final samples = _samples[phase];
    if (samples == null || samples.length < 3) return null;
    var r = 0.0, g = 0.0, b = 0.0;
    for (final s in samples) {
      final sum = s[0] + s[1] + s[2];
      if (sum <= 0) continue;
      r += s[0] / sum;
      g += s[1] / sum;
      b += s[2] / sum;
    }
    final n = samples.length;
    return [r / n, g / n, b / n];
  }

  /// True = face reflected the colors, false = it didn't, null = not enough
  /// samples to judge (treat as inconclusive, not as failure).
  bool? evaluate() {
    final baseline = _chroma(-1);
    if (baseline == null) return null;

    var judged = 0;
    var correct = 0;
    for (var i = 0; i < colors.length; i++) {
      final flash = _chroma(i);
      if (flash == null) continue;
      judged++;
      final deltas = [
        flash[0] - baseline[0],
        flash[1] - baseline[1],
        flash[2] - baseline[2],
      ];
      final expected = colors[i].index; // Channel enum order = RGB order
      final maxDelta = deltas.reduce(max);
      // The flashed channel must rise, and rise more than the others.
      if (deltas[expected] > 0.004 && deltas[expected] == maxDelta) {
        correct++;
      }
    }
    if (judged < 2) return null;
    return correct >= judged - 1; // allow one miss
  }

  Map<String, Object?> metadataFor(bool? passed) => {
        'flashChallenge': passed == null
            ? 'inconclusive'
            : passed
                ? 'passed'
                : 'failed',
        'flashChallengeOrder': colors.map((c) => c.name).toList(),
      };

  /// Mean R/G/B over the center 50% of the frame (subsampled). The face is
  /// centered by the session's own positioning requirement, so the center
  /// region is face-dominated without needing coordinate-space gymnastics.
  static List<double>? sampleCenterRgb(CameraImage image) {
    if (image.planes.isEmpty) return null;
    final width = image.width;
    final height = image.height;
    final x0 = width ~/ 4, x1 = width * 3 ~/ 4;
    final y0 = height ~/ 4, y1 = height * 3 ~/ 4;
    const step = 8;

    var r = 0.0, g = 0.0, b = 0.0;
    var count = 0;

    final isBgra = Platform.isIOS && image.planes.length == 1;
    if (isBgra) {
      final plane = image.planes.first;
      final bytes = plane.bytes;
      final stride = plane.bytesPerRow;
      for (var y = y0; y < y1; y += step) {
        for (var x = x0; x < x1; x += step) {
          final i = y * stride + x * 4;
          if (i + 2 >= bytes.length) continue;
          b += bytes[i];
          g += bytes[i + 1];
          r += bytes[i + 2];
          count++;
        }
      }
    } else {
      // YUV (Android NV21 single-plane, or iOS NV12 bi-planar).
      final yPlane = image.planes.first;
      final yBytes = yPlane.bytes;
      final yStride = yPlane.bytesPerRow > 0 ? yPlane.bytesPerRow : width;
      final biPlanar = image.planes.length >= 2;
      final uvBytes = biPlanar ? image.planes[1].bytes : yBytes;
      final uvStride = biPlanar
          ? image.planes[1].bytesPerRow
          : yStride;
      final uvBase = biPlanar ? 0 : yStride * height;

      for (var y = y0; y < y1; y += step) {
        final uvRow = uvBase + (y >> 1) * uvStride;
        for (var x = x0; x < x1; x += step) {
          final yi = y * yStride + x;
          final uvi = uvRow + (x & ~1);
          if (yi >= yBytes.length || uvi + 1 >= uvBytes.length) continue;
          final yv = yBytes[yi].toDouble();
          // NV21 interleaves V,U; NV12 interleaves U,V.
          final double u, v;
          if (biPlanar) {
            u = uvBytes[uvi] - 128.0;
            v = uvBytes[uvi + 1] - 128.0;
          } else {
            v = uvBytes[uvi] - 128.0;
            u = uvBytes[uvi + 1] - 128.0;
          }
          r += (yv + 1.402 * v).clamp(0.0, 255.0);
          g += (yv - 0.344136 * u - 0.714136 * v).clamp(0.0, 255.0);
          b += (yv + 1.772 * u).clamp(0.0, 255.0);
          count++;
        }
      }
    }
    if (count == 0) return null;
    return [r / count, g / count, b / count];
  }
}

/// RGB order matters: index must match the [r, g, b] sample layout.
enum Channel { red, green, blue }

extension ChannelColor on Channel {
  Color get tint {
    switch (this) {
      case Channel.red:
        return const Color(0xFFFF0000);
      case Channel.green:
        return const Color(0xFF00FF00);
      case Channel.blue:
        return const Color(0xFF0000FF);
    }
  }
}
