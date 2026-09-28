import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

LivenessResult sampleResult() => LivenessResult(
      success: true,
      completedActions: const [LivenessAction.blink],
      images: [
        CapturedImage(
          bytes: Uint8List.fromList([1, 2, 3]),
          action: null,
          timestampMs: 120,
          kind: CaptureKind.reference,
        ),
        CapturedImage(
          bytes: Uint8List.fromList([4, 5, 6]),
          action: LivenessAction.blink,
          timestampMs: 812,
          kind: CaptureKind.peak,
        ),
      ],
      startedAt: DateTime.utc(2026, 1, 1, 12),
      finishedAt: DateTime.utc(2026, 1, 1, 12, 0, 5),
      confidenceScore: 0.93,
      sessionId: 'LV-0000000000AB-12345678',
      metadata: const {'blink_ms': 640},
    );

/// Captures what an upload sent.
class Captured {
  http.Request? request;
  String get body => utf8.decode(request!.bodyBytes, allowMalformed: true);

  /// The JSON in the multipart `metadata` field.
  Map<String, Object?> get metadata {
    final match = RegExp(
      r'name="metadata"\r\n\r\n(.*?)\r\n--',
      dotAll: true,
    ).firstMatch(body);
    return jsonDecode(match!.group(1)!) as Map<String, Object?>;
  }
}

void main() {
  group('U1 HttpLivenessUploader sends the full result', () {
    late Captured captured;
    late HttpLivenessUploader uploader;

    setUp(() async {
      captured = Captured();
      uploader = HttpLivenessUploader(
        endpoint: Uri.parse('https://api.example.com/liveness'),
        headers: const {'Authorization': 'Bearer t'},
        client: MockClient((request) async {
          captured.request = request;
          return http.Response('{}', 200);
        }),
      );
      await uploader.upload(sampleResult());
    });

    test('metadata contains sessionId and confidenceScore', () {
      final m = captured.metadata;
      expect(m['sessionId'], 'LV-0000000000AB-12345678');
      expect(m['confidenceScore'], 0.93);
      expect(m['success'], true);
      expect(m['completedActions'], ['blink']);
      expect((m['metadata'] as Map)['blink_ms'], 640);
    });

    test('image file names carry action, kind and timestamp', () {
      expect(captured.body, contains('filename="reference_120ms.jpg"'));
      expect(captured.body, contains('filename="blink_peak_812ms.jpg"'));
    });

    test('sends X-Liveness-Session and keeps caller headers', () {
      final headers = captured.request!.headers;
      expect(headers['X-Liveness-Session'], 'LV-0000000000AB-12345678');
      expect(headers['Authorization'], 'Bearer t');
    });
  });

  group('U2 HTTP errors, timeout and retries', () {
    HttpLivenessUploader uploader(
      MockClientHandler handler, {
      int maxRetries = 0,
      Duration timeout = const Duration(seconds: 5),
      Future<void> Function(http.StreamedResponse)? onResponse,
    }) =>
        HttpLivenessUploader(
          endpoint: Uri.parse('https://api.example.com/liveness'),
          client: MockClient(handler),
          maxRetries: maxRetries,
          timeout: timeout,
          retryDelay: Duration.zero,
          onResponse: onResponse,
        );

    test('HTTP 500 throws LivenessUploadException with status and body',
        () async {
      final seen = <int>[];
      final u = uploader(
        (_) async => http.Response('boom', 500),
        onResponse: (r) async => seen.add(r.statusCode),
      );
      await expectLater(
        u.upload(sampleResult()),
        throwsA(isA<LivenessUploadException>()
            .having((e) => e.statusCode, 'statusCode', 500)
            .having((e) => e.body, 'body', 'boom')),
      );
      expect(seen, [500], reason: 'onResponse still sees the final response');
    });

    test('onResponse can read the body on success', () async {
      String? body;
      await uploader(
        (_) async => http.Response('{"ok":true}', 201),
        onResponse: (r) async => body = await r.stream.bytesToString(),
      ).upload(sampleResult());
      expect(body, '{"ok":true}');
    });

    test('an attempt that exceeds timeout throws TimeoutException', () async {
      final u = uploader(
        (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return http.Response('late', 200);
        },
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
          u.upload(sampleResult()), throwsA(isA<TimeoutException>()));
    });

    test('5xx is retried maxRetries times, then throws', () async {
      var calls = 0;
      final u = uploader((_) async {
        calls++;
        return http.Response('unavailable', 503);
      }, maxRetries: 2);
      await expectLater(u.upload(sampleResult()),
          throwsA(isA<LivenessUploadException>()));
      expect(calls, 3);
    });

    test('a retry that succeeds completes normally', () async {
      var calls = 0;
      await uploader((_) async {
        calls++;
        return calls < 3
            ? http.Response('unavailable', 503)
            : http.Response('ok', 200);
      }, maxRetries: 2)
          .upload(sampleResult());
      expect(calls, 3);
    });

    test('network errors are retried', () async {
      var calls = 0;
      await uploader((_) async {
        calls++;
        if (calls == 1) throw http.ClientException('connection reset');
        return http.Response('ok', 200);
      }, maxRetries: 1)
          .upload(sampleResult());
      expect(calls, 2);
    });

    test('4xx is not retried', () async {
      var calls = 0;
      final u = uploader((_) async {
        calls++;
        return http.Response('bad', 422);
      }, maxRetries: 3);
      await expectLater(u.upload(sampleResult()),
          throwsA(isA<LivenessUploadException>()));
      expect(calls, 1);
    });

    test('default maxRetries is 0', () async {
      var calls = 0;
      final u = uploader((_) async {
        calls++;
        return http.Response('x', 500);
      });
      await expectLater(u.upload(sampleResult()), throwsA(anything));
      expect(calls, 1);
    });
  });
}
