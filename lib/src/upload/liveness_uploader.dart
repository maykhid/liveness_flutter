import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/models.dart';

/// Signature for delivering a [LivenessResult] to your backend — any
/// transport: REST, dio, gRPC, presigned S3, Firebase, a local queue, etc.
typedef LivenessUploadFn = Future<void> Function(LivenessResult result);

/// Strategy interface for delivering results. You almost never need to
/// implement this: pass any async function via [LivenessUploader.custom],
/// or use [HttpLivenessUploader] for the common multipart-POST case.
///
/// Note the package never *requires* an uploader — `onResult` always hands
/// you the raw result and you can do delivery entirely yourself.
abstract class LivenessUploader {
  const LivenessUploader();

  /// Wrap any async function as an uploader.
  ///
  /// ```dart
  /// final uploader = LivenessUploader.custom((result) async {
  ///   await dio.post('/liveness', data: FormData.fromMap({...}));
  /// });
  /// ```
  const factory LivenessUploader.custom(LivenessUploadFn fn) =
      _FunctionUploader;

  Future<void> upload(LivenessResult result);
}

class _FunctionUploader extends LivenessUploader {
  const _FunctionUploader(this._fn);
  final LivenessUploadFn _fn;

  @override
  Future<void> upload(LivenessResult result) => _fn(result);
}

/// Built-in uploader for the common case: multipart-POST to an endpoint.
class HttpLivenessUploader extends LivenessUploader {
  const HttpLivenessUploader({
    required this.endpoint,
    this.headers = const {},
    this.imageFieldName = 'images',
    this.frameFieldName = 'frames',
    this.videoFieldName = 'video',
    this.metadataFieldName = 'metadata',
    this.onResponse,
    this.onProgress,
  });

  final Uri endpoint;

  /// e.g. `{'Authorization': 'Bearer …'}`
  final Map<String, String> headers;

  final String imageFieldName;
  final String frameFieldName;
  final String videoFieldName;
  final String metadataFieldName;

  /// Inspect the server response (status code, body) if you care about it.
  final Future<void> Function(http.StreamedResponse response)? onResponse;

  /// Called as the request body is sent — drive a progress bar with
  /// `sentBytes / totalBytes`. Liveness payloads can be several MB, so
  /// showing progress is strongly recommended (see README).
  ///
  /// Note: reports bytes handed to the network stack; on fast connections
  /// it may reach 100% slightly before the server finishes reading.
  final void Function(int sentBytes, int totalBytes)? onProgress;

  /// Sends:
  /// - `metadata` field: JSON with success, actions, timings
  /// - `images[i]` files: JPEG per captured frame (filename encodes action)
  /// - `frames[i]` files: frame-sequence JPEGs (filename encodes timestamp)
  /// - `video` file: the session recording, if any
  @override
  Future<void> upload(LivenessResult result) async {
    final request =
        _ProgressMultipartRequest('POST', endpoint, onProgress: onProgress)
          ..headers.addAll(headers);

    request.fields[metadataFieldName] = jsonEncode({
      'success': result.success,
      'completedActions':
          result.completedActions.map((a) => a.name).toList(),
      'failureReason': result.failureReason?.name,
      'startedAt': result.startedAt.toIso8601String(),
      'finishedAt': result.finishedAt.toIso8601String(),
      'durationMs': result.duration.inMilliseconds,
      ...result.metadata,
    });

    for (var i = 0; i < result.images.length; i++) {
      final image = result.images[i];
      request.files.add(http.MultipartFile.fromBytes(
        '$imageFieldName[$i]',
        image.bytes,
        filename: '${image.action?.name ?? 'reference'}_$i.jpg',
      ));
    }

    // Frame sequence: filename encodes the session timestamp so the backend
    // can reassemble a video (see README for the ffmpeg one-liner).
    for (var i = 0; i < result.frameSequence.length; i++) {
      final f = result.frameSequence[i];
      request.files.add(http.MultipartFile.fromBytes(
        '$frameFieldName[$i]',
        f.bytes,
        filename:
            'frame_${i.toString().padLeft(4, '0')}_${f.timestampMs}ms.jpg',
      ));
    }

    final videoPath = result.videoPath;
    if (videoPath != null && File(videoPath).existsSync()) {
      request.files.add(
        await http.MultipartFile.fromPath(videoFieldName, videoPath),
      );
    }

    final response = await request.send();
    await onResponse?.call(response);
  }
}

/// MultipartRequest that reports bytes as they're written to the wire.
class _ProgressMultipartRequest extends http.MultipartRequest {
  _ProgressMultipartRequest(super.method, super.url, {this.onProgress});

  final void Function(int sent, int total)? onProgress;

  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();
    final progress = onProgress;
    if (progress == null) return byteStream;

    final total = contentLength;
    var sent = 0;
    final transformer = StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (data, sink) {
        sent += data.length;
        progress(sent, total);
        sink.add(data);
      },
    );
    return http.ByteStream(byteStream.transform(transformer));
  }
}
