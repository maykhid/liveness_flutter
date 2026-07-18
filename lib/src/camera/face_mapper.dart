import 'dart:math' as math;
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/models.dart';

/// Maps ML Kit [Face] objects to normalized, platform-independent
/// [FaceSnapshot]s.
class FaceMapper {
  const FaceMapper({
    required this.mirrorYaw,
    required this.uprightCoordinates,
  });

  /// See `LivenessConfig.mirrorYaw`.
  final bool mirrorYaw;

  /// Android ML Kit reports coordinates in the rotated (upright) frame, so
  /// dimensions must be swapped for 90/270 rotations. iOS reports them in
  /// the raw buffer frame. Pass `Platform.isAndroid`.
  final bool uprightCoordinates;

  FaceSnapshot map(
    Face face, {
    required Size imageSize,
    required InputImageRotation rotation,
    required int timestampMs,
  }) {
    final swap = uprightCoordinates &&
        (rotation == InputImageRotation.rotation90deg ||
            rotation == InputImageRotation.rotation270deg);
    final upright =
        swap ? Size(imageSize.height, imageSize.width) : imageSize;

    final w = upright.width == 0 ? 1.0 : upright.width;
    final h = upright.height == 0 ? 1.0 : upright.height;

    Rect normRect(Rect r) =>
        Rect.fromLTRB(r.left / w, r.top / h, r.right / w, r.bottom / h);

    Offset? nose;
    final noseLandmark = face.landmarks[FaceLandmarkType.noseBase];
    if (noseLandmark != null) {
      nose = Offset(
        noseLandmark.position.x / w,
        noseLandmark.position.y / h,
      );
    }

    // Sign conventions differ between platforms because Android processes
    // the rotated upright frame while iOS processes the raw buffer.
    // Target convention: positive yaw = user's left, positive roll = tilt
    // toward the user's left shoulder. `mirrorYaw=false` inverts both for
    // devices that disagree.
    final platformSign = uprightCoordinates ? 1.0 : -1.0; // Android : iOS
    final userSign = mirrorYaw ? 1.0 : -1.0;

    final rawYaw = face.headEulerAngleY;
    final yaw = rawYaw == null ? null : rawYaw * platformSign * userSign;

    final rawRoll = face.headEulerAngleZ;
    final roll = rawRoll == null ? null : rawRoll * -platformSign * userSign;

    return FaceSnapshot(
      timestampMs: timestampMs,
      smileProbability: face.smilingProbability,
      leftEyeOpenProbability: face.leftEyeOpenProbability,
      rightEyeOpenProbability: face.rightEyeOpenProbability,
      headEulerAngleX: face.headEulerAngleX,
      headEulerAngleY: yaw,
      headEulerAngleZ: roll,
      noseBase: nose,
      mouthOpenRatio: _mouthOpenRatio(face),
      boundingBox: normRect(face.boundingBox),
      trackingId: face.trackingId,
    );
  }

  double? _mouthOpenRatio(Face face) {
    final upper = face.contours[FaceContourType.upperLipBottom]?.points;
    final lower = face.contours[FaceContourType.lowerLipTop]?.points;
    if (upper == null || lower == null || upper.isEmpty || lower.isEmpty) {
      return null;
    }
    final upperMid = upper[upper.length ~/ 2];
    final lowerMid = lower[lower.length ~/ 2];
    // Euclidean distance: orientation-agnostic (the gap axis differs between
    // Android upright space and iOS landscape buffer space).
    final dx = (lowerMid.x - upperMid.x).toDouble();
    final dy = (lowerMid.y - upperMid.y).toDouble();
    final gap = math.sqrt(dx * dx + dy * dy);
    // Normalize by the larger box side (≈ face height in either orientation).
    final box = face.boundingBox;
    final faceExtent = math.max(box.width, box.height);
    if (faceExtent <= 0) return null;
    return gap / faceExtent;
  }
}
