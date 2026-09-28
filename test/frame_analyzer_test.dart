import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';
import 'package:liveness_flutter/src/camera/detection_geometry.dart';

class _Fixed extends LivenessFrameAnalyzer {
  const _Fixed(this.id, this.score);
  @override
  final String id;
  final double? score;
  @override
  Future<double?> analyze(LivenessFrame frame) async => score;
}

void main() {
  group('S3 config validation', () {
    test('analyzer ids must be unique', () {
      expect(
        () => const LivenessConfig(
          actions: [LivenessAction.blink],
          frameAnalyzers: [_Fixed('pad', 0.1), _Fixed('pad', 0.2)],
        ).validate(),
        throwsA(isA<ArgumentError>()
            .having((e) => e.name, 'name', 'frameAnalyzers')),
      );
    });

    test('analyzerWeight must be 0–1', () {
      expect(
        () => const LivenessConfig(
          actions: [LivenessAction.blink],
          analyzerWeight: 1.5,
        ).validate(),
        throwsArgumentError,
      );
    });
  });

  group('S3 faceSpaceToUpright', () {
    const box = Rect.fromLTRB(0.1, 0.4, 0.3, 0.6);

    test('upright (portrait) face space is unchanged', () {
      expect(
        faceSpaceToUpright(box, (
          faceSpaceSize: const Size(720, 1280),
          rotationDegrees: 270,
          mirrored: true,
        )),
        box,
      );
    });

    test('a raw landscape buffer is turned like the JPEG encoder does', () {
      // 90° clockwise: the buffer's left edge becomes the top.
      final upright = faceSpaceToUpright(box, (
        faceSpaceSize: const Size(1280, 720),
        rotationDegrees: 90,
        mirrored: true,
      ));
      expect(upright.top, closeTo(0.1, 1e-9));
      expect(upright.bottom, closeTo(0.3, 1e-9));
      expect(upright.left, closeTo(0.4, 1e-9));
      expect(upright.right, closeTo(0.6, 1e-9));
    });
  });
}
