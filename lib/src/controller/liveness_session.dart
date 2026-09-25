import 'dart:math';

import 'package:flutter/foundation.dart';

import '../detection/action_detectors.dart';
import '../models/models.dart';

/// Events emitted by [LivenessSession] that the host (UI layer) reacts to,
/// e.g. capturing an image when an action completes.
sealed class LivenessEvent {
  const LivenessEvent();
}

/// Emitted once when the face is first correctly positioned (used for the
/// neutral reference image).
class ReferenceReadyEvent extends LivenessEvent {
  const ReferenceReadyEvent();
}

class ActionStartedEvent extends LivenessEvent {
  const ActionStartedEvent(this.action, this.index);
  final LivenessAction action;
  final int index;
}

/// The detector reported [DetectorUpdate.isPeak]: this frame best shows
/// [action]. May fire several times per action; the latest one wins.
class ActionPeakEvent extends LivenessEvent {
  const ActionPeakEvent(this.action, this.index, this.timestampMs);
  final LivenessAction action;
  final int index;
  final int timestampMs;
}

class ActionCompletedEvent extends LivenessEvent {
  const ActionCompletedEvent(this.action, this.index);
  final LivenessAction action;
  final int index;
}

class SessionCompletedEvent extends LivenessEvent {
  const SessionCompletedEvent();
}

class SessionFailedEvent extends LivenessEvent {
  const SessionFailedEvent(this.reason);
  final LivenessFailureReason reason;
}

/// Pure-Dart session state machine. Feed it face observations per frame via
/// [onFrame]; listen to [state] for UI and [events] for side effects.
///
/// Platform-independent and unit-testable.
class LivenessSession {
  /// Throws an [ArgumentError] if [config] is invalid (see
  /// [LivenessConfig.validate]).
  ///
  /// The shuffle uses [Random.secure] unless [random] is given (tests), so
  /// the order can't be predicted from a seeded PRNG.
  ///
  /// With a [LivenessConfig.challenge], its actions run in its order and
  /// [now] (default `DateTime.now`) is used to refuse an expired one.
  LivenessSession(this.config, {Random? random, DateTime Function()? now})
      : _now = now ?? DateTime.now,
        _actions = _plan(config, random ?? Random.secure()) {
    config.validate();
    _state = ValueNotifier(
      LivenessSessionState(
        phase: LivenessPhase.initializing,
        totalActions: _actions.length,
        actionPlan: actionOrder,
        actionTimeout: config.actionTimeout,
      ),
    );
  }

  final LivenessConfig config;
  final DateTime Function() _now;

  /// Challenge order if any; else a random pick of `randomActionCount`
  /// from the pool; else the list, shuffled if asked.
  static List<LivenessAction> _plan(LivenessConfig config, Random random) {
    final challenge = config.challenge;
    if (challenge != null) return List.of(challenge.actions);
    final count = config.randomActionCount;
    if (count != null) {
      // Validation happens in the constructor body; clamp so a bad count
      // reaches validate() instead of throwing a RangeError here.
      final pool = List.of(config.actions)..shuffle(random);
      return pool.take(count.clamp(0, pool.length)).toList();
    }
    return config.shuffleActions
        ? (List.of(config.actions)..shuffle(random))
        : List.of(config.actions);
  }

  bool get _challengeExpired =>
      config.challenge?.isExpiredAt(_now()) ?? false;

  /// The order actions will actually run in (shuffled once per session when
  /// `config.shuffleActions` is true).
  final List<LivenessAction> _actions;
  List<LivenessAction> get actionOrder => List.unmodifiable(_actions);

  late final ValueNotifier<LivenessSessionState> _state;
  ValueListenable<LivenessSessionState> get state => _state;
  LivenessSessionState get current => _state.value;

  final List<void Function(LivenessEvent)> _listeners = [];
  void addEventListener(void Function(LivenessEvent) listener) =>
      _listeners.add(listener);

