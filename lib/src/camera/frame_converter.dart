import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// Pixel layout of a [RawFrame].
enum RawFrameFormat { nv21, bgra8888, nv12 }

/// Sendable payload for [encodeRawFrame].
class EncodeRequest {
  const EncodeRequest(this.frame, {this.maxDimension = 720, this.quality = 85});

  final RawFrame frame;
  final int maxDimension;
  final int quality;
}

/// Top-level entry point for `compute`/`Isolate.run`. Being top-level (not a
/// lambda inside widget code) guarantees the isolate message contains only
/// [EncodeRequest] — no accidental capture of camera/widget state, which is
/// unsendable and would make the isolate spawn throw.
Uint8List? encodeRawFrame(EncodeRequest request) =>
    FrameConverter.rawFrameToJpeg(
      request.frame,
      maxDimension: request.maxDimension,
      quality: request.quality,
    );

/// A copied, isolate-sendable snapshot of one camera frame. Safe to pass to
/// `Isolate.run` for background JPEG encoding.
class RawFrame {
  const RawFrame({
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.format,
    required this.planes,
    required this.strides,
  });

  final int width;
  final int height;

  /// Clockwise rotation needed to make the image upright.
  final int rotationDegrees;
  final RawFrameFormat format;

  /// Copied plane bytes (1 plane for nv21/bgra, 2 for nv12).
  final List<Uint8List> planes;
  final List<int> strides;
}

/// Converts camera plugin frames to ML Kit [InputImage]s and to JPEG bytes.
class FrameConverter {
  FrameConverter({required this.camera, required this.controller});

