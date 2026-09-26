import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter_example/recipes/controller.dart';
import 'package:liveness_flutter_example/recipes/custom_ui.dart';
import 'package:liveness_flutter_example/recipes/server_bound.dart';

import '../support/no_camera.dart';

// With no camera, each LivenessDetector ends with a systemError result —
// enough to check the screens build and the result path works.
void main() {
  setUp(useNoCamera);

  testWidgets('custom UI recipe builds', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CustomUiPage()));
    await advance(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('controller recipe shows the result and offers a retry',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ControllerPage()));
    await advance(tester);
    expect(find.text('Last result: systemError'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('server-bound recipe warns when there is no backend',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ServerBoundPage()));
    expect(find.textContaining('No BACKEND_URL'), findsOneWidget);
  });

  test('without a backend, the upload is skipped (not faked)', () async {
    final message = await uploadResultForTest();
    expect(message, contains('nothing was uploaded'));
  });
}