  ActionDetector? _detector;
  int _actionIndex = 0;
  int? _actionStartMs;
  int? _sessionStartMs;
  int? _lastSeenMs;
  int? _neutralStartMs;
  int? _faceLostSinceMs;
  int? _multipleFacesSinceMs;

  /// When the detector stopped being fed (face briefly lost, a second face,
  /// or a bad-quality frame). Its state is kept; see [_resumeDetector].
  int? _pausedSinceMs;
  bool _referenceEmitted = false;
  final List<LivenessAction> _completed = [];
  final Map<String, Object?> _metadata = {};

  Map<String, Object?> get metadata => Map.unmodifiable(_metadata);

  bool get isTerminal =>
      current.phase == LivenessPhase.completed ||
      current.phase == LivenessPhase.failed;

  /// Call once the camera + detector pipeline is delivering frames.
  void start() {
    if (_challengeExpired) {
      _fail(LivenessFailureReason.challengeExpired);
      return;
    }
    _emitState(current.copyWith(phase: LivenessPhase.searchingFace));
  }

  void cancel() {
    if (isTerminal) return;
    _fail(LivenessFailureReason.cancelled);
  }

  void systemError() {
    if (isTerminal) return;
    _fail(LivenessFailureReason.systemError);
  }

  /// The faces that matter, primary first: sorted by bounding-box area
  /// (largest first), with secondary faces smaller than
  /// [minAreaRatio] × the primary's area dropped.
  static List<FaceSnapshot> relevantFaces(
    List<FaceSnapshot> faces, {
    double minAreaRatio = 0.35,
  }) {
    if (faces.length < 2) return faces;
    final sorted = List.of(faces)..sort((a, b) => b.area.compareTo(a.area));
    final minArea = sorted.first.area * minAreaRatio;
    return [
      sorted.first,
      ...sorted.skip(1).where((f) => f.area >= minArea),
    ];
  }

  /// Advance timers without a frame. Call periodically (the widget does,
  /// every 250 ms) so timeouts still fire when the camera stalls and no
  /// frames arrive. [timestampMs] must use the same clock as [onFrame].
  void tick(int timestampMs) {
    if (isTerminal || current.phase == LivenessPhase.initializing) return;
    if (_checkTimeouts(timestampMs)) return;
    // Keep the countdowns moving even when frames stall.
    final start = _actionStartMs;
    _emitState(current.copyWith(
      remaining: current.phase == LivenessPhase.performingAction &&
              start != null
          ? Duration(
              milliseconds: config.actionTimeout.inMilliseconds -
                  (timestampMs - start),
            )
          : null,
    ));
  }

  /// Fails the session if any timeout has expired. Returns true if it did.
  bool _checkTimeouts(int nowMs) {
    final sessionStart = _sessionStartMs ??= nowMs;
    _lastSeenMs = nowMs;
    final sessionTimeout = config.sessionTimeout;
    if (sessionTimeout != null &&
        nowMs - sessionStart > sessionTimeout.inMilliseconds) {
      _fail(LivenessFailureReason.sessionTimeout);
      return true;
    }
    switch (current.phase) {
      case LivenessPhase.performingAction:
        final start = _actionStartMs;
        if (start != null &&
            nowMs - start > config.actionTimeout.inMilliseconds) {
          _fail(LivenessFailureReason.actionTimeout);
          return true;
        }
      case LivenessPhase.awaitingNeutral:
        final start = _neutralStartMs;
        if (start != null &&
            nowMs - start > config.neutralTimeout.inMilliseconds) {
          _metadata['timeoutPhase'] = LivenessPhase.awaitingNeutral.name;
          _fail(LivenessFailureReason.actionTimeout);
          return true;
        }
      default:
        break;
    }
    return false;
  }

