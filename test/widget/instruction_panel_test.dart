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
}
