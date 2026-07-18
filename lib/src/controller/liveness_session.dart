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
  LivenessSession(this.config, {Random? random})
      : _actions = config.shuffleActions
            ? (List.of(config.actions)..shuffle(random ?? Random()))
            : List.of(config.actions),
        _state = ValueNotifier(
          LivenessSessionState(
            phase: LivenessPhase.initializing,
            totalActions: config.actions.length,
          ),
        );

  final LivenessConfig config;

  /// The order actions will actually run in (shuffled once per session when
  /// `config.shuffleActions` is true).
  final List<LivenessAction> _actions;
  List<LivenessAction> get actionOrder => List.unmodifiable(_actions);

  final ValueNotifier<LivenessSessionState> _state;
  ValueListenable<LivenessSessionState> get state => _state;
  LivenessSessionState get current => _state.value;

  final List<void Function(LivenessEvent)> _listeners = [];
  void addEventListener(void Function(LivenessEvent) listener) =>
      _listeners.add(listener);

  ActionDetector? _detector;
  int _actionIndex = 0;
  int? _actionStartMs;
  int? _faceLostSinceMs;
  bool _referenceEmitted = false;
  final List<LivenessAction> _completed = [];
  final Map<String, Object?> _metadata = {};

  Map<String, Object?> get metadata => Map.unmodifiable(_metadata);

  bool get isTerminal =>
      current.phase == LivenessPhase.completed ||
      current.phase == LivenessPhase.failed;

  /// Call once the camera + detector pipeline is delivering frames.
  void start() {
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

  /// Feed one frame's worth of detection output.
  ///
  /// [faces] — all faces detected this frame (normalized snapshots).
  /// [faceInPosition] — whether the primary face is inside the target oval
  /// (computed by the UI layer, which knows the oval geometry).
  /// [guidance] — what to tell the user right now (surfaced in state).
  /// [qualityHold] — frame is unusable (too dark/blurry): pause without
  /// counting toward face-lost failure.
  /// [spoofSuspected] — replay guard tripped: fail immediately.
  void onFrame({
    required List<FaceSnapshot> faces,
    required bool faceInPosition,
    required int timestampMs,
    FaceGuidance guidance = FaceGuidance.none,
    bool qualityHold = false,
    bool spoofSuspected = false,
  }) {
    if (isTerminal || current.phase == LivenessPhase.initializing) return;

    if (spoofSuspected) {
      _fail(LivenessFailureReason.spoofSuspected);
      return;
    }

    if (faces.length > 1 && config.failOnMultipleFaces) {
      _fail(LivenessFailureReason.multipleFaces);
      return;
    }

    final face = faces.isEmpty ? null : faces.first;

    // Unusable frame (dark/blurry): freeze in place. Doesn't accumulate
    // toward face-lost — a dim room shouldn't fail the session, the user
    // just needs to fix the light.
    if (qualityHold) {
      _faceLostSinceMs = null;
      _detector?.reset();
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
        // Within grace: freeze, but pause detector state.
        _detector?.reset();
        _emitState(
            current.copyWith(faceInPosition: false, guidance: guidance));
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
        _runDetector(face, timestampMs);

      default:
        break;
    }
  }

  void _beginAction(int timestampMs) {
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

  void _runDetector(FaceSnapshot face, int timestampMs) {
    final detector = _detector;
    final startMs = _actionStartMs;
    if (detector == null || startMs == null) return;

    final elapsed = timestampMs - startMs;
    final timeoutMs = config.actionTimeout.inMilliseconds;
    if (elapsed > timeoutMs) {
      _fail(LivenessFailureReason.actionTimeout);
      return;
    }

    final update = detector.update(face);
    if (update.completed) {
      final action = detector.action;
      _completed.add(action);
      _metadata['${action.name}_ms'] = elapsed;
      _emitEvent(ActionCompletedEvent(action, _actionIndex));
      _actionIndex++;
      _detector = null;

      if (_actionIndex >= _actions.length) {
        _emitState(current.copyWith(
          phase: LivenessPhase.completed,
          completedActions: List.of(_completed),
          actionProgress: 1,
          faceInPosition: true,
        ));
        _emitEvent(const SessionCompletedEvent());
      } else {
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

  void _emitState(LivenessSessionState next) => _state.value = next;

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
