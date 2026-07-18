import 'dart:math' as math;

import '../models/models.dart';

/// Result of feeding one frame to an [ActionDetector].
class DetectorUpdate {
  const DetectorUpdate({required this.progress, required this.completed});
  final double progress;
  final bool completed;

  static const none = DetectorUpdate(progress: 0, completed: false);
  static const done = DetectorUpdate(progress: 1, completed: true);
}

/// A pure state machine that decides whether one [LivenessAction] has been
/// performed. Consumes [FaceSnapshot]s; no platform dependencies, so it can
/// be unit-tested with synthetic frames.
abstract class ActionDetector {
  ActionDetector(this.tuning);

  final DetectorTuning tuning;

  LivenessAction get action;

  /// Feed one frame. Returns current progress and completion.
  DetectorUpdate update(FaceSnapshot face);

  /// Reset internal state (called when the action restarts, e.g. after the
  /// face was lost).
  void reset();

  /// Create the built-in detector for [action].
  factory ActionDetector.forAction(
    LivenessAction action,
    DetectorTuning tuning,
  ) {
    switch (action) {
      case LivenessAction.blink:
        return BlinkDetector(tuning);
      case LivenessAction.smile:
        return SmileDetector(tuning, fullTeeth: false);
      case LivenessAction.fullTeethSmile:
        return SmileDetector(tuning, fullTeeth: true);
      case LivenessAction.nod:
        return NodDetector(tuning);
      case LivenessAction.lookLeft:
        return HeadPoseDetector(tuning, action: LivenessAction.lookLeft);
      case LivenessAction.lookRight:
        return HeadPoseDetector(tuning, action: LivenessAction.lookRight);
      case LivenessAction.lookUp:
        return HeadPoseDetector(tuning, action: LivenessAction.lookUp);
      case LivenessAction.lookDown:
        return HeadPoseDetector(tuning, action: LivenessAction.lookDown);
      case LivenessAction.tiltLeft:
        return HeadPoseDetector(tuning, action: LivenessAction.tiltLeft);
      case LivenessAction.tiltRight:
        return HeadPoseDetector(tuning, action: LivenessAction.tiltRight);
      case LivenessAction.eyesClosed:
        return EyesClosedDetector(tuning);
      case LivenessAction.openMouth:
        return OpenMouthDetector(tuning);
      case LivenessAction.drawCircleWithNose:
        return CircleNoseDetector(tuning);
    }
  }
}

/// Eyes open -> both closed -> open again, within [DetectorTuning.blinkMaxDuration].
class BlinkDetector extends ActionDetector {
  BlinkDetector(super.tuning);

  @override
  LivenessAction get action => LivenessAction.blink;

  int _stage = 0; // 0 = waiting open, 1 = waiting closed, 2 = waiting reopen
  int? _closedAtMs;

  @override
  DetectorUpdate update(FaceSnapshot face) {
    final left = face.leftEyeOpenProbability;
    final right = face.rightEyeOpenProbability;
    if (left == null || right == null) return _progress();

    final open = left > tuning.blinkOpenThreshold && right > tuning.blinkOpenThreshold;
    final closed =
        left < tuning.blinkClosedThreshold && right < tuning.blinkClosedThreshold;

    switch (_stage) {
      case 0:
        if (open) _stage = 1;
      case 1:
        if (closed) {
          _stage = 2;
          _closedAtMs = face.timestampMs;
        }
      case 2:
        final elapsed = face.timestampMs - (_closedAtMs ?? face.timestampMs);
        if (elapsed > tuning.blinkMaxDuration.inMilliseconds) {
          // Too slow — treat as eyes-closed, not a blink. Restart.
          reset();
        } else if (open) {
          return DetectorUpdate.done;
        }
    }
    return _progress();
  }

  DetectorUpdate _progress() =>
      DetectorUpdate(progress: _stage / 3, completed: false);

  @override
  void reset() {
    _stage = 0;
    _closedAtMs = null;
  }
}

/// Smile held for [DetectorTuning.expressionHold]. With [fullTeeth], requires
/// a stronger smile and (when contours are available) an open mouth.
class SmileDetector extends ActionDetector {
  SmileDetector(super.tuning, {required this.fullTeeth});

  final bool fullTeeth;
  int? _startMs;

  @override
  LivenessAction get action =>
      fullTeeth ? LivenessAction.fullTeethSmile : LivenessAction.smile;

  @override
  DetectorUpdate update(FaceSnapshot face) {
    final smile = face.smileProbability;
    if (smile == null) return DetectorUpdate.none;

    bool satisfied;
    if (fullTeeth) {
      // Strong smile, plus a visible lip gap when contours are available.
      // Missing contours don't block completion (some devices/frames omit
      // them), they just make this equivalent to a strong smile.
      final mouth = face.mouthOpenRatio;
      satisfied = smile > tuning.fullTeethSmileThreshold &&
          (mouth == null || mouth > tuning.fullTeethMouthOpenRatio);
    } else {
      satisfied = smile > tuning.smileThreshold;
    }

    return _hold(satisfied, face.timestampMs, tuning.expressionHold);
  }

