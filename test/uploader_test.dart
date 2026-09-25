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
}
