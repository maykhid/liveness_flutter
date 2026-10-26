# Configuration: `LivenessConfig` and `DetectorTuning`

Every field below has a default; set only what the task needs. The
installed package's `lib/src/models/models.dart` is the source of truth
for names and defaults.

## Choosing actions

| Action | Kind | Notes |
|---|---|---|
| `blink` | motion | Fast and reliable. Sampled at ~20 fps. Good default. |
| `nod` | motion | Down and back up. Uses pitch; see `invertPitch`. |
| `openMouth` | motion | Needs face contours, which turns ML Kit tracking off (see `failOnFaceChange`). |
| `drawCircleWithNose` | motion | Experimental. Whole-head circles; expect retries. Don't make it mandatory without testing on real users' phones. |
| `smile` | pose | Easy. Fakeable with a photo, so pair it with a motion action. |
| `fullTeethSmile` | pose | Needs contours. Device-sensitive (lip contour quality). |
| `lookLeft`, `lookRight` | pose | The *user's* left and right. See `mirrorYaw`. |
| `lookUp`, `lookDown` | pose | Pitch-based; see `invertPitch`. |
| `tiltLeft`, `tiltRight` | pose | Head roll toward a shoulder. |
| `eyesClosed` | pose | Hold closed for `eyesClosedHold` (2 s). The user can't see it finish, so add `hapticFeedback: true`. |

Guidance:

- At least one motion action, always.
- Two to four actions is the usual range. Each costs a few seconds and
  some users fail some actions.
- For users who struggle (older users, accessibility needs): `blink` and
  `smile`, longer `actionTimeout`, and `requireNeutralBetweenActions:
  false`.

## Order and randomness

| Field | Default | Effect |
|---|---|---|
| `actions` | required | The list, or the pool when `randomActionCount` is set. Ignored (pass `const []`) when `challenge` is set. |
| `shuffleActions` | `false` | New random order each session. Use `true` in production unless a fixed script matters. |
| `randomActionCount` | `null` | Pick this many from `actions` at random, in random order. 3 from all 13 gives 1,716 sequences. Must be 1 to `actions.length`. |
| `challenge` | `null` | A server-issued `LivenessChallenge`: runs exactly its actions in its order, echoes its nonce, fails with `challengeExpired` once `expiresAt` passes. See [backend.md](backend.md). |

```dart
import 'package:liveness_flutter/liveness_flutter.dart';

// Three random actions from a pool, in random order, every session.
const pooled = LivenessConfig(
  actions: [
    LivenessAction.blink,
    LivenessAction.nod,
    LivenessAction.smile,
    LivenessAction.lookLeft,
    LivenessAction.lookRight,
  ],
  randomActionCount: 3,
  capture: {CaptureType.images},
);
```

A random pick from a pool can come out with no motion action. If that
matters, put only motion actions in the pool, use a fixed list with
`shuffleActions`, or let the server choose.

## Timing

| Field | Default | Effect |
|---|---|---|
| `actionTimeout` | 15 s | Per action. Keeps running while the session is paused for bad light. |
| `neutralTimeout` | 10 s | Time to return to a neutral face between actions. |
| `sessionTimeout` | 2 min | Whole session from the first frame. `null` disables it. |
| `faceLostGrace` | 800 ms | How long the face may leave the frame. |
| `requireNeutralBetweenActions` | `true` | Blocks holding one pose through several actions. |

## Faces

| Field | Default | Effect |
|---|---|---|
| `failOnMultipleFaces` | `true` | Fail on a second face of comparable size. `false` uses the largest face. |
| `multipleFacesGrace` | 500 ms | How long a second face may stay before failing. Small background faces are ignored (`tuning.secondaryFaceMinAreaRatio`). |
| `failOnFaceChange` | `false` | Fail with `faceChanged` when ML Kit's tracking ID changes while a face stays in view. Off by default because a fast head turn can re-assign the ID on some devices. Needs tracking, which is off when `openMouth` or `fullTeethSmile` is in the list. |

## Capture

| Field | Default | Effect |
|---|---|---|
| `capture` | `{}` | Any of `CaptureType.images`, `.video`, `.frameSequence`. |
| `captureReferenceImage` | `true` | A neutral photo before the first action (with `images`). |
| `captureAtPeak` | `true` | Photo at the action's clearest moment rather than the passing frame. |
| `maxImageDimension` | 720 | Longest side of photos and frames, in pixels. |
| `jpegQuality` | 85 | 1 to 100. |
| `frameSequenceFps` | 8 | 1 to 15. |
| `frameSequenceMaxFrames` | 300 | Memory cap for frame sequences. |
| `autoDeleteVideo` | `false` | Delete the video file when the screen closes. Only after you uploaded or copied it. |

`LivenessDetector.cameraResolution` (default `ResolutionPreset.high`) sets
the camera and video resolution.

Which to use:

- **`images`**: the best default and the minimum for KYC. A few photos,
  smallest upload.
- **`frameSequence`**: video-like evidence that works on every phone. The
  server can make an MP4 with
  `ffmpeg -framerate 8 -pattern_type glob -i 'frame_*.jpg' -c:v libx264 -pix_fmt yuv420p session.mp4`.
- **`video`**: a real file. Reliable on iPhone; many Android phones can't
  record and analyse at once. Probe first:

```dart
import 'package:liveness_flutter/liveness_flutter.dart';

/// Call once during onboarding, never while a camera screen is open. It
/// takes 2 to 3 seconds on Android the first time and is cached.
Future<Set<CaptureType>> chooseCapture() async {
  final canRecord = await LivenessCapabilities.supportsVideoCapture();
  return canRecord
      ? {CaptureType.images, CaptureType.video}
      : {CaptureType.images, CaptureType.frameSequence};
}
```

