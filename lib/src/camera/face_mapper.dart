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
    this.invertPitch = false,
  });

  /// See `LivenessConfig.mirrorYaw`.
  final bool mirrorYaw;

  /// See `LivenessConfig.invertPitch`.
  final bool invertPitch;

  /// Android ML Kit reports coordinates in the rotated (upright) frame, so
  /// dimensions must be swapped for 90/270 rotations. iOS reports them in
  /// the raw buffer frame. Pass `Platform.isAndroid`.
  final bool uprightCoordinates;

  /// The size face coordinates are normalised by: the rotated (upright)
  /// size on Android, the raw buffer size on iOS.
  Size faceSpaceSize(Size imageSize, InputImageRotation rotation) {
    final swap = uprightCoordinates &&
        (rotation == InputImageRotation.rotation90deg ||
            rotation == InputImageRotation.rotation270deg);
    return swap ? Size(imageSize.height, imageSize.width) : imageSize;
  }

  FaceSnapshot map(
    Face face, {
    required Size imageSize,
    required InputImageRotation rotation,
    required int timestampMs,
  }) {
    final upright = faceSpaceSize(imageSize, rotation);

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

    // Pitch is passed through: ML Kit documents positive X as "facing
    // up" on both platforms, and the Android/iOS difference that flips yaw
    // and roll above is a horizontal mirror, which leaves pitch unchanged.
    // TODO(B8): confirm on an iPhone (nod, lookUp, lookDown with
    // showDebugOverlay) and drop this note, or flip the iOS sign here.
    final rawPitch = face.headEulerAngleX;
    final pitch =
        rawPitch == null ? null : (invertPitch ? -rawPitch : rawPitch);

    return FaceSnapshot(
      timestampMs: timestampMs,
      smileProbability: face.smilingProbability,
      leftEyeOpenProbability: face.leftEyeOpenProbability,
      rightEyeOpenProbability: face.rightEyeOpenProbability,
      headEulerAngleX: pitch,
      headEulerAngleY: yaw,
      headEulerAngleZ: roll,
      noseBase: nose,
      mouthOpenRatio: _mouthOpenRatio(face),
      boundingBox: normRect(face.boundingBox),
      trackingId: face.trackingId,
      identitySignature: _identitySignature(face),
    );
  }

  /// Distances are ratios of the same frame, so no normalisation to image
  /// size is needed; dividing by √(box area) makes them independent of
  /// distance and of portrait/landscape coordinates.
  (double, double)? _identitySignature(Face face) {
    math.Point<double>? centroid(FaceContourType type) {
      final points = face.contours[type]?.points;
      if (points == null || points.isEmpty) return null;
      var x = 0.0, y = 0.0;
      for (final p in points) {
        x += p.x;
        y += p.y;
      }
      return math.Point(x / points.length, y / points.length);
    }

    math.Point<double>? landmark(FaceLandmarkType type) {
      final p = face.landmarks[type]?.position;
      return p == null ? null : math.Point(p.x.toDouble(), p.y.toDouble());
    }

    final leftEye = centroid(FaceContourType.leftEye) ??
        landmark(FaceLandmarkType.leftEye);
    final rightEye = centroid(FaceContourType.rightEye) ??
        landmark(FaceLandmarkType.rightEye);
    final nose = centroid(FaceContourType.noseBottom) ??
        landmark(FaceLandmarkType.noseBase);
    final mouth = centroid(FaceContourType.upperLipTop) ??
        landmark(FaceLandmarkType.bottomMouth);
    final box = face.boundingBox;
    final scale = math.sqrt(box.width * box.height);
    if (leftEye == null ||
        rightEye == null ||
        nose == null ||
        mouth == null ||
        scale <= 0) {
      return null;
    }
    return (
      leftEye.distanceTo(rightEye) / scale,
      nose.distanceTo(mouth) / scale,
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
