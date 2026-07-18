import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

FaceSnapshot neutral(int t) => FaceSnapshot(
      timestampMs: t,
      smileProbability: 0.05,
      leftEyeOpenProbability: 0.95,
      rightEyeOpenProbability: 0.95,
      headEulerAngleX: 0,
      headEulerAngleY: 0,
      headEulerAngleZ: 0,
      boundingBox: const Rect.fromLTWH(0.3, 0.3, 0.4, 0.4),
    );

FaceSnapshot smiling(int t) => FaceSnapshot(
      timestampMs: t,
      smileProbability: 0.95,
      leftEyeOpenProbability: 0.95,
      rightEyeOpenProbability: 0.95,
      headEulerAngleX: 0,
      headEulerAngleY: 0,
      headEulerAngleZ: 0,
      boundingBox: const Rect.fromLTWH(0.3, 0.3, 0.4, 0.4),
    );

void main() {
  test('completes a smile-only session and emits events in order', () {
    final session = LivenessSession(
      const LivenessConfig(actions: [LivenessAction.smile]),
    );
    final events = <Type>[];
    session.addEventListener((e) => events.add(e.runtimeType));

    session.start();
    session.onFrame(faces: [neutral(0)], faceInPosition: true, timestampMs: 0);
    expect(session.current.phase, LivenessPhase.performingAction);

    session.onFrame(
        faces: [smiling(100)], faceInPosition: true, timestampMs: 100);
    session.onFrame(
        faces: [smiling(700)], faceInPosition: true, timestampMs: 700);

    expect(session.current.phase, LivenessPhase.completed);
    expect(events, [
      ReferenceReadyEvent,
      ActionStartedEvent,
      ActionCompletedEvent,
      SessionCompletedEvent,
    ]);
  });

  test('requires neutral between actions', () {
    final session = LivenessSession(
      const LivenessConfig(
        actions: [LivenessAction.smile, LivenessAction.blink],
      ),
    );
    session.start();
    session.onFrame(faces: [neutral(0)], faceInPosition: true, timestampMs: 0);
    session.onFrame(
        faces: [smiling(100)], faceInPosition: true, timestampMs: 100);
    session.onFrame(
        faces: [smiling(700)], faceInPosition: true, timestampMs: 700);

    expect(session.current.phase, LivenessPhase.awaitingNeutral);

    // Still smiling: must not advance.
    session.onFrame(
        faces: [smiling(800)], faceInPosition: true, timestampMs: 800);
    expect(session.current.phase, LivenessPhase.awaitingNeutral);

    session.onFrame(
        faces: [neutral(900)], faceInPosition: true, timestampMs: 900);
    expect(session.current.phase, LivenessPhase.performingAction);
    expect(session.current.currentAction, LivenessAction.blink);
  });

  test('fails on action timeout', () {
    final session = LivenessSession(
      const LivenessConfig(
        actions: [LivenessAction.smile],
        actionTimeout: Duration(seconds: 5),
      ),
    );
    session.start();
    session.onFrame(faces: [neutral(0)], faceInPosition: true, timestampMs: 0);
    session.onFrame(
        faces: [neutral(6000)], faceInPosition: true, timestampMs: 6000);

    expect(session.current.phase, LivenessPhase.failed);
    expect(
        session.current.failureReason, LivenessFailureReason.actionTimeout);
  });

  test('fails on multiple faces', () {
    final session = LivenessSession(
      const LivenessConfig(actions: [LivenessAction.smile]),
    );
    session.start();
    session.onFrame(
      faces: [neutral(0), neutral(0)],
      faceInPosition: true,
      timestampMs: 0,
    );
    expect(session.current.phase, LivenessPhase.failed);
    expect(
        session.current.failureReason, LivenessFailureReason.multipleFaces);
  });

  test('fails when face lost beyond grace period during action', () {
    final session = LivenessSession(
      const LivenessConfig(
        actions: [LivenessAction.smile],
        faceLostGrace: Duration(milliseconds: 500),
      ),
    );
    session.start();
    session.onFrame(faces: [neutral(0)], faceInPosition: true, timestampMs: 0);
    expect(session.current.phase, LivenessPhase.performingAction);

    session.onFrame(faces: [], faceInPosition: false, timestampMs: 100);
    expect(session.current.phase, LivenessPhase.performingAction);

    session.onFrame(faces: [], faceInPosition: false, timestampMs: 700);
    expect(session.current.phase, LivenessPhase.failed);
    expect(session.current.failureReason, LivenessFailureReason.faceLost);
  });

  test('shuffleActions randomizes execution order but keeps all actions', () {
    const actions = [
      LivenessAction.blink,
      LivenessAction.smile,
      LivenessAction.nod,
      LivenessAction.lookLeft,
      LivenessAction.lookRight,
    ];
    final session = LivenessSession(
      const LivenessConfig(actions: actions, shuffleActions: true),
      random: Random(42), // deterministic for the test
    );
    expect(session.actionOrder.toSet(), actions.toSet());
    expect(session.actionOrder.length, actions.length);

    // Without shuffle, order is preserved.
    final plain = LivenessSession(const LivenessConfig(actions: actions));
    expect(plain.actionOrder, actions);
  });

  test('cancel produces cancelled failure', () {
    final session = LivenessSession(
      const LivenessConfig(actions: [LivenessAction.smile]),
    );
    session.start();
    session.cancel();
    expect(session.current.phase, LivenessPhase.failed);
    expect(session.current.failureReason, LivenessFailureReason.cancelled);
  });
}
