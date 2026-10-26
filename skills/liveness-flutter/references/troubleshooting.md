# Troubleshooting

Start every device problem with `showDebugOverlay: true` on
`LivenessDetector`. It shows live head angles, eye and smile
probabilities, brightness, sharpness and static-feed guard counters, and
draws a green box where ML Kit sees the face.

## Build and setup

| Symptom | Cause and fix |
|---|---|
| iOS app crashes when the camera opens | `NSCameraUsageDescription` is missing from `ios/Runner/Info.plist`. |
| `pod install` fails on the ML Kit pods | `ios/Podfile` needs `platform :ios, '15.5'` or higher. Then `cd ios && pod install --repo-update`. |
| Android build says minSdk is too low | Set `minSdk = 24` in `android/app/build.gradle(.kts)`. |
| Version solving fails on `camera` | The package needs `camera` 0.12, which needs Flutter 3.38+. Upgrade Flutter, or align the app's own `camera` constraint. |
| `'implements' LivenessAttestor` no longer compiles after upgrading to 0.6 | `prepare()` was added. Switch to `extends LivenessAttestor`, or add `Future<void> prepare() async {}`. |
| A `switch` over `LivenessFailureReason` or `FaceGuidance` stops compiling after an upgrade | A minor release added a value. Add the case. |
| Nothing works on a simulator or emulator | No usable front camera. Use a physical phone. |

## Sessions

| Symptom | Cause and fix |
|---|---|
| Stuck on "Fit your face in the oval" with a custom overlay | The face must be inside the *theme's* oval unless `targetRegion` is set. Pass the drawn window as `targetRegion` and set `theme.ovalShape` to its shape. |
| Stuck on "Move closer" | The face fills too little of the target. Lower `tuning.targetFillMin`, or make the target smaller (`theme.ovalSizeFactor`). |
| `lookLeft` and `lookRight` are swapped on one device | Set `mirrorYaw: false` for it. In assisted mode the sign flips automatically for the back camera. |
| `lookUp`, `lookDown` or `nod` are inverted | Set `invertPitch: true`. Check the pitch sign in the debug overlay first; up/down is not yet confirmed on every iPhone. |
| `smile` or `fullTeethSmile` rarely completes | Lower `tuning.smileThreshold` or `tuning.fullTeethSmileThreshold`. `fullTeethSmile` depends on lip contour quality and varies by device. |
| `eyesClosed` resets | Eye-open flickers longer than `tuning.eyesOpenTolerance` (300 ms) reset the hold. Raise it a little, and add `hapticFeedback: true` so users know when it's done. |
| `drawCircleWithNose` fails a lot | Expected: it needs big whole-head circles. Lower `tuning.circleMinSweepDegrees` or drop the action. |
| Frequent `actionTimeout` with `metadata['timeoutPhase'] == 'awaitingNeutral'` | Users don't return to neutral between actions. Raise `neutralTimeout` or set `requireNeutralBetweenActions: false`. |
| Session pauses with "Find better lighting" and then times out | Too dark. The action timer keeps running while paused by design. Better light, or adjust `brightnessMin`; `enableQualityChecks: false` disables the pause. |
| `multipleFaces` failures from people in the background | Raise `tuning.secondaryFaceMinAreaRatio` or `multipleFacesGrace`, or `failOnMultipleFaces: false`. |
| `spoofSuspected` on a real, normal phone | The static-feed guard saw pixel-identical frames. That shouldn't happen with a live sensor; capture the device model and report it to the package's issue tracker. `enableReplayGuard: false` turns the guard off. |
| `faceChanged` failures on fast head turns | `failOnFaceChange: true` reacts to ML Kit re-assigning the tracking ID. Leave it `false`; the change still lowers `confidenceScore`. |
| `systemError` immediately | Often an invalid config; read `metadata['configError']`, or call `config.validate()` to get the `ArgumentError`. Otherwise a camera or ML Kit failure: check `onError`. |
| `challengeExpired` straight away | The phone's clock is ahead of the server's, or the challenge sat too long before the screen opened. Fetch the challenge just before opening the screen and give a few minutes of expiry. |
| Low `confidenceScore` on clean runs | Read the `confidence_*` keys in `metadata` to see which signal lowered it (duplicate frames, low motion, quality violations, flash challenge, analyzers). |

## Results and navigation

| Symptom | Cause and fix |
|---|---|
| Pressing back closes two screens | `onResult` ran after the screen was disposed and popped the previous route. Guard with `if (!context.mounted) return;` and pop only when `ModalRoute.of(context)?.isCurrent ?? false`. |
| `onResult` got a `cancelled` result nobody pressed | `metadata['cancelledBy']`: `'lifecycle'` (app went to the background), `'dispose'` (screen closed first), `'restart'` (`controller.restart()`). |
| Changing `config` on rebuild has no effect | The config is read once per session. Use a new `key` on `LivenessDetector`, or call `controller.restart()` after the rebuild. |
| `controller.restart()` throws `StateError` | The controller isn't attached to a mounted `LivenessDetector`. |
| `result.images` is empty | `capture` doesn't include `CaptureType.images`. |
| `videoPath` is null with `CaptureType.video` | The device couldn't record and analyse at once: `metadata['videoUnavailable'] == true`. Probe with `LivenessCapabilities.supportsVideoCapture()` and use `frameSequence` there. |
| Out-of-memory crashes on cheap Android phones | Too many frames held in memory. Lower `frameSequenceFps`, `frameSequenceMaxFrames` or `maxImageDimension`. |
| The server's hash check fails | Files were re-encoded, resized or renamed in a way that lost the mapping. Send the bytes unchanged. |
| The attestation is valid but the server's payload check fails | The `metadata` field isn't `result.evidenceJson` byte for byte: a custom uploader decoded and re-encoded it, or built it from `toJson()`. Or the server parsed the JSON before hashing it, or runs against a pre-0.6.0 app that signs the 5-part payload. |
| `attestation` is null | `metadata['attestationError']` says why: the attestor threw, took over 15 s, or the screen closed before it ran. |

## Reporting a device bug

The package is in beta. Issues go to
https://github.com/maykhid/liveness_flutter/issues with the phone model,
OS version, package version and what the debug overlay shows.
