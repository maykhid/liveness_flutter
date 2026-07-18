import 'dart:io';

import 'package:camera/camera.dart';

/// Cheap per-frame quality metrics, computed by subsampling ~1 in 256
/// pixels of the luma channel. Costs well under a millisecond per frame.
class FrameQuality {
  const FrameQuality({
    required this.brightness,
    required this.sharpness,
    required this.hash,
  });

  /// Mean luma, 0 (black) – 1 (white).
  final double brightness;

  /// Luma standard deviation, 0–1. Low values mean a flat image — usually
  /// blur/out-of-focus (or a featureless surface held to the camera).
  final double sharpness;

  /// FNV-1a hash of the sampled pixels. Two frames from a live camera are
  /// never pixel-identical (sensor noise); repeated identical hashes mean
  /// static/injected input. Used by the replay guard.
  final int hash;
}

class FrameQualityAnalyzer {
  FrameQualityAnalyzer._();

  /// Sample step in bytes; 16 in x and every 16th row ≈ 1/256 of pixels.
  static const _step = 16;

  static FrameQuality? analyze(CameraImage image) {
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final width = image.width;
    final height = image.height;
    final stride = plane.bytesPerRow > 0 ? plane.bytesPerRow : width;

    // Luma source: Android NV21 plane 0 is the Y plane directly. iOS BGRA
    // has no luma plane — the green channel is a good proxy (it dominates
    // luma perception). NV12 (iOS fallback) plane 0 is also Y.
    final isBgra = Platform.isIOS && image.planes.length == 1;
    final bytesPerPixel = isBgra ? 4 : 1;
    final channelOffset = isBgra ? 1 : 0; // G in BGRA

    var count = 0;
    var sum = 0;
    var sumSq = 0;
    var hash = 0x811c9dc5; // FNV-1a 32-bit offset basis

    for (var y = 0; y < height; y += _step) {
      final rowStart = y * stride;
      for (var x = 0; x < width; x += _step) {
        final index = rowStart + x * bytesPerPixel + channelOffset;
        if (index >= bytes.length) continue;
        final value = bytes[index];
        sum += value;
        sumSq += value * value;
        count++;
        hash = ((hash ^ value) * 0x01000193) & 0xFFFFFFFF;
      }
    }
    if (count == 0) return null;

    final mean = sum / count;
    final variance = (sumSq / count) - (mean * mean);
    final stdDev = variance <= 0 ? 0.0 : _sqrt(variance);

    return FrameQuality(
      brightness: mean / 255.0,
      sharpness: stdDev / 255.0,
      hash: hash,
    );
  }

  // Newton's method — avoids importing dart:math for one call site.
  static double _sqrt(double v) {
    var x = v;
    for (var i = 0; i < 12; i++) {
      x = 0.5 * (x + v / x);
    }
    return x;
  }
}
