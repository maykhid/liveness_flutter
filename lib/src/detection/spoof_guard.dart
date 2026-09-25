import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import '../models/models.dart';

/// Pure-Dart **static-feed guard** (historically "replay guard"). No ML, no
/// dependencies. It watches for input that can't come from a live camera
/// pointed at a live person:
///
/// 1. **Sensor noise.** A real camera never produces two pixel-identical
///    frames. A long streak of identical frame hashes means a static image
///    or injected feed → [replaySuspected] (hard fail, if enabled).
/// 2. **Near-duplicates.** Frames that differ by less than sensor noise
///    ([nearDuplicateMaxDiff] mean luma difference) while the face box
///    doesn't move at all — e.g. a re-encoded still injected as a camera.
///    Soft signal: lowers the confidence score, never fails on its own.
/// 3. **Micro-motion.** A live head is never perfectly still; yaw/pitch
///    jitter constantly by fractions of a degree. Windows with near-zero
///    motion range lower the confidence score (soft signal only — some
///    people hold very still, so this never hard-fails on its own).
///
/// What it does **not** detect: a photo, screen or video held up to a real
/// camera. The real camera adds real noise and the person holding it adds
/// real motion. That's what the action challenge, the colour-flash
/// challenge and server-side presentation-attack detection are for.
class SpoofGuard {
  SpoofGuard({
    this.duplicateStreakLimit = 15,
    this.motionWindowSize = 20,
    this.motionMinRangeDegrees = 0.8,
    this.nearDuplicateMaxDiff = 0.5,
    this.nearDuplicateStreakLimit = 15,
    this.staticBoxMaxShift = 0.002,
  });

  /// Consecutive identical frames before [replaySuspected] (15 frames at
  /// ~10 fps ≈ 1.5 s of physically impossible stillness).
  final int duplicateStreakLimit;

  /// Frames per micro-motion window.
  final int motionWindowSize;

  /// Combined yaw+pitch range below which a window counts as "unnaturally
  /// still".
  final double motionMinRangeDegrees;

  /// Mean absolute luma difference (0–255 levels) between consecutive
  /// frames below which they count as near-duplicates. Live sensors are
  /// typically well above 1.
  final double nearDuplicateMaxDiff;

  /// Consecutive near-duplicate frames (with a static face box) that make
  /// one near-duplicate run.
  final int nearDuplicateStreakLimit;

  /// Face-box movement (normalised, max of centre shift and size change)
  /// below which the box counts as static.
  final double staticBoxMaxShift;

  int? _lastHash;
  Uint8List? _lastLuma;
  Rect? _lastBox;
  int _nearDuplicateStreak = 0;

  /// Frames that were near-duplicates of the previous one with a static
  /// face box.
  int nearDuplicateFrames = 0;

  /// Runs of [nearDuplicateStreakLimit] such frames in a row.
  int nearDuplicateRuns = 0;
  int _duplicateStreak = 0;
  int totalDuplicates = 0;

  final List<double> _yaws = [];
  final List<double> _pitches = [];
  int lowMotionWindows = 0;
  int totalMotionWindows = 0;

  /// Feed one processed frame. [hash] and [luma] from `FrameQuality`;
  /// [face] the primary face if any.
  void onFrame({int? hash, FaceSnapshot? face, Uint8List? luma}) {
    _checkNearDuplicate(luma, face?.boundingBox);

    if (hash != null) {
      if (hash == _lastHash) {
        _duplicateStreak++;
        totalDuplicates++;
      } else {
        _duplicateStreak = 0;
      }
      _lastHash = hash;
    }

    final yaw = face?.headEulerAngleY;
    final pitch = face?.headEulerAngleX;
    if (yaw != null && pitch != null) {
      _yaws.add(yaw);
      _pitches.add(pitch);
      if (_yaws.length >= motionWindowSize) {
        _closeMotionWindow();
      }
    }
  }

  void _checkNearDuplicate(Uint8List? luma, Rect? box) {
    final previousLuma = _lastLuma;
    final previousBox = _lastBox;
    _lastLuma = luma;
    _lastBox = box;
    if (luma == null ||
        box == null ||
        previousLuma == null ||
        previousBox == null ||
        luma.length != previousLuma.length ||
        luma.isEmpty) {
      _nearDuplicateStreak = 0;
      return;
    }
    final shift = max(
      (box.center - previousBox.center).distance,
      max((box.width - previousBox.width).abs(),
          (box.height - previousBox.height).abs()),
    );
    var diff = 0;
    for (var i = 0; i < luma.length; i++) {
      diff += (luma[i] - previousLuma[i]).abs();
    }
    final meanDiff = diff / luma.length;
    if (meanDiff < nearDuplicateMaxDiff && shift < staticBoxMaxShift) {
      nearDuplicateFrames++;
      _nearDuplicateStreak++;
      if (_nearDuplicateStreak == nearDuplicateStreakLimit) nearDuplicateRuns++;
    } else {
      _nearDuplicateStreak = 0;
    }
  }

  void _closeMotionWindow() {
    var minY = _yaws.first, maxY = _yaws.first;
    var minP = _pitches.first, maxP = _pitches.first;
    for (var i = 1; i < _yaws.length; i++) {
      if (_yaws[i] < minY) minY = _yaws[i];
      if (_yaws[i] > maxY) maxY = _yaws[i];
      if (_pitches[i] < minP) minP = _pitches[i];
      if (_pitches[i] > maxP) maxP = _pitches[i];
    }
    totalMotionWindows++;
    if ((maxY - minY) + (maxP - minP) < motionMinRangeDegrees) {
      lowMotionWindows++;
    }
    _yaws.clear();
    _pitches.clear();
  }

  /// Hard signal: static/injected input.
  bool get replaySuspected => _duplicateStreak >= duplicateStreakLimit;

  /// 0–1 penalty to subtract from the confidence score.
  double get confidencePenalty {
    var penalty = 0.0;
    // Any duplicates at all are odd; scale gently, cap hard.
    penalty += (totalDuplicates * 0.02).clamp(0.0, 0.4);
    // Fraction of session spent unnaturally still.
    if (totalMotionWindows > 0) {
      penalty += 0.3 * (lowMotionWindows / totalMotionWindows);
    }
    // Sustained near-identical frames with a frozen face box.
    penalty += (nearDuplicateRuns * 0.15).clamp(0.0, 0.3);
    return penalty.clamp(0.0, 0.7);
  }

  /// Diagnostics for `LivenessResult.metadata`.
  Map<String, Object?> get metadata => {
        'confidence_duplicateFrames': totalDuplicates,
        'confidence_lowMotionWindows': lowMotionWindows,
        'confidence_motionWindows': totalMotionWindows,
        'confidence_nearDuplicateFrames': nearDuplicateFrames,
        'confidence_nearDuplicateRuns': nearDuplicateRuns,
      };
}
