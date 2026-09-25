import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';
import 'package:liveness_flutter/src/ui/liveness_overlay.dart';

Future<void> pumpPanel(
  WidgetTester tester,
  LivenessSessionState state, {
  LivenessTheme theme = const LivenessTheme(),
}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DefaultInstructionPanel(state: state, theme: theme),
      ),
    ));

void main() {
  group('C4 hints under the instruction', () {
    testWidgets('guidance shows below the instruction in hintStyle',
        (tester) async {
      const hintStyle = TextStyle(fontSize: 11, color: Colors.amber);
      await pumpPanel(
        tester,
        const LivenessSessionState(
          phase: LivenessPhase.performingAction,
          totalActions: 2,
          currentAction: LivenessAction.smile,
          guidance: FaceGuidance.tooFar,
        ),
        theme: const LivenessTheme(hintStyle: hintStyle),
      );
      expect(find.text('Smile'), findsOneWidget);
      final hint = tester.widget<Text>(find.text('Move closer'));
      expect(hint.style, hintStyle);
      // The hint sits under the instruction.
      expect(tester.getTopLeft(find.text('Move closer')).dy,
          greaterThan(tester.getTopLeft(find.text('Smile')).dy));
    });

    testWidgets('no hint when there is no guidance', (tester) async {
      await pumpPanel(
        tester,
        const LivenessSessionState(
          phase: LivenessPhase.performingAction,
          totalActions: 1,
          currentAction: LivenessAction.blink,
        ),
      );
      expect(find.byKey(const ValueKey('liveness-hint')), findsNothing);
    });

    testWidgets('a hint identical to the instruction is not repeated',
        (tester) async {
      await pumpPanel(
        tester,
        const LivenessSessionState(
          phase: LivenessPhase.searchingFace,
          totalActions: 1,
          guidance: FaceGuidance.noFace,
        ),
      );
      expect(find.text('Position your face in the oval'), findsOneWidget);
      expect(find.byKey(const ValueKey('liveness-hint')), findsNothing);
    });

    testWidgets('LivenessStrings.multipleFaces is used for the hint',
        (tester) async {
      await pumpPanel(
        tester,
        const LivenessSessionState(
          phase: LivenessPhase.centeringFace,
          totalActions: 1,
          guidance: FaceGuidance.multipleFaces,
        ),
        theme: const LivenessTheme(
          strings: LivenessStrings(multipleFaces: 'Just you, please'),
        ),
      );
      expect(find.text('Just you, please'), findsOneWidget);
    });
  });

  group('C5 localisation', () {
    testWidgets('step counter is localisable', (tester) async {
      await pumpPanel(
        tester,
        const LivenessSessionState(
          phase: LivenessPhase.performingAction,
          totalActions: 3,
          currentActionIndex: 1,
          currentAction: LivenessAction.blink,
        ),
        theme: LivenessTheme(
          strings: LivenessStrings(stepCounter: (c, t) => 'Étape $c sur $t'),
        ),
      );
      expect(find.text('Étape 2 sur 3'), findsOneWidget);
      expect(find.textContaining('Step'), findsNothing);
    });

    testWidgets('default step counter', (tester) async {
      await pumpPanel(
        tester,
        const LivenessSessionState(
          phase: LivenessPhase.performingAction,
          totalActions: 4,
          currentAction: LivenessAction.nod,
        ),
      );
      expect(find.text('Step 1 of 4'), findsOneWidget);
    });

    for (final reason in LivenessFailureReason.values) {
      testWidgets('failure text for ${reason.name}', (tester) async {
        await pumpPanel(
          tester,
          LivenessSessionState(
            phase: LivenessPhase.failed,
            totalActions: 1,
            failureReason: reason,
          ),
        );
        final expected = LivenessStrings.defaultFailureMessages[reason]!;
        expect(find.text(expected), findsOneWidget);
        expect(find.text('Verification failed'), findsNothing);
      });
    }

    testWidgets('failure text can be overridden per reason', (tester) async {
      await pumpPanel(
        tester,
        const LivenessSessionState(
          phase: LivenessPhase.failed,
          totalActions: 1,
          failureReason: LivenessFailureReason.faceLost,
        ),
        theme: const LivenessTheme(
          strings: LivenessStrings(failureMessages: {
            LivenessFailureReason.faceLost: 'Visage perdu',
          }),
        ),
      );
      expect(find.text('Visage perdu'), findsOneWidget);
    });

    testWidgets('failed without a reason falls back to `failed`',
        (tester) async {
      await pumpPanel(
        tester,
        const LivenessSessionState(phase: LivenessPhase.failed, totalActions: 1),
      );
      expect(find.text('Verification failed'), findsOneWidget);
    });

    testWidgets('a partial actionInstructions map keeps the other defaults',
        (tester) async {
      const strings = LivenessStrings(
        actionInstructions: {LivenessAction.blink: 'Clignez des yeux'},
      );
      await pumpPanel(
        tester,
        const LivenessSessionState(
          phase: LivenessPhase.performingAction,
          totalActions: 2,
          currentAction: LivenessAction.lookLeft,
        ),
        theme: const LivenessTheme(strings: strings),
      );
      expect(find.text('Turn your head to the left'), findsOneWidget);
      expect(find.text('lookLeft'), findsNothing);
      expect(strings.instructionFor(LivenessAction.blink), 'Clignez des yeux');
      expect(strings.actionInstructions.length, LivenessAction.values.length);
    });

    test('a partial guidanceMessages map keeps the other defaults', () {
      const strings = LivenessStrings(
        guidanceMessages: {FaceGuidance.tooFar: 'Rapprochez-vous'},
      );
      expect(strings.guidanceFor(FaceGuidance.tooFar), 'Rapprochez-vous');
      expect(strings.guidanceFor(FaceGuidance.lowLight), 'Find better lighting');
      expect(strings.guidanceFor(FaceGuidance.multipleFaces),
          'Only one face should be visible');
    });

    test('LivenessStrings.copyWith', () {
      const base = LivenessStrings(
        actionInstructions: {LivenessAction.smile: 'Souriez'},
      );
      final copy = base.copyWith(failed: 'Échec');
      expect(copy.failed, 'Échec');
      expect(copy.instructionFor(LivenessAction.smile), 'Souriez');
      expect(copy.completed, base.completed);
    });

    test('LivenessTheme.copyWith', () {
      const base = LivenessTheme(ovalSizeFactor: 0.6);
      final copy = base.copyWith(
        closeIconColor: Colors.black,
        strings: const LivenessStrings(failed: 'Nope'),
      );
      expect(copy.closeIconColor, Colors.black);
      expect(copy.ovalSizeFactor, 0.6);
      expect(copy.strings.failed, 'Nope');
      expect(copy.hintStyle, base.hintStyle);
    });
  });
}