If video fails mid-session anyway, the session continues without it and
`metadata['videoUnavailable']` is `true`.

Memory: photos are held in memory until `onResult`. Defaults use roughly
15 to 35 MB. Raising the frame rate and photo size together can run cheap
Android phones out of memory.

## Lighting and quality

| Field | Default | Effect |
|---|---|---|
| `enableQualityChecks` | `true` | Pause with a hint when too dark, too bright or blurry. |
| `brightnessMin` / `brightnessMax` | 0.10 / 0.95 | Mean brightness bounds, 0 to 1. |
| `sharpnessMin` | 0.03 | Below this counts as blurry. |
| `boostScreenBrightness` | `true` | Full screen brightness while open (app window only), restored on close. |

## Anti-spoofing switches

| Field | Default | Effect |
|---|---|---|
| `enableReplayGuard` | `true` | The static-feed guard. Pixel-identical frames fail with `spoofSuspected`; near-identical frames and unnatural stillness lower `confidenceScore`. It catches injected or frozen feeds, not a photo or screen held up to a real camera. |
| `enableFlashChallenge` | `false` | After the actions, flash red, green and blue in random order (~2.5 s) and check the face reflects them. Soft signal: a failure lowers `confidenceScore` by 0.35 and sets `metadata['flashChallenge'] = 'failed'`, never fails the session. Strong indoors, weak in bright offices, meaningless outdoors. |
| `flashAllowedMisses` | 0 | Colour phases that may fail while it still passes, 0 to 2. |
| `frameAnalyzers` / `analyzerWeight` | `[]` / 0.5 | Your own anti-spoof models. See [backend.md](backend.md). |

Treat a failed flash challenge as "review", not "fraud", and learn real
users' pass rate before acting on it.

## Assisted mode

`cameraMode: LivenessCameraMode.assisted` is for an operator (bank agent,
field officer) pointing the **back** camera at someone else. The operator
reads the instructions aloud; left and right mean the subject's; the torch
lights the face (`assistedTorchEnabled`, default `true`); the flash
challenge is skipped (`metadata['flashChallenge'] = 'skippedAssistedMode'`);
`metadata['cameraMode']` tells the server. The server may want extra
review for assisted sessions, since the operator controls the device.

## Orientation fixes

| Field | Default | Use when |
|---|---|---|
| `mirrorYaw` | `true` | Set `false` if `lookLeft`/`lookRight` are swapped on a device. |
| `invertPitch` | `false` | Set `true` if `lookUp`, `lookDown` or `nod` are inverted (check the live pitch with `showDebugOverlay`). Up/down has not been confirmed on every iPhone. |

## Performance

| Field | Default | Effect |
|---|---|---|
| `mlInterval` | 100 ms | Time between face detections (~10 fps). |
| `mlIntervalBlink` | 50 ms | Used during `blink` and `eyesClosed`. |
| `hapticFeedback` | `false` | Ticks on action complete and on pass or fail. |

## `DetectorTuning`: how strict each action is

Pass `tuning: DetectorTuning(...)`. Defaults are tested on real devices;
change one value at a time while watching `showDebugOverlay`.

| Field | Default | Meaning |
|---|---|---|
| `blinkClosedThreshold` | 0.25 | Eye-open probability that counts as closed. |
| `blinkOpenThreshold` | 0.7 | Counts as open. |
| `blinkPartialCloseThreshold` | 0.4 | A half-shut fast blink between open frames still counts. Set to `blinkClosedThreshold` to require fully closed eyes. |
| `blinkMaxDuration` | 1500 ms | Longer closures aren't a blink. |
| `smileThreshold` | 0.75 | Smile probability for `smile`. |
| `fullTeethSmileThreshold` | 0.85 | Smile probability for `fullTeethSmile`. |
| `fullTeethMouthOpenRatio` | 0.03 | Lip gap for `fullTeethSmile` (when contours exist). |
| `expressionHold` | 500 ms | Hold time for smiles and `openMouth`. |
| `eyesClosedHold` | 2 s | Hold time for `eyesClosed`. |
| `eyesOpenTolerance` | 300 ms | Eye-open flickers shorter than this don't reset `eyesClosed`. |
| `yawThreshold` | 25° | Turn needed for `lookLeft`/`lookRight`. |
| `pitchThreshold` | 15° | Tilt needed for `lookUp`/`lookDown`. |
| `rollThreshold` | 20° | Tilt needed for `tiltLeft`/`tiltRight`. |
| `poseHold` | 400 ms | Hold time for poses. |
| `nodPitchThreshold` | 12° | Depth of a nod. |
| `mouthOpenRatioThreshold` | 0.09 | Lip gap for `openMouth`. |
| `circleMinSweepDegrees` | 270 | How much of a circle `drawCircleWithNose` needs. |
| `circleWindow` | 10 s | Time to draw it. |
| `circleMinRadius` | 6° | Smaller head movements don't count toward the circle. |
| `secondaryFaceMinAreaRatio` | 0.35 | Faces smaller than this fraction of the main face are ignored. |
| `targetFillMin` / `targetFillMax` | 0.15 / 1.0 | Face size relative to the on-screen target: below is "move closer", above is "move back". |
| `maxFrameGap` | 250 ms | The most one gap between analysed frames adds to a hold timer. |

Most often loosened: `smileThreshold` or `fullTeethSmileThreshold` for
users whose smiles score low, `yawThreshold` for small turns, and
`targetFillMin` when users hold the phone far away.
