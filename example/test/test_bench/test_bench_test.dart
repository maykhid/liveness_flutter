import 'package:flutter_test/flutter_test.dart';

import 'package:liveness_flutter_example/main.dart';

void main() {
  testWidgets('home page renders its settings and start button',
      (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('Start liveness check'), findsOneWidget);
    expect(find.text('Presets'), findsOneWidget);
    expect(find.text('Actions'), findsOneWidget);
  });

  testWidgets('presets apply without errors', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    for (final name in [
      'Quick test',
      'Server-bound (KYC)',
      'Everything on',
      'Accessible',
    ]) {
      await tester.tap(find.text(name));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Preset: Accessible'), findsOneWidget);
  });

  testWidgets('every settings group opens without errors', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    for (final group in [
      'Timing',
      'Capture',
      'Security & anti-spoof',
      'Camera & detection',
      'Look & feel',
      'Permissions',
      'Upload',
    ]) {
      await tester.scrollUntilVisible(find.text(group), 200);
      await tester.tap(find.text(group));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: group);
    }
  });
}
