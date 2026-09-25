import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

void main() {
  group('S4 randomActionCount', () {
    const pool = LivenessAction.values;

    test('picks N distinct actions from the pool', () {
      final session = LivenessSession(
        const LivenessConfig(actions: pool, randomActionCount: 3),
        random: Random(1),
      );
      expect(session.actionOrder, hasLength(3));
      expect(session.actionOrder.toSet(), hasLength(3));
      expect(pool.toSet().containsAll(session.actionOrder), isTrue);
      expect(session.current.totalActions, 3);
      expect(session.current.actionPlan, session.actionOrder);
    });

    test('varies both selection and order between sessions', () {
      final plans = {
        for (var seed = 0; seed < 40; seed++)
          LivenessSession(
            const LivenessConfig(actions: pool, randomActionCount: 3),
            random: Random(seed),
          ).actionOrder.join(','),
      };
      expect(plans.length, greaterThan(30));
    });

    test('N = pool size is a full shuffle', () {
      const small = [
        LivenessAction.blink,
        LivenessAction.smile,
        LivenessAction.nod,
      ];
      final session = LivenessSession(
        const LivenessConfig(actions: small, randomActionCount: 3),
      );
      expect(session.actionOrder.toSet(), small.toSet());
    });

    test('out-of-range counts are rejected', () {
      for (final n in [0, -1, pool.length + 1]) {
        expect(
          () => LivenessSession(
              LivenessConfig(actions: pool, randomActionCount: n)),
          throwsA(isA<ArgumentError>()
              .having((e) => e.name, 'name', 'randomActionCount')),
          reason: 'n = $n',
        );
      }
    });

    test('a challenge wins over randomActionCount', () {
      final session = LivenessSession(LivenessConfig(
        actions: pool,
        randomActionCount: 2,
        challenge: LivenessChallenge(
          nonce: 'n',
          actions: const [LivenessAction.nod],
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      ));
      expect(session.actionOrder, [LivenessAction.nod]);
    });
  });
}
