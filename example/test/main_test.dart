import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter_example/main.dart';

void main() {
  testWidgets('the minimal example shows its button', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    expect(find.text("Verify it's me"), findsOneWidget);
  });
}
