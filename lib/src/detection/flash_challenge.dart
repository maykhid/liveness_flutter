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
  FlashChallenge({
    Random? random,
    this.allowedMisses = 0,
    this.k = 3,
    this.settle = const Duration(milliseconds: 150),
    this.minDelta = 0.004,
  }) : colors = List.of(_channels)..shuffle(random ?? Random.secure());

  static const _channels = [Channel.red, Channel.green, Channel.blue];

  /// Randomized per session.
  final List<Channel> colors;

  /// Colour phases that may fail while the challenge still passes.
  final int allowedMisses;

  /// How many standard errors the expected channel must rise by.
  final double k;

  /// Samples this soon after a phase starts are dropped: the display and
  /// the camera both need a moment to show the new colour.
  final Duration settle;

  /// Absolute floor on the required chromaticity rise, so a perfectly
  /// steady (or synthetic) baseline can't make the bar zero.
  final double minDelta;

  int _phase = -1;
  int? _phaseStartMs;

  /// -1 = baseline (no tint), 0.. = index into [colors].
  int get phase => _phase;

  /// Starts [phase] at [timestampMs] (same clock as [addSample]).
  void beginPhase(int phase, int timestampMs) {
    _phase = phase;
    _phaseStartMs = timestampMs;
  }

  final Map<int, List<List<double>>> _samples = {};

  /// Feed one frame's mean face-region RGB (0–255 each). With a
  /// [timestampMs], samples inside the [settle] window are ignored.
  void addSample(List<double> rgb, {int? timestampMs}) {
    final start = _phaseStartMs;
    if (timestampMs != null &&
        start != null &&
        timestampMs - start < settle.inMilliseconds) {
      return;
    }
    final sum = rgb[0] + rgb[1] + rgb[2];
    if (sum <= 0) return;
    (_samples[_phase] ??= []).add([rgb[0] / sum, rgb[1] / sum, rgb[2] / sum]);
  }

  /// Chromaticity samples of [phase] for [channel].
  List<double> _series(int phase, int channel) =>
      [for (final s in _samples[phase] ?? const <List<double>>[]) s[channel]];

  static double _mean(List<double> xs) =>
      xs.reduce((a, b) => a + b) / xs.length;

  static double _std(List<double> xs) {
    final m = _mean(xs);
    var acc = 0.0;
    for (final x in xs) {
      acc += (x - m) * (x - m);
    }
    return sqrt(acc / (xs.length - 1));
  }

  /// True = the face reflected every colour (within [allowedMisses]),
  /// false = it didn't, null = too few samples to judge (treat as
  /// inconclusive, not as failure).
  ///
  /// A phase counts as correct when its colour's channel rises by more
  /// than `max(minDelta, k × standard error)` both against the baseline
  /// and against every other colour phase. The standard error of a
  /// difference of means uses the per-frame noise σ measured on the
  /// baseline, so pure noise has to beat ~3σ several times over.
  bool? evaluate() {
    const minSamples = 3;
    if ((_samples[-1]?.length ?? 0) < minSamples) return null;
    for (var i = 0; i < colors.length; i++) {
      if ((_samples[i]?.length ?? 0) < minSamples) return null;
    }

    var misses = 0;
    for (var i = 0; i < colors.length; i++) {
      final c = colors[i].index; // Channel enum order = RGB order
      final sigma = _std(_series(-1, c));
      final flash = _series(i, c);
      final flashMean = _mean(flash);

      bool beats(List<double> other) {
        final se = sigma * sqrt(1 / flash.length + 1 / other.length);
        return flashMean - _mean(other) > max(minDelta, k * se);
      }

      var ok = beats(_series(-1, c));
      for (var j = 0; ok && j < colors.length; j++) {
        if (j != i) ok = beats(_series(j, c));
      }
      if (!ok) misses++;
    }
    return misses <= allowedMisses;
  }

  Map<String, Object?> metadataFor(bool? passed) => {
        'flashChallenge': passed == null
            ? 'inconclusive'
            : passed
                ? 'passed'
                : 'failed',
        'flashChallengeOrder': colors.map((c) => c.name).toList(),
      };

  /// Mean R/G/B over the centre 50% of the frame (subsampled).
  static List<double>? sampleCenterRgb(CameraImage image) =>
      sampleRgb(image, region: const Rect.fromLTRB(0.25, 0.25, 0.75, 0.75));

  /// Mean R/G/B over [region] (normalised to the camera buffer, 0..1),
  /// subsampled. Pass the face's box so background doesn't dilute the
  /// reflection.
  static List<double>? sampleRgb(CameraImage image, {required Rect region}) {
    if (image.planes.isEmpty) return null;
    final width = image.width;
    final height = image.height;
    final area = region.intersect(const Rect.fromLTRB(0, 0, 1, 1));
    if (area.isEmpty) return null;
    final x0 = (area.left * width).floor(), x1 = (area.right * width).ceil();
    final y0 = (area.top * height).floor();
    final y1 = (area.bottom * height).ceil();
    // ~40 samples per axis whatever the region size.
    final step = max(2, min(x1 - x0, y1 - y0) ~/ 40);

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