  /// Feed one frame's worth of detection output.
  ///
  /// [faces] — all faces detected this frame (normalized snapshots). The
  /// largest is the primary face; see [relevantFaces].
  /// [faceInPosition] — whether the primary face is inside the target oval
  /// (computed by the UI layer, which knows the oval geometry).
  /// [guidance] — what to tell the user right now (surfaced in state).
  /// [qualityHold] — frame is unusable (too dark/blurry): pause without
  /// counting toward face-lost failure.
  /// [spoofSuspected] — replay guard tripped: fail immediately.
  /// [faceChanged] — identity guard saw a face swap: fail immediately.
  void onFrame({
    required List<FaceSnapshot> faces,
    required bool faceInPosition,
    required int timestampMs,
    FaceGuidance guidance = FaceGuidance.none,
    bool qualityHold = false,
    bool spoofSuspected = false,
    bool faceChanged = false,
  }) {
    if (isTerminal || current.phase == LivenessPhase.initializing) return;

    if (spoofSuspected) {
      _fail(LivenessFailureReason.spoofSuspected);
      return;
    }
    if (faceChanged) {
      _fail(LivenessFailureReason.faceChanged);
      return;
    }

    if (_checkTimeouts(timestampMs)) return;

    final relevant = relevantFaces(
      faces,
      minAreaRatio: config.tuning.secondaryFaceMinAreaRatio,
    );
    if (relevant.length > 1 && config.failOnMultipleFaces) {
      final since = _multipleFacesSinceMs ??= timestampMs;
      if (timestampMs - since > config.multipleFacesGrace.inMilliseconds) {
        _fail(LivenessFailureReason.multipleFaces);
        return;
      }
      // Within grace: pause in place, as for a brief face dropout.
      _pausedSinceMs ??= timestampMs;
      _emitState(current.copyWith(
        faceInPosition: false,
        guidance: FaceGuidance.multipleFaces,
      ));
      return;
    }
    _multipleFacesSinceMs = null;

    final face = relevant.isEmpty ? null : relevant.first;

    // Unusable frame (dark/blurry): freeze in place. Doesn't accumulate
    // toward face-lost — a dim room shouldn't fail the session straight
    // away, the user just needs to fix the light. The action and session
    // timeouts above still run.
    if (qualityHold) {
      _faceLostSinceMs = null;
      _pausedSinceMs ??= timestampMs;
      _emitState(current.copyWith(guidance: guidance));
      return;
    }

    // Face-lost handling with grace period.
    if (face == null || !faceInPosition) {
      _faceLostSinceMs ??= timestampMs;
      final lostFor = timestampMs - _faceLostSinceMs!;
      if (current.phase == LivenessPhase.performingAction ||
          current.phase == LivenessPhase.awaitingNeutral) {
        if (lostFor > config.faceLostGrace.inMilliseconds) {
          _fail(LivenessFailureReason.faceLost);
          return;
        }
        // Within grace: stop feeding the detector but keep its state, so a
        // one-frame ML Kit miss doesn't restart a hold.
        _pausedSinceMs ??= timestampMs;
        _emitState(current.copyWith(faceInPosition: false, guidance: guidance));
        return;
      }
      _emitState(current.copyWith(
        phase: face == null
            ? LivenessPhase.searchingFace
            : LivenessPhase.centeringFace,
        faceInPosition: false,
        guidance: guidance,
      ));
      return;
    }
    _faceLostSinceMs = null;
    if (current.guidance != FaceGuidance.none) {
      _emitState(current.copyWith(guidance: FaceGuidance.none));
    }

    switch (current.phase) {
      case LivenessPhase.searchingFace:
      case LivenessPhase.centeringFace:
        if (!_referenceEmitted) {
          _referenceEmitted = true;
          _emitEvent(const ReferenceReadyEvent());
        }
        _beginAction(timestampMs);

      case LivenessPhase.awaitingNeutral:
        if (!config.requireNeutralBetweenActions || face.isNeutral) {
          _beginAction(timestampMs);
        } else {
          _emitState(current.copyWith(faceInPosition: true));
        }

      case LivenessPhase.performingAction:
        _resumeDetector(timestampMs);
        _runDetector(face, timestampMs);

      default:
        break;
    }
  }

