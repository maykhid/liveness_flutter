# Sending results to a backend, and binding sessions to it

The package never uploads anything by itself. `onResult` hands you the
`LivenessResult`; what happens next is your code. For anything a pass
unlocks, the full chain is:

1. The server issues a challenge (nonce, actions, expiry).
2. The app runs exactly that challenge and captures images.
3. The app uploads the result and its photos.
4. The server verifies the upload (nonce, order, hashes, attestation),
   then judges the face itself (face match, server-side anti-spoofing).

Steps 1 and 4 are server work; the `liveness-flutter-server` skill (or
the package's `doc/server_verification.md`) covers them.

## Uploading with `HttpLivenessUploader`

A multipart POST with progress, timeouts and retries:

| Parameter | Default | Notes |
|---|---|---|
| `endpoint` | required | `Uri`. |
| `headers` | `{}` | e.g. `{'Authorization': 'Bearer $token'}`. |
| `onProgress` | null | `(sentBytes, totalBytes)`. Uploads with photos can be several MB, so show progress. |
| `onResponse` | null | Sees the final response, including error statuses. |
| `timeout` | 60 s | Per attempt. |
| `maxRetries` | 0 | Retries network errors, timeouts and 5xx with exponential backoff. 4xx is never retried. |
| `retryDelay` | 1 s | Doubles each retry. |
| `client` | null | Your own `http.Client` (or a `MockClient` in tests). |
| `imageFieldName`, `frameFieldName`, `videoFieldName`, `metadataFieldName` | `images`, `frames`, `video`, `metadata` | Rename the multipart parts. |

What it sends: an `X-Liveness-Session` header with the session ID; a
`metadata` field with `jsonEncode(result.toJson())`; `images[i]` files
named `<action>_<kind>_<t>ms.jpg` (or `reference_<t>ms.jpg`); `frames[i]`
files; a `video` file if recorded. It throws `LivenessUploadException`
(`statusCode`, `body`) on a non-2xx answer and `TimeoutException` once
retries run out. Other network errors are rethrown as they are.

Upload from the screen that opened the check, after the camera screen
has closed, with a progress bar:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

class VerifyButton extends StatefulWidget {
  const VerifyButton({
    super.key,
    required this.openLivenessPage,
    required this.endpoint,
    required this.authToken,
  });

  /// Pushes the liveness page and returns its result (null on system back).
  final Future<LivenessResult?> Function(BuildContext context) openLivenessPage;
  final Uri endpoint;
  final String authToken;

  @override
  State<VerifyButton> createState() => _VerifyButtonState();
}

class _VerifyButtonState extends State<VerifyButton> {
  final _progress = ValueNotifier<double?>(null);
  String? _message;

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final result = await widget.openLivenessPage(context);
    if (result == null || !result.success) {
      setState(() => _message = result == null ? null : 'Not verified');
      return;
    }
    _progress.value = 0;
    try {
      await HttpLivenessUploader(
        endpoint: widget.endpoint,
        headers: {'Authorization': 'Bearer ${widget.authToken}'},
        maxRetries: 2,
        onProgress: (sent, total) => _progress.value = sent / total,
      ).upload(result);
      _message = 'Submitted. We will confirm shortly.';
    } on LivenessUploadException catch (e) {
      _message = 'The server refused it (HTTP ${e.statusCode}).';
    } on TimeoutException {
      _message = 'The upload timed out. Check your connection.';
    } catch (e) {
      _message = 'The upload failed.';
    } finally {
      _progress.value = null;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<double?>(
          valueListenable: _progress,
          builder: (context, value, _) => value == null
              ? FilledButton(onPressed: _verify, child: const Text('Verify'))
              : LinearProgressIndicator(value: value),
        ),
        if (_message != null) Text(_message!),
      ],
    );
  }
}
```

Whether to upload failed sessions too is a product decision; uploading
them gives the server fraud signals.

## Any other transport: `LivenessUploader.custom`

Wrap dio, a presigned S3 URL, Firebase Storage, a local queue, anything:

```dart
import 'dart:convert';

import 'package:liveness_flutter/liveness_flutter.dart';

LivenessUploader queuedUploader(
  Future<void> Function(String name, List<int> bytes) putFile,
  Future<void> Function(Map<String, Object?> json) postMetadata,
) {
  return LivenessUploader.custom((result) async {
    for (final image in result.images) {
      final name = image.action == null
          ? 'reference_${image.timestampMs}ms.jpg'
          : '${image.action!.name}_${image.kind.name}_${image.timestampMs}ms.jpg';
      await putFile(name, image.bytes);
    }
    // Send toJson() unchanged: it carries the nonce, the order and the
    // SHA-256 of every photo, which the server checks.
    await postMetadata(
      jsonDecode(jsonEncode(result.toJson())) as Map<String, Object?>,
    );
  });
}
```

Keep `toJson()` intact whatever the transport, and send the files'
bytes unmodified (no re-encoding or resizing), or their hashes stop
matching.

Video: `result.videoPath` is a temp file. Upload or copy it in or right
after `onResult`, then delete it or set `autoDeleteVideo: true`.

## Server challenges: `LivenessChallenge`

Fetch a challenge before opening the screen and pass it in the config:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:liveness_flutter/liveness_flutter.dart';

/// Expects {"nonce": "...", "actions": ["blink", "lookLeft"],
/// "expiresAt": "2026-10-26T12:05:00Z"}.
Future<LivenessChallenge> fetchChallenge(Uri url, String token) async {
  final response = await http.post(
    url,
    headers: {'Authorization': 'Bearer $token'},
  ).timeout(const Duration(seconds: 15));
  if (response.statusCode != 200) {
    throw Exception('Challenge request failed: HTTP ${response.statusCode}');
  }
  final json = jsonDecode(response.body) as Map<String, dynamic>;
  return LivenessChallenge(
    nonce: json['nonce'] as String,
    actions: [
      for (final name in json['actions'] as List)
        LivenessAction.values.byName(name as String),
    ],
    expiresAt: DateTime.parse(json['expiresAt'] as String),
  );
}

LivenessConfig serverBoundConfig(LivenessChallenge challenge) {
  return LivenessConfig(
    actions: const [], // the challenge decides the actions and order
    challenge: challenge,
    capture: const {CaptureType.images},
  );
}
```

