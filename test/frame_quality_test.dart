import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

void main() {
  const config = LivenessConfig(actions: [LivenessAction.blink]);
  FrameQuality q(double brightness, [double sharpness = 0.2]) =>
      FrameQuality(brightness: brightness, sharpness: sharpness, hash: 0);

  group('B9a quality guidance', () {
    test('dark frames report lowLight', () {
      expect(q(0.05).issueFor(config), FaceGuidance.lowLight);
    });

    test('overexposed frames report tooBright, not lowLight', () {
      expect(q(0.98).issueFor(config), FaceGuidance.tooBright);
    });

    test('flat frames report blurry', () {
      expect(q(0.5, 0.01).issueFor(config), FaceGuidance.blurry);
    });

    test('a good frame has no issue', () {
      expect(q(0.5).issueFor(config), isNull);
    });

    test('tooBright has a default message', () {
      expect(
        const LivenessStrings().guidanceFor(FaceGuidance.tooBright),
        isNotEmpty,
      );
    });
  });
}