  final CameraDescription camera;
  final CameraController controller;

  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Build an ML Kit [InputImage] from a streamed [CameraImage].
  /// Returns null for unsupported formats.
  InputImage? toInputImage(CameraImage image) {
    final rotation = _rotation();
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    // Android: NV21 (single plane). iOS: BGRA8888 (single plane).
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  InputImageRotation? _rotation() {
    final degrees = rotationDegrees();
    return degrees == null
        ? null
        : InputImageRotationValue.fromRawValue(degrees);
  }

  /// Clockwise degrees (0/90/180/270) to make the buffer upright.
  int? rotationDegrees() {
    final sensorOrientation = camera.sensorOrientation;
    if (Platform.isIOS) return sensorOrientation;
    // Android
    final rotationCompensation =
        _orientations[controller.value.deviceOrientation];
    if (rotationCompensation == null) return null;
    if (camera.lensDirection == CameraLensDirection.front) {
      return (sensorOrientation + rotationCompensation) % 360;
    }
    return (sensorOrientation - rotationCompensation + 360) % 360;
  }

  /// Copy a [CameraImage] into an isolate-sendable [RawFrame].
  /// Cheap (a memcpy); do the expensive [rawFrameToJpeg] off-thread.
  RawFrame? toRaw(CameraImage image) {
    final degrees = rotationDegrees();
    if (degrees == null || image.planes.isEmpty) return null;

    RawFrameFormat format;
    if (Platform.isAndroid) {
      format = RawFrameFormat.nv21;
    } else if (image.planes.length >= 2) {
      format = RawFrameFormat.nv12;
    } else {
      format = RawFrameFormat.bgra8888;
    }

    final planeCount = format == RawFrameFormat.nv12 ? 2 : 1;
    return RawFrame(
      width: image.width,
      height: image.height,
      rotationDegrees: degrees,
      format: format,
      planes: [
        for (var i = 0; i < planeCount; i++)
          Uint8List.fromList(image.planes[i].bytes),
      ],
      strides: [
        for (var i = 0; i < planeCount; i++)
          image.planes[i].bytesPerRow > 0
              ? image.planes[i].bytesPerRow
              : image.width,
      ],
    );
  }

  /// Convert a streamed [CameraImage] to upright JPEG bytes on the current
  /// thread. Prefer `Isolate.run(() => FrameConverter.rawFrameToJpeg(raw))`
  /// with [toRaw] for anything captured more than once per action.
  Uint8List? toJpeg(CameraImage image,
      {int maxDimension = 720, int quality = 85}) {
    final raw = toRaw(image);
    if (raw == null) return null;
    return rawFrameToJpeg(raw, maxDimension: maxDimension, quality: quality);
  }

  /// Pure function: decode, rotate upright, downscale, JPEG-encode.
  /// Static and dependency-free so it can run in a background isolate.
  static Uint8List? rawFrameToJpeg(
    RawFrame raw, {
    int maxDimension = 720,
    int quality = 85,
  }) {
    img.Image? decoded;
    switch (raw.format) {
      case RawFrameFormat.nv21:
        decoded = _nv21ToImage(raw);
      case RawFrameFormat.nv12:
        decoded = _nv12ToImage(raw);
      case RawFrameFormat.bgra8888:
        decoded = _bgraToImage(raw);
    }
    if (decoded == null) return null;

    switch (raw.rotationDegrees) {
      case 90:
        decoded = img.copyRotate(decoded, angle: 90);
      case 180:
        decoded = img.copyRotate(decoded, angle: 180);
      case 270:
        decoded = img.copyRotate(decoded, angle: 270);
      default:
        break;
    }

    if (decoded.width > maxDimension || decoded.height > maxDimension) {
      decoded = decoded.width >= decoded.height
          ? img.copyResize(decoded, width: maxDimension)
          : img.copyResize(decoded, height: maxDimension);
    }

    return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
  }

  static img.Image? _bgraToImage(RawFrame raw) {
    final bytes = raw.planes.first;
    return img.Image.fromBytes(
      width: raw.width,
      height: raw.height,
      bytes: bytes.buffer,
      bytesOffset: bytes.offsetInBytes,
      rowStride: raw.strides.first,
      order: img.ChannelOrder.bgra,
    );
  }

  /// iOS bi-planar 420 (NV12): plane0 = Y, plane1 = interleaved UV.
  static img.Image? _nv12ToImage(RawFrame raw) {
    if (raw.planes.length < 2) return null;
    final yBytes = raw.planes[0];
    final uvBytes = raw.planes[1];
    final width = raw.width;
    final height = raw.height;
    final yStride = raw.strides[0];
    final uvStride = raw.strides[1];
    final out = img.Image(width: width, height: height);

    for (var y = 0; y < height; y++) {
      final uvRow = (y >> 1) * uvStride;
      for (var x = 0; x < width; x++) {
        final yIndex = y * yStride + x;
        final uvIndex = uvRow + (x & ~1);
        if (yIndex >= yBytes.length || uvIndex + 1 >= uvBytes.length) {
          continue;
        }
        _setYuvPixel(out, x, y, yBytes[yIndex], uvBytes[uvIndex] - 128,
            uvBytes[uvIndex + 1] - 128);
      }
    }
    return out;
  }

  /// Android NV21: single buffer, Y plane then interleaved VU.
  static img.Image? _nv21ToImage(RawFrame raw) {
    final bytes = raw.planes.first;
    final width = raw.width;
    final height = raw.height;
    final stride = raw.strides.first;
    final out = img.Image(width: width, height: height);
    final uvStart = stride * height;

    for (var y = 0; y < height; y++) {
      final uvRow = uvStart + (y >> 1) * stride;
      for (var x = 0; x < width; x++) {
        final yIndex = y * stride + x;
        final uvIndex = uvRow + (x & ~1);
        if (yIndex >= bytes.length || uvIndex + 1 >= bytes.length) continue;
        // NV21 interleaves V then U.
        _setYuvPixel(out, x, y, bytes[yIndex], bytes[uvIndex + 1] - 128,
            bytes[uvIndex] - 128);
      }
    }
    return out;
  }

  static void _setYuvPixel(
      img.Image out, int x, int y, int yValue, int u, int v) {
    final r = yValue + 1.402 * v;
    final g = yValue - 0.344136 * u - 0.714136 * v;
    final b = yValue + 1.772 * u;
    out.setPixelRgb(
      x,
      y,
      r.clamp(0, 255).toInt(),
      g.clamp(0, 255).toInt(),
      b.clamp(0, 255).toInt(),
    );
  }
}