  DetectorUpdate _hold(bool satisfied, int nowMs, Duration hold) {
    if (!satisfied) {
      _startMs = null;
      return DetectorUpdate.none;
    }
    _startMs ??= nowMs;
    final elapsed = nowMs - _startMs!;
    if (elapsed >= hold.inMilliseconds) return DetectorUpdate.done;
    return DetectorUpdate(
      progress: elapsed / hold.inMilliseconds,
      completed: false,
    );
  }

  @override
  void reset() => _startMs = null;
}

/// Both eyes closed continuously for [DetectorTuning.eyesClosedHold].
///
/// ML Kit's eye-open probabilities jitter, so brief "open" flickers shorter
/// than [DetectorTuning.eyesOpenTolerance] (and frames with missing
/// probabilities) do not reset the hold timer.
class EyesClosedDetector extends ActionDetector {
  EyesClosedDetector(super.tuning);

  int? _closedStartMs;
  int? _openSinceMs;

  @override
  LivenessAction get action => LivenessAction.eyesClosed;

  @override
  DetectorUpdate update(FaceSnapshot face) {
    final left = face.leftEyeOpenProbability;
    final right = face.rightEyeOpenProbability;
    final now = face.timestampMs;
    final holdMs = tuning.eyesClosedHold.inMilliseconds;

    // Missing probabilities: keep current state, don't reset.
    if (left == null || right == null) return _progress(now, holdMs);

    // "Closed" is judged leniently here (below the open threshold) because
    // half-closed readings are common while eyes are actually shut.
    final closed = left < tuning.blinkOpenThreshold &&
        right < tuning.blinkOpenThreshold;

    if (closed) {
      // If eyes were open for longer than the tolerance, restart the hold.
      if (_openSinceMs != null &&
          now - _openSinceMs! > tuning.eyesOpenTolerance.inMilliseconds) {
        _closedStartMs = null;
      }
      _openSinceMs = null;
      _closedStartMs ??= now;
      if (now - _closedStartMs! >= holdMs) return DetectorUpdate.done;
    } else {
      _openSinceMs ??= now;
      if (now - _openSinceMs! > tuning.eyesOpenTolerance.inMilliseconds) {
        _closedStartMs = null;
      }
    }
    return _progress(now, holdMs);
  }

  DetectorUpdate _progress(int now, int holdMs) {
    final start = _closedStartMs;
    if (start == null) return DetectorUpdate.none;
    return DetectorUpdate(
      progress: ((now - start) / holdMs).clamp(0.0, 1.0),
      completed: false,
    );
  }

  @override
  void reset() {
    _closedStartMs = null;
    _openSinceMs = null;
  }
}

/// One nod cycle: neutral -> pitch down past threshold -> back to neutral.
class NodDetector extends ActionDetector {
  NodDetector(super.tuning);

  int _stage = 0; // 0 neutral, 1 down, 2 returned

  @override
  LivenessAction get action => LivenessAction.nod;

  @override
  DetectorUpdate update(FaceSnapshot face) {
    final pitch = face.headEulerAngleX;
    if (pitch == null) return DetectorUpdate.none;

    switch (_stage) {
      case 0:
        if (pitch.abs() < 8) _stage = 1;
      case 1:
        if (pitch < -tuning.nodPitchThreshold) _stage = 2;
      case 2:
        if (pitch > -4) return DetectorUpdate.done;
    }
    return DetectorUpdate(progress: _stage / 3, completed: false);
  }

  @override
  void reset() => _stage = 0;
}

/// Generic held-pose detector for look/tilt actions.
class HeadPoseDetector extends ActionDetector {
  HeadPoseDetector(super.tuning, {required this.action});

  @override
  final LivenessAction action;

  int? _startMs;

  double? _signal(FaceSnapshot f) {
    switch (action) {
      case LivenessAction.lookLeft:
        return f.headEulerAngleY;
      case LivenessAction.lookRight:
        final y = f.headEulerAngleY;
        return y == null ? null : -y;
      case LivenessAction.lookUp:
        return f.headEulerAngleX;
      case LivenessAction.lookDown:
        final x = f.headEulerAngleX;
        return x == null ? null : -x;
      case LivenessAction.tiltLeft:
        return f.headEulerAngleZ;
      case LivenessAction.tiltRight:
        final z = f.headEulerAngleZ;
        return z == null ? null : -z;
      default:
        return null;
    }
  }

  double get _threshold {
    switch (action) {
      case LivenessAction.lookLeft:
      case LivenessAction.lookRight:
        return tuning.yawThreshold;
      case LivenessAction.lookUp:
      case LivenessAction.lookDown:
        return tuning.pitchThreshold;
      default:
        return tuning.rollThreshold;
    }
  }

