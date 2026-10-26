# Setup and reading the result

## Install

```yaml
dependencies:
  liveness_flutter: ^0.6.0
```

Use the latest version from pub.dev if it is newer, and check its
CHANGELOG for breaking changes. Requirements: Flutter 3.38+ (Dart 3.10+),
Android API 24+, iOS 15.5+. No web or desktop support.

## Android

Set the minimum SDK to 24 in `android/app/build.gradle.kts`
(`minSdk = 24`) or `android/app/build.gradle` (`minSdkVersion 24`).
Recent Flutter templates use `flutter.minSdkVersion`; check what it
resolves to rather than assuming. Nothing else is required: the camera
plugin declares the camera permission.

## iOS

1. `ios/Runner/Info.plist`, inside `<dict>`. Without it the app crashes the
   first time the camera opens:

   ```xml
   <key>NSCameraUsageDescription</key>
   <string>Camera is used for liveness verification.</string>
   ```

   Write the text for the app's users; it appears in the permission
   prompt.

2. `ios/Podfile`: `platform :ios, '15.5'` (or higher). ML Kit face
   detection needs it; `pod install` fails below that.

## Permissions

No permission package is needed. The camera plugin asks the first time.
If the user refuses, the session ends with
`LivenessFailureReason.permissionDenied`. To show your own "allow camera
access" page inside the liveness screen instead of closing it, use
`permissionDeniedBuilder` (see [custom-ui.md](custom-ui.md)), and don't
pop the screen on a `permissionDenied` result in that case.

## Testing

Run on a physical phone. Simulators and emulators have no usable front
camera. Widget and unit tests have no camera either, so test your own
flow around the detector (navigation, upload, result handling) with a
hand-built `LivenessResult`:

```dart
import 'package:liveness_flutter/liveness_flutter.dart';

LivenessResult fakePassedResult() {
  final now = DateTime.now();
  return LivenessResult(
    success: true,
    completedActions: const [LivenessAction.blink, LivenessAction.smile],
    startedAt: now.subtract(const Duration(seconds: 8)),
    finishedAt: now,
    confidenceScore: 0.97,
    sessionId: 'LV-TEST',
  );
}
```

## The result

`onResult` gets one `LivenessResult`:

| Field | Meaning |
|---|---|
| `success` | All actions done in time, nothing failed the session. |
| `failureReason` | A `LivenessFailureReason` when `success` is false. |
| `confidenceScore` | 0 to 1. Starts at 1.0, lowered by suspicious signals. A clean pass on a real camera is 0.9 or more. |
| `completedActions` | The actions done, in the order they ran. |
| `images` | `CapturedImage`s (`bytes`, `action`, `kind`, `timestampMs`, `sha256Hex`). Empty unless `CaptureType.images`. |
| `frameSequence` | Steady-rate frames. Empty unless `CaptureType.frameSequence`. |
| `videoPath` | Temp file path. Null unless `CaptureType.video` and it worked. |
| `sessionId` | Audit ID such as `LV-018F3A2B9C4E-D7E31F08`. New on every session. |
| `nonce` | The server challenge's nonce, if one was used. |
| `attestation` | The attestor's token, if an attestor was set and succeeded. |
| `metadata` | Diagnostics: `<action>_ms` durations, `confidence_*` and `identity_*` counters, `cameraMode`, `cancelledBy`, `flashChallenge`, `videoUnavailable`, `attestationError`, `analyzers`. |

`CaptureKind` says what a photo shows: `reference` (neutral face before
the first action), `peak` (the clearest moment of an action, such as eyes
shut), `completion` (the frame where it passed, used when there is no
peak), `sequence` (a frame-sequence frame).

`result.toJson()` is a JSON-safe summary without image bytes, and it is
what the built-in uploader sends as `metadata`. `result.toString()` is a
readable log block.

### Handling each failure

`LivenessFailureReason` is an enum and new values arrive in minor
releases, so prefer a `switch` that the analyzer checks for completeness:

```dart
import 'package:liveness_flutter/liveness_flutter.dart';

/// What to tell the user, and whether offering "Try again" makes sense.
(String message, bool canRetry) explainFailure(LivenessResult result) {
  return switch (result.failureReason) {
    null => ('Verified', false),
    LivenessFailureReason.actionTimeout ||
    LivenessFailureReason.sessionTimeout =>
      ('That took too long. Try again in good light.', true),
    LivenessFailureReason.faceLost =>
      ('Keep your face inside the frame.', true),
    LivenessFailureReason.multipleFaces =>
      ('Only one person should be in view.', true),
    LivenessFailureReason.faceChanged =>
      ('A different face appeared. Start again.', true),
    LivenessFailureReason.spoofSuspected =>
      ("We couldn't confirm a live camera.", true),
    LivenessFailureReason.challengeExpired =>
      ('This check expired. Start again.', true),
    LivenessFailureReason.permissionDenied =>
      ('Allow camera access in Settings to continue.', false),
    LivenessFailureReason.systemError =>
      ('The camera had a problem. Try again.', true),
    LivenessFailureReason.cancelled => ('Cancelled', true),
  };
}
```

Notes:

- `cancelled` results say who cancelled in `metadata['cancelledBy']`:
  `'user'` (close button or `controller.cancel()`), `'lifecycle'` (the app
  went to the background), `'restart'` (`controller.restart()` while
  running) or `'dispose'` (the screen was closed first).
- `actionTimeout` with `metadata['timeoutPhase'] == 'awaitingNeutral'`
  means the user didn't return to a neutral face between actions.
- `systemError` right at the start can be an invalid config:
  `metadata['configError']` holds the message. Call `config.validate()`
  yourself to catch it earlier.
- `challengeExpired` is checked against the phone's clock; the server must
  check expiry with its own clock too.

## Navigation pattern

The usual flow is: a screen with a "Verify" button pushes the liveness
page, the liveness page pops with the result, and the first screen
uploads while showing progress. Closing the camera screen before
uploading frees the camera and lets you show a progress bar. See
[backend.md](backend.md) for the upload.
