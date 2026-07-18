import '../models/models.dart';

/// Pure-Dart anti-spoof signal collector. No ML, no dependencies — it
/// watches two things that are very hard to fake with cheap attacks:
///
/// 1. **Sensor noise.** A real camera never produces two pixel-identical
///    frames. A long streak of identical frame hashes means a static image
///    or injected feed → [replaySuspected] (hard fail, if enabled).
/// 2. **Micro-motion.** A live head is never perfectly still; yaw/pitch
///    jitter constantly by fractions of a degree. Windows with near-zero
///    motion range lower the confidence score (soft signal only — some
///    people hold very still, so this never hard-fails on its own).
class SpoofGuard {
  SpoofGuard({
    this.duplicateStreakLimit = 15,
    this.motionWindowSize = 20,
    this.motionMinRangeDegrees = 0.8,
  });

  /// Consecutive identical frames before [replaySuspected] (15 frames at
  /// ~10 fps ≈ 1.5 s of physically impossible stillness).
  final int duplicateStreakLimit;

  /// Frames per micro-motion window.
  final int motionWindowSize;

  /// Combined yaw+pitch range below which a window counts as "unnaturally
  /// still".
  final double motionMinRangeDegrees;

  int? _lastHash;
  int _duplicateStreak = 0;
  int totalDuplicates = 0;

  final List<double> _yaws = [];
  final List<double> _pitches = [];
  int lowMotionWindows = 0;
  int totalMotionWindows = 0;

  /// Feed one processed frame. [hash] from `FrameQuality.hash`; [face] the
  /// primary face if any.
  void onFrame({int? hash, FaceSnapshot? face}) {
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
    return penalty.clamp(0.0, 0.7);
  }

  /// Diagnostics for `LivenessResult.metadata`.
  Map<String, Object?> get metadata => {
        'confidence_duplicateFrames': totalDuplicates,
        'confidence_lowMotionWindows': lowMotionWindows,
        'confidence_motionWindows': totalMotionWindows,
      };
}
