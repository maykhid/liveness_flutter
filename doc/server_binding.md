# Bind sessions to your server

*You need this if* a passing result unlocks anything valuable. On its own,
the phone's verdict is unsigned: your server can't tell which actions it
expected or whether the result was edited. Three hooks fix that:

- **`LivenessConfig.challenge`**: your server issues a `LivenessChallenge`
  (single-use nonce, the actions in its chosen order, an expiry). The
  session runs exactly that order and echoes the nonce in
  `result.nonce`. An expired challenge fails with `challengeExpired`.
- **Image hashes**: `result.toJson()` (and so `result.evidenceJson`, the
  uploader's `metadata`) lists the SHA-256 of every photo and frame, so
  the server can prove the files weren't swapped.
- **`LivenessConfig.attestor`**: plug in Play Integrity or App Attest
  through the `LivenessAttestor` interface. It signs a hash of
  `sessionId|nonce|success|actions|image hashes|sha256(evidenceJson)`,
  so every field the server gets is covered; the token lands in
  `result.attestation`. The platform code lives in your app; see
  [Writing an attestor](server_verification.md#3a-writing-an-attestor)
  for a Dart template, Android and iOS snippets and the server checks.
  Treat a missing attestation as "send to review", not as a pass.

## Why the attestor matters

The challenge and hashes prove the upload is consistent, not where it
came from. Anyone who reads these docs can write a script that asks your
server for a challenge, skips the camera, and uploads someone else's
photos with `success: true`, the right nonce and matching hashes. Every
other check passes. An attestor closes that gap: Google (Play Integrity)
or Apple (App Attest) signs the session's hash only for your genuine,
unmodified app on a real device, so a script, an emulator or a tampered
build can't produce a valid token. It also blocks most fake-camera
attacks, which need a rooted or modified phone.

Without a server challenge, `randomActionCount: 3` makes each session
pick 3 actions at random from your list *and* shuffle them — from all 13
actions that's 1,716 possible sequences instead of 6.

The **[server verification guide](server_verification.md)** covers what
your backend should check, with a payload-rebuild snippet. Working client
code: the
[server-bound recipe](https://github.com/maykhid/liveness_flutter/blob/main/example/lib/recipes/server_bound.dart).

## Bring your own anti-spoof model

Optional. The package bundles no ML model, but
`LivenessConfig.frameAnalyzers` lets you plug one in (a TFLite/ONNX
presentation-attack detector, or a cloud call):

```dart
class MyPadModel extends LivenessFrameAnalyzer {
  @override
  String get id => 'pad-v2';

  @override
  Future<double?> analyze(LivenessFrame frame) async {
    // frame.jpeg: the upright full frame; frame.faceBox: the face (0..1).
    return myModel.spoofProbability(frame.jpeg, frame.faceBox); // 0–1
  }
}
```

It runs on the reference frame and on each action's evidence frame. Scores
land in `metadata['analyzers']['pad-v2']` and lower `confidenceScore` by
`analyzerWeight` (default 0.5) × the mean spoof probability.

## Uploads, in more detail

A non-2xx answer throws `LivenessUploadException(statusCode, body)`; each
attempt is limited by `timeout` (default 60 s); set `maxRetries` to retry
network errors, timeouts and 5xx with exponential backoff (4xx is never
retried). The basic upload is in
[getting started](getting_started.md#4-send-it-to-your-server).
