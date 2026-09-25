import 'dart:math';

import '../models/models.dart';

/// Notices a different face appearing mid-session, without a face model.
///
/// Two soft signals:
/// 1. **Tracking ID.** With ML Kit tracking on, a face that stays in view
///    keeps its ID. A change *without* a frame in between that had no
///    face is suspicious ([continuousTrackingIdChanges]); a change after
///    the face briefly left is normal and only counted.
/// 2. **Geometry.** [FaceSnapshot.identitySignature] (eye distance and
///    nose-to-mouth distance relative to face size) is compared across
///    near-frontal frames against a reference taken from the first ones.
///    Large jumps are counted ([signatureJumps]) for server-side review.
class IdentityGuard {
  IdentityGuard({
    this.maxSignatureDeviation = 0.25,
    this.frontalMaxAngle = 12,
    this.referenceFrames = 5,
  });

  /// Relative change of either signature ratio that counts as a jump.
  final double maxSignatureDeviation;

  /// Only frames with |yaw| and |pitch| below this are compared.
  final double frontalMaxAngle;

  /// Near-frontal frames averaged into the reference signature.
  final int referenceFrames;

  int? _trackingId;
  bool _gap = false;
  int trackingIdChanges = 0;
  int continuousTrackingIdChanges = 0;

  final List<(double, double)> _referenceSamples = [];
  (double, double)? _reference;
  int signatureFrames = 0;
  int signatureJumps = 0;

  /// Feed the primary face of each analysed frame, or null when no face
  /// was seen (or the frame was skipped).
  void onFrame(FaceSnapshot? face) {
    if (face == null) {
      _gap = true;
      return;
    }
    final id = face.trackingId;
    if (id != null) {
      final previous = _trackingId;
      if (previous != null && id != previous) {
        trackingIdChanges++;
        if (!_gap) continuousTrackingIdChanges++;
      }
      _trackingId = id;
    }
    _gap = false;

    final signature = face.identitySignature;
    final yaw = (face.headEulerAngleY ?? 0).abs();
    final pitch = (face.headEulerAngleX ?? 0).abs();
    if (signature == null || yaw > frontalMaxAngle || pitch > frontalMaxAngle) {
      return;
    }
    final reference = _reference;
    if (reference == null) {
      _referenceSamples.add(signature);
      if (_referenceSamples.length >= referenceFrames) {
        var a = 0.0, b = 0.0;
        for (final (x, y) in _referenceSamples) {
          a += x;
          b += y;
        }
        _reference =
            (a / _referenceSamples.length, b / _referenceSamples.length);
      }
      return;
    }
    signatureFrames++;
    final (a0, b0) = reference;
    final (a, b) = signature;
    if (a0 <= 0 || b0 <= 0) return;
    final deviation = max((a - a0).abs() / a0, (b - b0).abs() / b0);
    if (deviation > maxSignatureDeviation) signatureJumps++;
  }

  /// A face swap while a face stayed in view.
  bool get faceChanged => continuousTrackingIdChanges > 0;

  /// 0–0.3 off the confidence score for continuous tracking-ID changes.
  /// Geometry jumps are reported only (not yet calibrated on real users).
  double get confidencePenalty =>
      min(0.3, continuousTrackingIdChanges * 0.15);

  Map<String, Object?> get metadata => {
        'identity_trackingIdChanges': trackingIdChanges,
        'identity_trackingIdChangesContinuous': continuousTrackingIdChanges,
        'identity_signatureFrames': signatureFrames,
        'identity_signatureJumps': signatureJumps,
      };
}
