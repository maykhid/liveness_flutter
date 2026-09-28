import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

/// Thrown by [HttpLivenessUploader.upload] when the server answers with a
/// non-2xx status (after any retries).
class LivenessUploadException implements Exception {
  const LivenessUploadException(this.statusCode, this.body);

  final int statusCode;

  /// Response body, decoded as UTF-8 (malformed bytes replaced).
  final String body;

  @override
  String toString() => 'LivenessUploadException: HTTP $statusCode'
      '${body.isEmpty ? '' : ' — ${body.length > 200 ? '${body.substring(0, 200)}…' : body}'}';
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
    this.client,
    this.timeout = const Duration(seconds: 60),
    this.maxRetries = 0,
    this.retryDelay = const Duration(seconds: 1),
  });

  final Uri endpoint;

  /// e.g. `{'Authorization': 'Bearer …'}`
  final Map<String, String> headers;

  final String imageFieldName;
  final String frameFieldName;
  final String videoFieldName;
  final String metadataFieldName;

  /// Inspect the final server response (status code, body). Called for
  /// error statuses too, before [upload] throws; not called for 5xx
  /// responses that are retried.
  final Future<void> Function(http.StreamedResponse response)? onResponse;

  /// Called as the request body is sent — drive a progress bar with
  /// `sentBytes / totalBytes`. Liveness payloads can be several MB, so
  /// showing progress is strongly recommended (see README).
  ///
  /// Note: reports bytes handed to the network stack; on fast connections
  /// it may reach 100% slightly before the server finishes reading.
  final void Function(int sentBytes, int totalBytes)? onProgress;

  /// HTTP client to send with (e.g. a `MockClient` in tests, or your app's
  /// configured client). When null, a fresh client is created and closed
  /// per upload.
  final http.Client? client;

  /// Limit for each attempt: sending the request and reading the response.
  /// A timed-out attempt throws [TimeoutException] (or is retried).
  final Duration timeout;

  /// Extra attempts after a network error, a timeout, or a 5xx response.
  /// 4xx responses are never retried.
  final int maxRetries;

  /// Wait before the first retry; doubles on each later one.
  final Duration retryDelay;

  /// Sends:
  /// - `metadata` field: [LivenessResult.toJson] (sessionId,
  ///   confidenceScore, success, actions, timings, and the diagnostics under
  ///   `metadata`)
  /// - `images[i]` files: JPEG per captured frame, named
  ///   `<action>_<kind>_<timestampMs>ms.jpg` (or `reference_<t>ms.jpg`)
  /// - `frames[i]` files: frame-sequence JPEGs (filename encodes timestamp)
  /// - `video` file: the session recording, if any
  /// - `X-Liveness-Session` header: the session ID
  ///
  /// Throws [LivenessUploadException] for a non-2xx response and
  /// [TimeoutException] when an attempt exceeds [timeout], once
  /// [maxRetries] are used up. Network errors are rethrown as-is.
  @override
  Future<void> upload(LivenessResult result) async {
    final client = this.client ?? http.Client();
    try {
      for (var attempt = 0;; attempt++) {
        final canRetry = attempt < maxRetries;
        final http.StreamedResponse streamed;
        final Uint8List bytes;
        try {
          // A multipart request can only be sent once: rebuild per attempt.
          final request = await _buildRequest(result);
          streamed = await client.send(request).timeout(timeout);
          bytes = await streamed.stream.toBytes().timeout(timeout);
        } catch (e) {
          if (canRetry && _isRetryable(e)) {
            await Future<void>.delayed(retryDelay * (1 << attempt));
            continue;
          }
          rethrow;
        }

        final status = streamed.statusCode;
        if (status >= 500 && canRetry) {
          await Future<void>.delayed(retryDelay * (1 << attempt));
          continue;
        }
        await onResponse?.call(http.StreamedResponse(
          http.ByteStream.fromBytes(bytes),
          status,
          contentLength: bytes.length,
          request: streamed.request,
          headers: streamed.headers,
          isRedirect: streamed.isRedirect,
          persistentConnection: streamed.persistentConnection,
          reasonPhrase: streamed.reasonPhrase,
        ));
        if (status < 200 || status >= 300) {
          throw LivenessUploadException(
            status,
            utf8.decode(bytes, allowMalformed: true),
          );
        }
        return;
      }
    } finally {
      if (this.client == null) client.close();
    }
  }

  static bool _isRetryable(Object error) =>
      error is TimeoutException ||
      error is http.ClientException ||
      error is SocketException;

  Future<http.BaseRequest> _buildRequest(LivenessResult result) async {
    final request =
        _ProgressMultipartRequest('POST', endpoint, onProgress: onProgress)
          ..headers.addAll(headers)
          ..headers['X-Liveness-Session'] = result.sessionId;

    request.fields[metadataFieldName] = jsonEncode(result.toJson());

    for (var i = 0; i < result.images.length; i++) {
      final image = result.images[i];
      request.files.add(http.MultipartFile.fromBytes(
        '$imageFieldName[$i]',
        image.bytes,
        filename: _imageFileName(image),
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

    return request;
  }
}

/// File name used for a captured image: `<action>_<kind>_<t>ms.jpg`, or
/// `reference_<t>ms.jpg` for the neutral reference shot.
String _imageFileName(CapturedImage image) {
  final action = image.action;
  return action == null
      ? 'reference_${image.timestampMs}ms.jpg'
      : '${action.name}_${image.kind.name}_${image.timestampMs}ms.jpg';
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