`http` here is the app's own dependency; add it to `pubspec.yaml` if the
app doesn't have it. `LivenessAction.values.byName` throws on an unknown
name, so keep the server's action names in step with the package version.

Behaviour: the session runs the challenge's actions in its order (no
shuffle, `randomActionCount` ignored), `result.nonce` echoes the nonce,
and a challenge past `expiresAt` fails with `challengeExpired`, checked
at the start and at the end. Fetch a new challenge for every attempt,
including "Try again": a nonce is single use on the server. A restart
runs with whatever config the widget has at that moment, so fetch a new
challenge, rebuild `LivenessDetector` with it, and then call
`LivenessController.restart()` (or give the detector a new `key`).
Restarting without a new challenge reuses the spent nonce, and the server
will reject that session.

## Attestation: `LivenessAttestor`

The challenge and hashes prove the upload is consistent, not that it came
from your app: a script can request a challenge, skip the camera and
upload any photos with matching hashes. An attestor closes that: Google
Play Integrity or Apple App Attest signs the session's hash only for the
genuine app on a real device.

The package defines the hook; the platform code lives in the app because
it is tied to the developer's Google Play and Apple accounts. Subclass
with `extends` (since 0.6.0 the class has a `prepare()` method with a
default body; `implements` must add it).

```dart
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

class PlatformAttestor extends LivenessAttestor {
  PlatformAttestor({required this.cloudProjectNumber});

  static const _channel = MethodChannel('myapp/attestation');

  /// Google Cloud project number (Android only).
  final int cloudProjectNumber;

  Future<void>? _ready;

  /// Called when the screen opens, not awaited. Warm up Play Integrity or
  /// register the App Attest key here so attest() is quick. Must be safe
  /// to call again (a restart calls it again).
  @override
  Future<void> prepare() => _ready ??= _channel
          .invokeMethod<void>(
              'prepare', {'cloudProjectNumber': cloudProjectNumber})
          .catchError((Object e) {
        _ready = null; // let attest() try again
        throw e;
      });

  /// Gets the SHA-256 of result.attestationPayload. 15-second limit.
  @override
  Future<String> attest(Uint8List payloadHash) async {
    await prepare();
    final token = await _channel.invokeMapMethod<String, Object?>(
      'attest',
      {'hash': payloadHash},
    );
    return jsonEncode(token);
  }
}
```

Use it with `LivenessConfig(attestor: PlatformAttestor(...), ...)`. The
token lands in `result.attestation`. If `attest()` throws or times out,
`attestation` is null and `metadata['attestationError']` says why; the
result is never blocked.

The native halves (a Kotlin handler for Play Integrity, Swift for App
Attest), the account setup and the server checks are in the package's
`doc/server_verification.md`, section "Writing an attestor". Read it from
the installed package (see `.dart_tool/package_config.json`) before
writing the native code. Key facts: Play Integrity needs the app
installed from Google Play (internal testing is enough) and a linked
Cloud project; App Attest needs the App Attest capability and doesn't run
on the simulator.

The signed string is
`sessionId|nonce|success|action,action,…|sha256,sha256,…` (images then
frames, nonce empty when absent); `result.attestationPayload` and
`result.attestationPayloadHash` give it to you in Dart.

## Your own anti-spoof model: `LivenessFrameAnalyzer`

The package ships no ML model. To add presentation-attack detection
(a TFLite or ONNX model, or a cloud call):

```dart
import 'dart:ui' show Rect;

import 'package:liveness_flutter/liveness_flutter.dart';

class PadModelAnalyzer extends LivenessFrameAnalyzer {
  PadModelAnalyzer(this.spoofProbability);

  /// Your model: JPEG bytes and the face box (0..1) in, 0 to 1 out.
  final Future<double> Function(List<int> jpeg, Rect faceBox)
      spoofProbability;

  @override
  String get id => 'pad-v1';

  @override
  Future<double?> analyze(LivenessFrame frame) async {
    final box = frame.faceBox;
    if (box == null) return null; // no face on this frame: can't judge it
    return spoofProbability(frame.jpeg, box);
  }
}
```

It runs on the reference frame and each action's evidence frame, whether
or not photos are captured. `frame.jpeg` is the upright full frame and
`frame.faceBox` the face's box normalised to it; many models want the box
enlarged before cropping. Return null when a frame can't be judged;
thrown errors are counted, never shown to the user. Scores go to
`metadata['analyzers'][id]` (`scores`, `mean`, `max`, `errors`) and lower
`confidenceScore` by `analyzerWeight` (default 0.5) times the highest mean
spoof probability. `id`s must be unique. Analyses still running 5 s after
the session ends are dropped.
