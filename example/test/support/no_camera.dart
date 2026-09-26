import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replaces the camera plugin for widget tests: asking for cameras fails
/// with [code], so a LivenessDetector ends straight away — with
/// `systemError`, or `permissionDenied` for 'CameraAccessDenied'.
///
/// (Without this, the plugin's platform call never answers in tests.)
void useNoCamera({String code = 'CameraUnavailable'}) {
  final original = CameraPlatform.instance;
  CameraPlatform.instance = _NoCamera(code);
  addTearDown(() => CameraPlatform.instance = original);
}

class _NoCamera extends CameraPlatform {
  _NoCamera(this.code);

  final String code;

  @override
  Future<List<CameraDescription>> availableCameras() async =>
      throw CameraException(code, 'No camera in tests');
}

/// Advances fake time in small steps, so timers started along the way
/// (the result hold, navigation) all get to fire.
Future<void> advance(WidgetTester tester, {int ms = 2000}) async {
  for (var t = 0; t < ms; t += 100) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
