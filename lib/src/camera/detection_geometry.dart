import 'dart:ui';

import '../models/models.dart';

/// Shape of the on-screen target the face must fill.
enum TargetShape { oval, roundedRect, circle }

/// What a frame source knows about how its face coordinates relate to the
/// displayed preview.
typedef CameraGeometry = ({
  Size faceSpaceSize,
  int rotationDegrees,
  bool mirrored,
});

/// Maps between the widget's normalised screen space (0..1 over the view)
/// and the normalised space [FaceSnapshot] boxes are reported in ("face
/// space"). Pure maths, no platform calls.
///
/// The camera preview is cover-fitted to the view (the same maths as the
/// built-in full-screen preview) and, for the front camera, mirrored. Face
/// space is either already upright (Android: ML Kit reports rotated
/// coordinates) or the raw sensor buffer (iOS). Which one is detected from
/// the shapes: when face space is landscape while the view is portrait (or
/// the reverse) and the camera rotation is a quarter turn, face space is
/// the unrotated buffer and points are turned back by [rotationDegrees].
class DetectionGeometry {
  const DetectionGeometry({
    required this.viewSize,
    required this.faceSpaceSize,
    required this.rotationDegrees,
    required this.mirrored,
  });

  /// Size of the widget the preview and overlay fill.
  final Size viewSize;

  /// Size (pixels) that face coordinates are normalised by.
  final Size faceSpaceSize;

  /// Clockwise degrees that turn the camera buffer upright (0/90/180/270).
  final int rotationDegrees;

  /// Whether the preview is shown mirrored (front camera).
  final bool mirrored;

  bool get _quarterTurn {
    final quarter = rotationDegrees == 90 || rotationDegrees == 270;
    final viewPortrait = viewSize.height >= viewSize.width;
    final facePortrait = faceSpaceSize.height >= faceSpaceSize.width;
    return quarter && viewPortrait != facePortrait;
  }

  /// The camera image as displayed (upright), in pixels.
  Size get displayedImageSize => _quarterTurn
      ? Size(faceSpaceSize.height, faceSpaceSize.width)
      : faceSpaceSize;

  /// Fraction of the displayed image visible along x and y after the
  /// cover-fit crop.
  (double, double) get _visible {
    final image = displayedImageSize;
    if (image.isEmpty || viewSize.isEmpty) return (1, 1);
    final imageAspect = image.width / image.height;
    final viewAspect = viewSize.width / viewSize.height;
    return imageAspect > viewAspect
        ? (viewAspect / imageAspect, 1)
        : (1, imageAspect / viewAspect);
  }

  /// Screen point (normalised to the view) → face-space point.
  Offset viewToFace(Offset p) {
    final (sx, sy) = _visible;
    // View → displayed (upright, mirrored-as-shown) image.
    var x = 0.5 + (p.dx - 0.5) * sx;
    final y = 0.5 + (p.dy - 0.5) * sy;
    // Undo the preview mirror.
    if (mirrored) x = 1 - x;
    if (!_quarterTurn) return Offset(x, y);
    // Upright → raw buffer (inverse of the clockwise turn).
    return rotationDegrees == 90 ? Offset(y, 1 - x) : Offset(1 - y, x);
  }

  /// Face-space point → screen point (normalised to the view).
  Offset faceToView(Offset p) {
    var x = p.dx, y = p.dy;
    if (_quarterTurn) {
      // Raw buffer → upright (clockwise turn).
      (x, y) = rotationDegrees == 90 ? (1 - p.dy, p.dx) : (p.dy, 1 - p.dx);
    }
    if (mirrored) x = 1 - x;
    final (sx, sy) = _visible;
    return Offset(0.5 + (x - 0.5) / sx, 0.5 + (y - 0.5) / sy);
  }

  Rect viewRectToFace(Rect r) =>
      Rect.fromPoints(viewToFace(r.topLeft), viewToFace(r.bottomRight));

  Rect faceRectToView(Rect r) =>
      Rect.fromPoints(faceToView(r.topLeft), faceToView(r.bottomRight));
}

/// The region a face must occupy to count as "in position", in face space.
class TargetZone {
  const TargetZone(this.rect, this.shape);

  final Rect rect;
  final TargetShape shape;

  /// Whether [p] lies inside the shape. Rounded rectangles are treated as
  /// plain rectangles (the corners are a small fraction of the area).
  bool contains(Offset p) {
    if (rect.isEmpty) return false;
    switch (shape) {
      case TargetShape.roundedRect:
        return rect.contains(p);
      case TargetShape.oval:
      case TargetShape.circle:
        final dx = (p.dx - rect.center.dx) / (rect.width / 2);
        final dy = (p.dy - rect.center.dy) / (rect.height / 2);
        return dx * dx + dy * dy <= 1;
    }
  }

  /// Positioning problem for [face], or null when it is in position: its
  /// centre is inside the shape and its box area is between
  /// [DetectorTuning.targetFillMin] and [DetectorTuning.targetFillMax] of
  /// the zone's bounding-rect area.
  FaceGuidance? issueFor(FaceSnapshot face, DetectorTuning tuning) {
    final zoneArea = rect.width * rect.height;
    if (zoneArea <= 0) return FaceGuidance.notCentered;
    final fill = face.area / zoneArea;
    if (fill < tuning.targetFillMin) return FaceGuidance.tooFar;
    if (fill > tuning.targetFillMax) return FaceGuidance.tooClose;
    if (!contains(face.boundingBox.center)) return FaceGuidance.notCentered;
    return null;
  }
}