  @override
  DetectorUpdate update(FaceSnapshot face) {
    final value = _signal(face);
    if (value == null) return DetectorUpdate.none;

    if (value < _threshold) {
      _startMs = null;
      // Show partial progress as the head approaches the threshold.
      final approach = (value / _threshold).clamp(0.0, 1.0) * 0.5;
      return DetectorUpdate(progress: approach, completed: false);
    }
    _startMs ??= face.timestampMs;
    final elapsed = face.timestampMs - _startMs!;
    final holdMs = tuning.poseHold.inMilliseconds;
    if (elapsed >= holdMs) return DetectorUpdate.done;
    return DetectorUpdate(
      progress: 0.5 + 0.5 * (elapsed / holdMs),
      completed: false,
    );
  }

  @override
  void reset() => _startMs = null;
}

/// Mouth open (contour-based) held for [DetectorTuning.expressionHold].
class OpenMouthDetector extends ActionDetector {
  OpenMouthDetector(super.tuning);

  int? _startMs;

  @override
  LivenessAction get action => LivenessAction.openMouth;

  @override
  DetectorUpdate update(FaceSnapshot face) {
    final ratio = face.mouthOpenRatio;
    if (ratio == null) return DetectorUpdate.none;

    if (ratio < tuning.mouthOpenRatioThreshold) {
      _startMs = null;
      return DetectorUpdate(
        progress: (ratio / tuning.mouthOpenRatioThreshold).clamp(0.0, 1.0) * 0.5,
        completed: false,
      );
    }
    _startMs ??= face.timestampMs;
    final elapsed = face.timestampMs - _startMs!;
    final holdMs = tuning.expressionHold.inMilliseconds;
    if (elapsed >= holdMs) return DetectorUpdate.done;
    return DetectorUpdate(
      progress: 0.5 + 0.5 * (elapsed / holdMs),
      completed: false,
    );
  }

  @override
  void reset() => _startMs = null;
}

/// Experimental: trace a circle with the nose.
///
/// "Drawing a circle with your nose" is head rotation: yaw and pitch trace a
/// circle 90° out of phase. This detector accumulates the swept angle of the
/// (yaw, pitch) vector — robust across devices, unlike nose-vs-face-box
/// tracking (the box moves with the head, so that signal is ~zero).
/// Completes when the total sweep reaches
/// [DetectorTuning.circleMinSweepDegrees] within [DetectorTuning.circleWindow].
/// **One full circle** (≥ [DetectorTuning.circleMinSweepDegrees], default
/// 270°) in either direction is enough — clockwise and counter-clockwise
/// progress are tracked separately so wobble in the opposite direction never
/// subtracts from progress.
class CircleNoseDetector extends ActionDetector {
  CircleNoseDetector(super.tuning);

  double? _lastAngle;
  double _cwSweep = 0;
  double _ccwSweep = 0;
  int? _windowStartMs;

  @override
  LivenessAction get action => LivenessAction.drawCircleWithNose;

  @override
  DetectorUpdate update(FaceSnapshot face) {
    final yaw = face.headEulerAngleY;
    final pitch = face.headEulerAngleX;
    if (yaw == null || pitch == null) return _progress();

    final magnitude = math.sqrt(yaw * yaw + pitch * pitch);
    if (magnitude < tuning.circleMinRadius) {
      // Head too close to straight-ahead: no rotation signal this frame.
      _lastAngle = null;
      return _progress();
    }

    final angle = math.atan2(pitch, yaw) * 180 / math.pi;
    _windowStartMs ??= face.timestampMs;

    if (face.timestampMs - _windowStartMs! >
        tuning.circleWindow.inMilliseconds) {
      reset();
      _windowStartMs = face.timestampMs;
      return _progress();
    }

    if (_lastAngle != null) {
      var delta = angle - _lastAngle!;
      if (delta > 180) delta -= 360;
      if (delta < -180) delta += 360;
      // Ignore implausible jumps (tracking glitches).
      if (delta.abs() < 60) {
        if (delta > 0) {
          _cwSweep += delta;
        } else {
          _ccwSweep -= delta;
        }
      }
    }
    _lastAngle = angle;

    if (math.max(_cwSweep, _ccwSweep) >= tuning.circleMinSweepDegrees) {
      return DetectorUpdate.done;
    }
    return _progress();
  }

  DetectorUpdate _progress() => DetectorUpdate(
        progress: (math.max(_cwSweep, _ccwSweep) /
                tuning.circleMinSweepDegrees)
            .clamp(0.0, 1.0),
        completed: false,
      );

  @override
  void reset() {
    _lastAngle = null;
    _cwSweep = 0;
    _ccwSweep = 0;
    _windowStartMs = null;
  }
}
