import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

FaceSnapshot f(int t, {double smile = 0.05}) => FaceSnapshot(
      timestampMs: t,
      smileProbability: smile,
      leftEyeOpenProbability: 0.95,
      rightEyeOpenProbability: 0.95,
      headEulerAngleX: 0,
      headEulerAngleY: 0,
      headEulerAngleZ: 0,
      boundingBox: const Rect.fromLTWH(0.3, 0.3, 0.4, 0.4),
    );

void main() {
  group('B7 LivenessSessionState', () {
    test('copyWith clear flags null the field; null args keep it', () {
      const s = LivenessSessionState(
        phase: LivenessPhase.failed,
        totalActions: 2,
        currentAction: LivenessAction.blink,
        failureReason: LivenessFailureReason.faceLost,
        remaining: Duration(seconds: 3),
      );
      final kept = s.copyWith();
      expect(kept.currentAction, LivenessAction.blink);
      expect(kept.failureReason, LivenessFailureReason.faceLost);
      expect(kept.remaining, const Duration(seconds: 3));

      final cleared = s.copyWith(
        clearCurrentAction: true,
        clearFailureReason: true,
        clearRemaining: true,
      );
      expect(cleared.currentAction, isNull);
      expect(cleared.failureReason, isNull);
      expect(cleared.remaining, isNull);
    });

    test('remaining is null in awaitingNeutral', () {
      final session = LivenessSession(
        const LivenessConfig(
          actions: [LivenessAction.smile, LivenessAction.blink],
        ),
      )..start();
      session.onFrame(faces: [f(0)], faceInPosition: true, timestampMs: 0);
      session.onFrame(
          faces: [f(100, smile: 0.9)], faceInPosition: true, timestampMs: 100);
      expect(session.current.remaining, isNotNull);
      session.onFrame(
          faces: [f(700, smile: 0.9)], faceInPosition: true, timestampMs: 700);
      expect(session.current.phase, LivenessPhase.awaitingNeutral);
      expect(session.current.remaining, isNull);

      session.onFrame(faces: [f(800)], faceInPosition: true, timestampMs: 800);
      expect(session.current.phase, LivenessPhase.performingAction);
      expect(session.current.remaining, isNotNull);
    });

    test('remaining is null once completed or failed', () {
      final session = LivenessSession(
        const LivenessConfig(actions: [LivenessAction.smile]),
      )..start();
      session.onFrame(faces: [f(0)], faceInPosition: true, timestampMs: 0);
      session.onFrame(
          faces: [f(100, smile: 0.9)], faceInPosition: true, timestampMs: 100);
      session.cancel();
      expect(session.current.phase, LivenessPhase.failed);
      expect(session.current.remaining, isNull);
    });
  });

  group('C2 builder information', () {
    test('actionPlan equals actionOrder from the first state onward', () {
      final session = LivenessSession(
        const LivenessConfig(
          actions: [
            LivenessAction.smile,
            LivenessAction.blink,
            LivenessAction.nod,
            LivenessAction.lookLeft,
          ],
          shuffleActions: true,
        ),
        random: Random(7),
      );
      final seen = <LivenessSessionState>[session.current];
      session.state.addListener(() => seen.add(session.current));
      session.start();
      session.onFrame(faces: [f(0)], faceInPosition: true, timestampMs: 0);
      session.cancel();

      expect(seen.length, greaterThan(2));
      for (final state in seen) {
        expect(state.actionPlan, session.actionOrder);
        expect(state.totalActions, 4);
      }
    });

    test('actionTimeout mirrors the config', () {
      final session = LivenessSession(const LivenessConfig(
        actions: [LivenessAction.smile],
        actionTimeout: Duration(seconds: 9),
      ));
      expect(session.current.actionTimeout, const Duration(seconds: 9));
    });

    test('sessionRemaining counts down from sessionTimeout', () {
      final session = LivenessSession(const LivenessConfig(
        actions: [LivenessAction.smile],
        sessionTimeout: Duration(seconds: 60),
      ))
        ..start();
      expect(session.current.sessionRemaining, isNull);
      session.onFrame(faces: const [], faceInPosition: false, timestampMs: 1000);
      expect(session.current.sessionRemaining, const Duration(seconds: 60));
      session.tick(11000);
      expect(session.current.sessionRemaining, const Duration(seconds: 50));
    });

    test('sessionRemaining stays null when sessionTimeout is null', () {
      final session = LivenessSession(const LivenessConfig(
        actions: [LivenessAction.smile],
        sessionTimeout: null,
      ))
        ..start();
      session.onFrame(faces: const [], faceInPosition: false, timestampMs: 0);
      session.tick(5000);
      expect(session.current.sessionRemaining, isNull);
    });

    test('tick() keeps the action countdown moving without frames', () {
      final session = LivenessSession(const LivenessConfig(
        actions: [LivenessAction.smile],
        actionTimeout: Duration(seconds: 10),
      ))
        ..start();
      session.onFrame(faces: [f(0)], faceInPosition: true, timestampMs: 0);
      session.tick(4000);
      expect(session.current.remaining, const Duration(seconds: 6));
    });

    test('a failed state carries its failureReason', () {
      final session = LivenessSession(const LivenessConfig(
        actions: [LivenessAction.smile],
        actionTimeout: Duration(seconds: 1),
      ))
        ..start();
      session.onFrame(faces: [f(0)], faceInPosition: true, timestampMs: 0);
      session.tick(1500);
      expect(session.current.phase, LivenessPhase.failed);
      expect(session.current.failureReason, LivenessFailureReason.actionTimeout);
    });
  });
}