  void _beginAction(int timestampMs) {
    _pausedSinceMs = null;
    final action = _actions[_actionIndex];
    _detector = ActionDetector.forAction(action, config.tuning);
    _actionStartMs = timestampMs;
    _emitState(current.copyWith(
      phase: LivenessPhase.performingAction,
      currentAction: action,
      currentActionIndex: _actionIndex,
      actionProgress: 0,
      faceInPosition: true,
      remaining: config.actionTimeout,
    ));
    _emitEvent(ActionStartedEvent(action, _actionIndex));
  }

  /// Ends a pause. Short pauses (up to [LivenessConfig.faceLostGrace]) keep
  /// the detector's progress; longer ones (only possible via a quality
  /// hold, since a longer face loss fails the session) restart the action,
  /// because hold timers would otherwise count the unseen gap as held.
  void _resumeDetector(int timestampMs) {
    final pausedSince = _pausedSinceMs;
    if (pausedSince == null) return;
    _pausedSinceMs = null;
    if (timestampMs - pausedSince > config.faceLostGrace.inMilliseconds) {
      _detector?.reset();
    }
  }

  void _runDetector(FaceSnapshot face, int timestampMs) {
    final detector = _detector;
    final startMs = _actionStartMs;
    if (detector == null || startMs == null) return;

    final elapsed = timestampMs - startMs;
    final timeoutMs = config.actionTimeout.inMilliseconds;

    final update = detector.update(face);
    if (update.isPeak) {
      _emitEvent(ActionPeakEvent(detector.action, _actionIndex, timestampMs));
    }
    if (update.completed) {
      final action = detector.action;
      _completed.add(action);
      _metadata['${action.name}_ms'] = elapsed;
      _emitEvent(ActionCompletedEvent(action, _actionIndex));
      _actionIndex++;
      _detector = null;

      if (_actionIndex >= _actions.length) {
        if (_challengeExpired) {
          _fail(LivenessFailureReason.challengeExpired);
          return;
        }
        _emitState(current.copyWith(
          phase: LivenessPhase.completed,
          completedActions: List.of(_completed),
          actionProgress: 1,
          faceInPosition: true,
        ));
        _emitEvent(const SessionCompletedEvent());
      } else {
        _neutralStartMs = timestampMs;
        _emitState(current.copyWith(
          phase: LivenessPhase.awaitingNeutral,
          completedActions: List.of(_completed),
          actionProgress: 0,
          faceInPosition: true,
        ));
      }
      return;
    }

    _emitState(current.copyWith(
      actionProgress: update.progress,
      faceInPosition: true,
      remaining: Duration(milliseconds: timeoutMs - elapsed),
    ));
  }

  void _fail(LivenessFailureReason reason) {
    _emitState(current.copyWith(
      phase: LivenessPhase.failed,
      failureReason: reason,
      completedActions: List.of(_completed),
    ));
    _emitEvent(SessionFailedEvent(reason));
  }

  void _emitState(LivenessSessionState next) {
    // `remaining` is the action countdown; it is meaningless elsewhere.
    if (next.phase != LivenessPhase.performingAction && next.remaining != null) {
      next = next.copyWith(clearRemaining: true);
    }
    final timeout = config.sessionTimeout;
    final start = _sessionStartMs;
    final now = _lastSeenMs;
    if (timeout != null && start != null && now != null) {
      final left = timeout.inMilliseconds - (now - start);
      next = next.copyWith(
        sessionRemaining: Duration(milliseconds: left < 0 ? 0 : left),
      );
    }
    _state.value = next;
  }

  void _emitEvent(LivenessEvent event) {
    for (final l in List.of(_listeners)) {
      l(event);
    }
  }

  void dispose() {
    _listeners.clear();
    _state.dispose();
  }
}
