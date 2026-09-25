import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

import '../support/fake_frame_source.dart';

void main() {
  final harness = FakeSourceHarness();
  setUp(harness.install);
  tearDown(harness.uninstall);

  Future<List<LivenessResult>> pumpDetector(
    WidgetTester tester, {
    LivenessConfig config = const LivenessConfig(
      actions: [LivenessAction.smile],
      capture: {CaptureType.images},
    ),
  }) async {
    usePhoneScreen(tester);
    final results = <LivenessResult>[];
    await tester.pumpWidget(MaterialApp(
      home: LivenessDetector(
        config: config,
        onResult: results.add,
      ),
    ));
    await tester.pump();
    return results;
  }

  group('T1 fake frame source', () {
    testWidgets('a scripted smile session succeeds once with evidence',
        (tester) async {
      final results = await pumpDetector(tester);
      expect(harness.source.started, isTrue);
      expect(find.byKey(const ValueKey('fake-preview')), findsOneWidget);

      await harness.step(tester, [face()]); // reference + smile starts
      await harness.hold(tester, [face(smile: 0.9)], 700);
      await tester.pump(const Duration(seconds: 1));

      expect(results, hasLength(1));
      final result = results.single;
      expect(result.success, isTrue);
      expect(result.completedActions, [LivenessAction.smile]);
      expect(result.images.map((i) => i.kind),
          [CaptureKind.reference, CaptureKind.peak]);
      expect(harness.source.stopped, isTrue);
    });

    testWidgets('a camera that fails to open ends with one systemError',
        (tester) async {
      harness.nextStartError = StateError('no camera');
      final results = <LivenessResult>[];
      final errors = <Object>[];
      await tester.pumpWidget(MaterialApp(
        home: LivenessDetector(
          config: const LivenessConfig(actions: [LivenessAction.smile]),
          onResult: results.add,
          onError: (e, _) => errors.add(e),
        ),
      ));
      await tester.pump(const Duration(seconds: 1));
      expect(errors.single, isA<StateError>());
      expect(results.single.failureReason, LivenessFailureReason.systemError);
    });
  });

  group('B3 onResult on dispose', () {
    testWidgets('removing the detector mid-session delivers one cancel',
        (tester) async {
      final results = await pumpDetector(tester);
      await harness.step(tester, [face()]);
      await harness.step(tester, [face(smile: 0.9)]);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(results, hasLength(1));
      expect(results.single.success, isFalse);
      expect(results.single.failureReason, LivenessFailureReason.cancelled);
      expect(results.single.metadata['cancelledBy'], 'dispose');
      expect(harness.source.disposed, isTrue);

      await tester.pump(const Duration(seconds: 2));
      expect(results, hasLength(1));
    });

    testWidgets('popping a route mid-session delivers one cancel',
        (tester) async {
      final results = <LivenessResult>[];
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigatorKey,
        home: const SizedBox(),
      ));
      navigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (context) => LivenessDetector(
          config: const LivenessConfig(actions: [LivenessAction.smile]),
          onResult: (result) {
            results.add(result);
            // README pattern: must be safe after a system back.
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ));
      await tester.pumpAndSettle();
      await harness.step(tester, [face()]);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(results, hasLength(1));
      expect(results.single.metadata['cancelledBy'], 'dispose');
    });

    testWidgets('the close button cancels with cancelledBy: user',
        (tester) async {
      final results = await pumpDetector(tester);
      await harness.step(tester, [face()]);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump(const Duration(seconds: 1));
      expect(results.single.failureReason, LivenessFailureReason.cancelled);
      expect(results.single.metadata['cancelledBy'], 'user');

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(results, hasLength(1));
    });

    testWidgets('app going to background cancels with cancelledBy: lifecycle',
        (tester) async {
      final results = await pumpDetector(tester);
      await harness.step(tester, [face()]);
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 1));
      expect(results.single.metadata['cancelledBy'], 'lifecycle');
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets('a success cut short by dispose is still a success',
        (tester) async {
      final results = await pumpDetector(tester);
      await harness.step(tester, [face()]);
      await harness.hold(tester, [face(smile: 0.9)], 700);
      // Session completed; result hold (400 ms) still running.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(results.single.success, isTrue);
      expect(results.single.metadata.containsKey('cancelledBy'), isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(results, hasLength(1));
    });

    testWidgets('a throwing onResult during dispose goes to onError',
        (tester) async {
      final errors = <Object>[];
      await tester.pumpWidget(MaterialApp(
        home: LivenessDetector(
          config: const LivenessConfig(actions: [LivenessAction.smile]),
          onResult: (_) => throw StateError('boom'),
          onError: (e, _) => errors.add(e),
        ),
      ));
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(errors.whereType<StateError>(), hasLength(1));
    });
  });

  group('C3 detection follows the drawn target', () {
    Future<LivenessSessionState> positionWith(
      WidgetTester tester,
      FaceSnapshot f, {
      LivenessTheme theme = const LivenessTheme(),
      Rect? targetRegion,
    }) async {
      usePhoneScreen(tester);
      final controller = LivenessController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: LivenessDetector(
          controller: controller,
          theme: theme,
          targetRegion: targetRegion,
          config: const LivenessConfig(actions: [LivenessAction.smile]),
          onResult: (_) {},
        ),
      ));
      await tester.pump();
      await harness.step(tester, [f]);
      return controller.state;
    }

    testWidgets('the default oval accepts a centred face', (tester) async {
      final state = await positionWith(tester, face());
      expect(state.phase, LivenessPhase.performingAction);
    });

    testWidgets('shrinking ovalSizeFactor makes the same face too close',
        (tester) async {
      final state = await positionWith(
        tester,
        face(),
        theme: const LivenessTheme(ovalSizeFactor: 0.3),
      );
      expect(state.phase, LivenessPhase.centeringFace);
      expect(state.guidance, FaceGuidance.tooClose);
    });

    testWidgets('moving the oval makes a centred face not centred',
        (tester) async {
      final state = await positionWith(
        tester,
        face(box: const Rect.fromLTWH(0.4, 0.4, 0.2, 0.2)),
        theme: const LivenessTheme(ovalCenter: Offset(0.5, 0.2)),
      );
      expect(state.guidance, FaceGuidance.notCentered);
    });

    testWidgets('targetRegion drives detection (and accounts for the mirror)',
        (tester) async {
      // Top-left of the screen = top-right of the unmirrored camera image.
      const region = Rect.fromLTWH(0.05, 0.05, 0.4, 0.25);
      final centred = await positionWith(tester, face(), targetRegion: region);
      expect(centred.faceInPosition, isFalse);

      await tester.pumpWidget(const SizedBox());
      final inRegion = await positionWith(
        tester,
        face(box: const Rect.fromLTWH(0.605, 0.075, 0.2, 0.2)),
        targetRegion: region,
      );
      expect(inRegion.phase, LivenessPhase.performingAction);
    });
  });

  group('C4 layout and styling hooks', () {
    Future<List<LivenessResult>> pumpWith(
      WidgetTester tester, {
      LivenessTheme theme = const LivenessTheme(),
      AlignmentGeometry instructionAlignment = const Alignment(0, 0.72),
      Widget Function(BuildContext, VoidCallback)? closeButtonBuilder,
    }) async {
      usePhoneScreen(tester);
      final results = <LivenessResult>[];
      await tester.pumpWidget(MaterialApp(
        home: LivenessDetector(
          theme: theme,
          instructionAlignment: instructionAlignment,
          closeButtonBuilder: closeButtonBuilder,
          config: const LivenessConfig(actions: [LivenessAction.smile]),
          onResult: results.add,
        ),
      ));
      await tester.pump();
      return results;
    }

    testWidgets('instructionAlignment positions the instruction panel',
        (tester) async {
      await pumpWith(tester, instructionAlignment: Alignment.topCenter);
      final align = tester.widget<Align>(find
          .ancestor(
            of: find.text('Position your face in the oval'),
            matching: find.byType(Align),
          )
          .first);
      expect(align.alignment, Alignment.topCenter);
    });

    testWidgets('close icon colour, alignment and tooltip come from theme',
        (tester) async {
      await pumpWith(
        tester,
        theme: const LivenessTheme(
          closeIconColor: Colors.black,
          closeButtonAlignment: Alignment.topRight,
          strings: LivenessStrings(close: 'Schließen'),
        ),
      );
      expect(tester.widget<Icon>(find.byIcon(Icons.close)).color,
          Colors.black);
      expect(find.byTooltip('Schließen'), findsOneWidget);
      expect(tester.getCenter(find.byIcon(Icons.close)).dx,
          greaterThan(360 / 2));
    });

    testWidgets('closeButtonBuilder replaces the button and can cancel',
        (tester) async {
      final results = await pumpWith(
        tester,
        closeButtonBuilder: (context, onClose) =>
            TextButton(onPressed: onClose, child: const Text('Not now')),
      );
      expect(find.byIcon(Icons.close), findsNothing);
      await tester.tap(find.text('Not now'));
      await tester.pump(const Duration(seconds: 1));
      expect(results.single.metadata['cancelledBy'], 'user');
    });

    testWidgets('resultHoldDuration delays onResult', (tester) async {
      final results = await pumpWith(
        tester,
        theme: const LivenessTheme(
          resultHoldDuration: Duration(milliseconds: 1500),
        ),
      );
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump(const Duration(milliseconds: 1000));
      expect(results, isEmpty);
      await tester.pump(const Duration(milliseconds: 600));
      expect(results, hasLength(1));
    });
  });
}
