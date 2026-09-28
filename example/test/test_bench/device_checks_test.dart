import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter_example/test_bench/main.dart';
import 'package:liveness_flutter_example/test_bench/src/device_checks.dart';

import '../support/no_camera.dart';

void main() {
  group('the checks themselves', () {
    test('ids are unique', () {
      final ids = deviceChecks.map((c) => c.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('every test-bench check has settings that form a valid config', () {
      for (final c in deviceChecks) {
        if (c.target == CheckTarget.testBench) {
          expect(c.settings, isNotNull, reason: 'check ${c.id}');
          expect(() => c.settings!().toConfig().validate(), returnsNormally,
              reason: 'check ${c.id}');
        }
      }
    });

    test('checks set up what their scenario needs', () {
      DeviceCheck byId(String id) => deviceChecks.firstWhere((c) => c.id == id);
      expect(byId('2').settings!().debugOverlay, isTrue);
      expect(byId('3').settings!().externalControls, isTrue);
      expect(byId('5').settings!().assisted, isTrue);
      expect(byId('6').settings!().flashChallenge, isTrue);
      expect(byId('14').settings!().toConfig().failOnMultipleFaces, isTrue);
      expect(byId('15').settings!().toConfig().failOnMultipleFaces, isFalse);
    });
  });

  test('the report lists every check with its status and the OS', () {
    final log = DeviceCheckLog()..deviceModel = 'Pixel 7';
    log.record('7', CheckStatus.failed, 'passed instantly after uncovering');
    log.record('1', CheckStatus.passed, '');
    final report = log.report();
    expect(report, contains('Device: Pixel 7'));
    expect(report, contains('OS: '));
    expect(report, contains('[PASS] 1.'));
    expect(report, contains('[FAIL] 7.'));
    expect(report, contains('passed instantly after uncovering'));
    expect(report, contains('[----] 2.'));
  });

  testWidgets('open, run, mark: a check runs a session and is recorded',
      (tester) async {
    useNoCamera(); // the session ends straight away with systemError
    await tester.pumpWidget(const TestBenchApp());
    await tester.tap(find.text('Device checks'));
    await tester.pumpAndSettle();
    expect(find.text('1. Camera fills the circle under an app bar'),
        findsOneWidget);

    await tester.tap(find.text('4. Close while the camera is starting'));
    await tester.pumpAndSettle();
    expect(find.text('Expected'), findsOneWidget);

    await tester.tap(find.text('Run this check'));
    await advance(tester);
    await tester.pumpAndSettle();
    // Back on the check page after the session ended.
    expect(find.text('Run this check'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'camera error');
    await tester.tap(find.text('Failed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('failed 1'), findsOneWidget);

    // The session it ran is in the session list.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sessions'), 300);
    expect(find.textContaining('systemError'), findsWidgets);
  });
}
