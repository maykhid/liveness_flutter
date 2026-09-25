import 'package:flutter_test/flutter_test.dart';
// Deliberately the only import: everything the public API needs must be
// reachable from here.
import 'package:liveness_flutter/liveness_flutter.dart';

void main() {
  test('C7 ResolutionPreset is re-exported', () {
    const preset = ResolutionPreset.medium;
    expect(preset.name, 'medium');
  });

  test('C3 TargetShape is exported for LivenessTheme.ovalShape', () {
    const theme = LivenessTheme(ovalShape: TargetShape.circle);
    expect(theme.ovalShape, TargetShape.circle);
  });
}
