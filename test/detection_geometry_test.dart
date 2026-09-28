
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';
import 'package:liveness_flutter/src/camera/detection_geometry.dart';

Matcher near(Offset o) => predicate<Offset>(
      (p) => (p.dx - o.dx).abs() < 1e-9 && (p.dy - o.dy).abs() < 1e-9,
      'near $o',
    );

void main() {
  const portraitView = Size(720, 1280);

  group('C3 DetectionGeometry', () {
    test('same aspect, rotation 0, back camera: identity', () {
      const g = DetectionGeometry(
        viewSize: portraitView,
        faceSpaceSize: Size(720, 1280),
        rotationDegrees: 0,
        mirrored: false,
      );
      expect(g.viewToFace(const Offset(0.2, 0.7)), near(const Offset(0.2, 0.7)));
    });

    test('cover-fit crops the wider image horizontally', () {
      const g = DetectionGeometry(
        viewSize: Size(360, 780), // aspect 0.4615
        faceSpaceSize: Size(720, 1280), // aspect 0.5625
        rotationDegrees: 0,
        mirrored: false,
      );
      final visibleX = (360 / 780) / (720 / 1280);
      expect(g.viewToFace(const Offset(0, 0.5)),
          near(Offset(0.5 - 0.5 * visibleX, 0.5)));
      // Full height is visible.
      expect(g.viewToFace(const Offset(0.5, 0)).dy, closeTo(0, 1e-9));
    });

    test('cover-fit crops the taller image vertically', () {
      const g = DetectionGeometry(
        viewSize: Size(800, 1000), // aspect 0.8 (tablet)
        faceSpaceSize: Size(720, 1280),
        rotationDegrees: 0,
        mirrored: false,
      );
      final visibleY = (720 / 1280) / 0.8;
      expect(g.viewToFace(const Offset(0.5, 0)).dy, closeTo(0.5 - 0.5 * visibleY, 1e-9));
      expect(g.viewToFace(const Offset(0, 0.5)).dx, closeTo(0, 1e-9));
    });

    test('front camera: the preview is mirrored, so x flips', () {
      const g = DetectionGeometry(
        viewSize: portraitView,
        faceSpaceSize: Size(720, 1280),
        rotationDegrees: 270,
        mirrored: true,
      );
      expect(g.viewToFace(const Offset(0.2, 0.3)), near(const Offset(0.8, 0.3)));
    });

    test('rotation 90 with a raw landscape buffer (iOS-style)', () {
      const g = DetectionGeometry(
        viewSize: portraitView,
        faceSpaceSize: Size(1280, 720),
        rotationDegrees: 90,
        mirrored: false,
      );
      // Turning the buffer 90° clockwise puts its left edge on top.
      expect(g.viewToFace(const Offset(0.5, 0)), near(const Offset(0, 0.5)));
      expect(g.viewToFace(const Offset(1, 0.5)), near(const Offset(0.5, 0)));
      expect(g.displayedImageSize, const Size(720, 1280));
    });

    test('rotation 270 with a raw landscape buffer', () {
      const g = DetectionGeometry(
        viewSize: portraitView,
        faceSpaceSize: Size(1280, 720),
        rotationDegrees: 270,
        mirrored: false,
      );
      // Turning the buffer 270° clockwise puts its right edge on top.
      expect(g.viewToFace(const Offset(0.5, 0)), near(const Offset(1, 0.5)));
      expect(g.viewToFace(const Offset(0, 0.5)), near(const Offset(0.5, 0)));
    });

    test('rotation 90 with an already-upright buffer is not turned again',
        () {
      const g = DetectionGeometry(
        viewSize: portraitView,
        faceSpaceSize: Size(720, 1280),
        rotationDegrees: 90,
        mirrored: false,
      );
      expect(g.viewToFace(const Offset(0.3, 0.1)), near(const Offset(0.3, 0.1)));
    });

    for (final rotation in [0, 90, 270]) {
      for (final mirrored in [false, true]) {
        for (final faceSpace in [const Size(720, 1280), const Size(1280, 720)]) {
          test('round trip: rotation $rotation, '
              '${mirrored ? 'front' : 'back'}, face space $faceSpace', () {
            final g = DetectionGeometry(
              viewSize: const Size(360, 780),
              faceSpaceSize: faceSpace,
              rotationDegrees: rotation,
              mirrored: mirrored,
            );
            for (final p in const [
              Offset(0.1, 0.2),
              Offset(0.5, 0.44),
              Offset(0.9, 0.8),
            ]) {
              expect(g.faceToView(g.viewToFace(p)), near(p));
            }
          });
        }
      }
    }

    // The preview is drawn with BoxFit.cover in whatever space the detector
    // gets; detection must crop the camera image exactly the same way.
    for (final view in const [
      Size(390, 844), // full screen
      Size(390, 700), // under an app bar
      Size(800, 1000), // tablet
    ]) {
      test('agrees with BoxFit.cover in a $view view', () {
        const image = Size(720, 1280);
        final g = DetectionGeometry(
          viewSize: view,
          faceSpaceSize: image,
          rotationDegrees: 0,
          mirrored: false,
        );
        final fitted = applyBoxFit(BoxFit.cover, image, view);
        final visible = Alignment.center.inscribe(fitted.source, Offset.zero & image);
        final topLeft = g.viewToFace(Offset.zero);
        final bottomRight = g.viewToFace(const Offset(1, 1));
        expect(topLeft.dx * image.width, closeTo(visible.left, 0.01));
        expect(topLeft.dy * image.height, closeTo(visible.top, 0.01));
        expect(bottomRight.dx * image.width, closeTo(visible.right, 0.01));
        expect(bottomRight.dy * image.height, closeTo(visible.bottom, 0.01));
      });
    }

    test('front vs back differ only by the mirror', () {
      for (final rotation in [0, 90, 270]) {
        final back = DetectionGeometry(
          viewSize: portraitView,
          faceSpaceSize: const Size(1280, 720),
          rotationDegrees: rotation,
          mirrored: false,
        );
        final front = DetectionGeometry(
          viewSize: portraitView,
          faceSpaceSize: const Size(1280, 720),
          rotationDegrees: rotation,
          mirrored: true,
        );
        const p = Offset(0.25, 0.4);
        expect(front.viewToFace(p), near(back.viewToFace(const Offset(0.75, 0.4))),
            reason: 'rotation $rotation');
      }
    });
  });

  group('C3 TargetZone', () {
    FaceSnapshot faceIn(Rect box) =>
        FaceSnapshot(timestampMs: 0, boundingBox: box);
    const tuning = DetectorTuning();
    const zone = TargetZone(Rect.fromLTWH(0.2, 0.2, 0.6, 0.5), TargetShape.oval);

    test('in position: centred and filling the zone', () {
      expect(zone.issueFor(faceIn(const Rect.fromLTWH(0.3, 0.25, 0.4, 0.4)), tuning),
          isNull);
    });

    test('too far / too close use the fill ratio', () {
      expect(zone.issueFor(faceIn(const Rect.fromLTWH(0.45, 0.4, 0.1, 0.1)), tuning),
          FaceGuidance.tooFar);
      expect(zone.issueFor(faceIn(const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8)), tuning),
          FaceGuidance.tooClose);
    });

    test('a centre outside the oval is not centred', () {
      expect(
          zone.issueFor(faceIn(const Rect.fromLTWH(0.55, 0.05, 0.3, 0.3)), tuning),
          FaceGuidance.notCentered);
    });

    test('oval excludes corners a rounded rect includes', () {
      const corner = Offset(0.22, 0.22);
      expect(zone.contains(corner), isFalse);
      expect(
        const TargetZone(Rect.fromLTWH(0.2, 0.2, 0.6, 0.5), TargetShape.roundedRect)
            .contains(corner),
        isTrue,
      );
    });
  });
}
