import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

void main() {
  group('B2 LivenessConfig.validate', () {
    void expectInvalid(LivenessConfig config, String field) {
      expect(
        config.validate,
        throwsA(isA<ArgumentError>().having((e) => e.name, 'name', field)),
      );
      expect(() => LivenessSession(config), throwsArgumentError);
    }

    test('a default config with actions is valid', () {
      const LivenessConfig(actions: [LivenessAction.blink]).validate();
    });

    test('empty actions', () {
      expectInvalid(const LivenessConfig(actions: []), 'actions');
    });

    // Built at runtime (non-const) so the constructor asserts don't fire
    // first — validate() must also catch these in release builds.
    int runtime(int v) => v;
    double runtimeD(double v) => v;

    test('jpegQuality out of range', () {
      expect(
        () => LivenessConfig(
            actions: const [LivenessAction.blink], jpegQuality: runtime(0)),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => LivenessConfig(
            actions: const [LivenessAction.blink], jpegQuality: runtime(101)),
        throwsA(isA<AssertionError>()),
      );
    });

    test('maxImageDimension below 64', () {
      expect(
        () => LivenessConfig(
            actions: const [LivenessAction.blink],
            maxImageDimension: runtime(32)),
        throwsA(isA<AssertionError>()),
      );
    });

    test('brightnessMin >= brightnessMax', () {
      expect(
        () => LivenessConfig(
          actions: const [LivenessAction.blink],
          brightnessMin: runtimeD(0.9),
          brightnessMax: runtimeD(0.5),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('non-positive durations', () {
      expectInvalid(
        const LivenessConfig(
            actions: [LivenessAction.blink], actionTimeout: Duration.zero),
        'actionTimeout',
      );
      expectInvalid(
        const LivenessConfig(
            actions: [LivenessAction.blink],
            neutralTimeout: Duration(seconds: -1)),
        'neutralTimeout',
      );
      expectInvalid(
        const LivenessConfig(
            actions: [LivenessAction.blink], sessionTimeout: Duration.zero),
        'sessionTimeout',
      );
      expectInvalid(
        const LivenessConfig(
            actions: [LivenessAction.blink],
            faceLostGrace: Duration(milliseconds: -1)),
        'faceLostGrace',
      );
    });

    test('zero faceLostGrace is allowed (no grace)', () {
      const LivenessConfig(
        actions: [LivenessAction.blink],
        faceLostGrace: Duration.zero,
      ).validate();
    });
  });

  testWidgets('B2 empty actions produce exactly one failed result',
      (tester) async {
    final results = <LivenessResult>[];
    final errors = <Object>[];
    await tester.pumpWidget(MaterialApp(
      home: LivenessDetector(
        config: const LivenessConfig(actions: []),
        onResult: results.add,
        onError: (e, _) => errors.add(e),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(results, hasLength(1));
    expect(results.single.success, isFalse);
    expect(results.single.failureReason, LivenessFailureReason.systemError);
    expect(results.single.metadata['configError'], contains('actions'));
    expect(errors.single, isA<ArgumentError>());
  });
}
