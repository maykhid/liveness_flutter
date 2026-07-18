<div align="center">

# 🛡️ liveness_flutter

**Face liveness checks for Flutter — free, on-device, and built for *your* backend.**

[![pub package](https://img.shields.io/pub/v/liveness_flutter.svg)](https://pub.dev/packages/liveness_flutter)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-green.svg)](#)
[![No ML models](https://img.shields.io/badge/models-none%20to%20download-orange.svg)](#)

*Blink. Smile. Turn left. Verified.* ✅

<!-- 📸 Screenshots coming soon:
<img src="screenshots/demo.gif" width="260"/>
<img src="screenshots/session.png" width="260"/>
<img src="screenshots/result.png" width="260"/>
-->

</div>

---

You give it a list of actions (blink, smile, turn left…). It shows the
camera, guides the user through each action, and checks a real live person
performed them. When it's done you get one result object — optionally with
photos and/or video — and you send it **wherever you want**.

Everything runs on the phone. **No cloud service. No license fees. No
model downloads. No account.**

## ✨ Why this package?

| | |
|---|---|
| 🎯 **13 challenge actions** | blink, smile, fullTeethSmile, nod, look left/right/up/down, tilt left/right, eyes closed, open mouth, draw-a-circle-with-your-nose |
| 🎲 **Anti-replay shuffle** | random action order per session, so a pre-recorded video can't follow the script |
| 🕵️ **Anti-spoof, zero ML** | replay guard (sensor-noise check), micro-motion analysis, frame-quality gates, opt-in color-flash challenge |
| 📸 **Evidence capture** | photos per action, full video, or a works-everywhere frame sequence — your server verifies, not just the phone |
| 🔌 **Any backend** | `onResult` hands you everything; built-in multipart uploader with progress, or bring dio/S3/Firebase/anything |
| 🎨 **Fully yours** | theme every color and string (localizable), or replace whole UI layers with your own widgets |
| 🧑‍🤝‍🧑 **Assisted mode** | agent points the back camera at the customer — torch lighting, auto-flipped left/right |
| 🪶 **Featherlight** | pure Dart + Google ML Kit. No TensorFlow, no 20 MB downloads, minSdk 21 |

## 🚀 Quick start

```dart
import 'package:liveness_flutter/liveness_flutter.dart';

LivenessDetector(
  config: LivenessConfig(
    actions: [
      LivenessAction.blink,
      LivenessAction.smile,
      LivenessAction.lookLeft,
      LivenessAction.lookRight,
      LivenessAction.nod,
    ],
    shuffleActions: true,          // random order each time (recommended)
    capture: {CaptureType.images}, // one photo per completed action
  ),
  onResult: (result) async {
    if (result.success) {
      // Send it to your server however you like — everything is in `result`.
      await myApi.submitLiveness(result);
    }
    Navigator.pop(context, result);
  },
)
```

> 💡 Why `shuffleActions: true`? If actions always come in the same order,
> someone could record a video of a person doing that exact sequence and
> play it to the camera. Random order means yesterday's recording won't
> match today's sequence.

## ⚙️ Setting up Android and iOS

**Android** — set `minSdkVersion 21` in your app.

**iOS** — add to `ios/Runner/Info.plist` (without it the app crashes on
camera use):

```xml
<key>NSCameraUsageDescription</key>
<string>Camera is used for liveness verification.</string>
```

Also set `platform :ios, '15.5'` in `ios/Podfile` (the face detection
library needs iOS 15.5+).

## 📸 Photos, video, and "frame sequence" — which do I pick?

**Capturing nothing is the default.** `capture` is an empty set unless you
add to it — then `result.images` and `result.frameSequence` come back
empty and `videoPath` is null. Nothing is encoded, kept in memory, or
written to disk; frames are analyzed for the check and discarded
immediately. You still get the verdict: `success`, `completedActions`,
`confidenceScore`, `sessionId`, and `metadata` — a few hundred bytes.

The trade-off: with no captured media, your server has nothing to
independently verify — you're fully trusting the on-device result. Fine
for low-stakes flows (gating a selfie upload); for KYC or anything with
real consequences, capture at least `{CaptureType.images}` so your backend
can double-check.

| You want | Use | Notes |
|---|---|---|
| A photo of each completed action | `CaptureType.images` | Smallest uploads. Works everywhere. **Best default.** |
| A real video file of the session | `CaptureType.video` | Great on iPhones. On many Android phones the camera can't record and detect at the same time — see below. |
| Something video-like that works on every phone | `CaptureType.frameSequence` | Several photos per second for the whole session. A list of photos, not a video file — but played back they look like one. |

<details>
<summary>🤖 <b>The Android video problem, in plain words</b> (click to expand)</summary>

Detecting your face and recording a video both need the camera at the same
time. iPhones handle that fine. Many Android phones can't — and there's no
official way to ask a phone in advance. So this package gives you three
tools:

1. `LivenessCapabilities.supportsVideoCapture()` — call it once when your
   app starts (takes 2–3 seconds, remembers the answer). It quietly tries
   recording and tells you `true`/`false`:

   ```dart
   final canRecord = await LivenessCapabilities.supportsVideoCapture();
   final capture = canRecord
       ? {CaptureType.images, CaptureType.video}
       : {CaptureType.images, CaptureType.frameSequence};
   ```

2. If you skip that and video fails mid-session anyway, the check **doesn't
   break** — it quietly continues without video and marks
   `result.metadata['videoUnavailable'] = true` so you know.

3. Frame sequence as the works-everywhere alternative. If your server wants
   a real video file from those photos, one command turns them into an MP4:

   ```bash
   ffmpeg -framerate 8 -pattern_type glob -i 'frame_*.jpg' \
     -c:v libx264 -pix_fmt yuv420p session.mp4
   ```

</details>

## 📦 What you get back

`onResult` gives you a `LivenessResult` with:

- `success` — did the person complete all actions in time?
- `confidenceScore` — 0 to 1. A clean run on a real camera scores 0.9+.
  Duplicate frames, a frozen head, or many bad-quality frames pull it
  down. Raw counters are in `metadata` under `confidence_*` keys.
- `sessionId` — unique audit ID (e.g. `LV-018F3A2B9C4E-D7E31F08`)
- `completedActions` — which actions, in the order performed
- `images` — the photos, each labeled with the action it belongs to
- `frameSequence` — the steady-stream photos, each with a timestamp
- `videoPath` — where the video file is, if you recorded one
- `failureReason` — why it failed (took too long, face left the screen,
  more than one face, replay/static input suspected, user cancelled…)
- `metadata` — extras like how long each action took

Log it with `debugPrint(result.toString())`, or `result.toJson()` for a
JSON-safe summary (no media bytes).

## ☁️ Sending results to your server

You never *have* to use anything built-in — `onResult` gives you the data,
and any upload code you already have will do. For convenience:

```dart
// The common case: POST everything as a multipart form.
await HttpLivenessUploader(
  endpoint: Uri.parse('https://api.example.com/liveness'),
  headers: {'Authorization': 'Bearer …'},
  onProgress: (sent, total) => progress.value = sent / total,
).upload(result);

// Or wrap your own function (dio, Firebase, S3, anything):
final uploader = LivenessUploader.custom((result) async {
  // your code here
});
```

> ⏳ **Show a progress bar.** With photos and frames, an upload is easily
> several MB — on mobile data that's many seconds, and a silent wait looks
> frozen. `onProgress` gives you `(sentBytes, totalBytes)` to drive any
> progress UI. Since uploading happens in *your* `onResult` code, the UI
> is fully yours: a common pattern is to close the camera screen
> immediately (`Navigator.pop`) and upload from the previous screen with a
> `LinearProgressIndicator`. Bringing your own transport (dio etc.)? Use
> its progress callbacks the same way.

## 🎨 Making it look like your app

- `LivenessTheme` — colors, borders, text styles, oval size, and **every
  piece of text** (so you can translate it).
- `overlayBuilder` / `instructionBuilder` — swap out the dimmed overlay or
  the instruction area entirely with your own widgets. Both receive the
  live session state and rebuild on every change. Useful fields:
  `state.phase`, `state.currentAction`, `state.completedActions`,
  `state.actionProgress` (current action, 0–1), `state.overallProgress`
  (whole session), `state.faceInPosition`, `state.remaining` (time left),
  `state.guidance` (what's wrong right now: too far, too dark…).
- `DetectorTuning` — how strict each action is (how big a smile counts,
  how far to turn, how long to hold…). Tested defaults, all adjustable.

<details>
<summary>🧩 <b>Custom UI examples</b> (click to expand)</summary>

```dart
// Custom instructions: your own text, emoji, step dots — anything.
instructionBuilder: (context, state) {
  final text = switch (state.phase) {
    LivenessPhase.searchingFace => 'Show us your face 👀',
    LivenessPhase.performingAction => switch (state.currentAction!) {
        LivenessAction.blink => 'Blink! 😉',
        LivenessAction.smile => 'Smile! 😊',
        _ => state.currentAction!.name,
      },
    LivenessPhase.completed => 'You\'re verified ✅',
    _ => 'One moment…',
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Text(text,
        style: const TextStyle(color: Colors.white, fontSize: 18)),
  );
},
```

```dart
// Custom overlay: replace the oval with anything — here, a progress bar
// on top of a scrim you draw yourself.
overlayBuilder: (context, state) => Stack(fit: StackFit.expand, children: [
  CustomPaint(painter: MyWindowPainter(active: state.faceInPosition)),
  Align(
    alignment: const Alignment(0, -0.85),
    child: SizedBox(
      width: 220,
      child: LinearProgressIndicator(value: state.overallProgress),
    ),
  ),
]),
```

Tip: if you draw your own overlay shape, keep the "window" roughly
centered — the face-position check expects the face near the middle of the
frame. The example app has a full working custom UI behind a toggle.

</details>

## 🧑‍🤝‍🧑 Assisted mode: verifying someone else (opt-in)

By default the person being verified holds the phone and uses the front
camera. Some flows are different: a bank agent or field officer holds the
phone and verifies **another person** — common in branch onboarding and
doorstep KYC:

```dart
LivenessConfig(
  actions: [...],
  cameraMode: LivenessCameraMode.assisted,
)
```

**Understand what assisted mode means before using it:**

- The **back camera** is used, pointed at the subject. The **operator**
  watches the screen and must **read each instruction out loud** ("please
  blink", "turn your head left") — the subject cannot see the screen.
- "Left" and "right" always mean the *subject's* left/right; detection
  signs are flipped automatically for the unmirrored back camera.
- The **device torch turns on** to light the subject's face (the screen,
  which normally does that job, faces the operator). Opt out with
  `assistedTorchEnabled: false`. Skipped on devices without a torch.
- The **color-flash challenge is automatically skipped** (the screen's
  colors can't reach the subject's face):
  `metadata['flashChallenge'] = 'skippedAssistedMode'`. Replay guard,
  micro-motion, and quality gates still run.
- `metadata['cameraMode']` tells your backend which mode was used — decide
  whether assisted sessions need extra review, since the operator (not the
  subject) controls the device.

## 🌈 Stopping video replays: the color-flash challenge (opt-in)

The hardest cheap attack on *any* action-based liveness check is playing a
video of a real person on a second screen. The actions in the video look
real to the camera, because they were real when recorded.

`enableFlashChallenge: true` adds a defense: right after the actions
succeed, the screen flashes a short color sequence (red/green/blue, in a
**random order each session**, ~2.5 seconds, "Hold still…"). A real face
is lit by the phone's screen, so the camera sees each color reflected on
the skin. A replayed video was recorded before this session's random order
existed — its "face" doesn't reflect the right colors at the right times.

```dart
LivenessConfig(
  actions: [...],
  shuffleActions: true,
  enableFlashChallenge: true,
)
```

**It's a soft signal, on purpose — and lighting is why.** The trick
depends on the phone screen being a meaningful light source on the face:

| Environment | What to expect |
|---|---|
| 🌙 Dim / evening indoor | Strong signal — reflections clearly measurable |
| 🏠 Normal indoor lighting | Good signal — reliable for most users |
| 🏢 Bright office / large windows | Weak — real faces may score `'inconclusive'` or `'failed'` |
| ☀️ Outdoors in daylight | Little to no signal — results not meaningful |

Other weakeners: phone held far from the face, very low screen brightness,
strongly colored ambient light. To help, the package **raises the screen
to full brightness automatically** during the session and restores it
afterward (app window only; opt out with `boostScreenBrightness: false`).

A failed challenge lowers `confidenceScore` by 0.35 and sets
`metadata['flashChallenge'] = 'failed'` — it never rejects the user by
itself. **Treat a failure as "review this one", not "this is fraud."**
Log the metadata for a few weeks and learn your real users' pass rate
before enforcing anything. Bonus: the flash moment is captured in your
video/frames — a real face visibly changes color, which your server can
check too.

## 🎛️ Media size & cleanup

- **Photo size**: `maxImageDimension` (default 720 px longest side) and
  `jpegQuality` (default 85; lower = smaller files).
- **Video size**: `cameraResolution` on the `LivenessDetector` widget.
- **Frame rate**: `frameSequenceFps` (default 8, max 15) and
  `frameSequenceMaxFrames` (default 300) cap memory. Encoding runs in
  background isolates — capture never stalls detection.
- **Cleanup**: photos live only in memory — gone when you're done with the
  result. The **video is a real file** and is *not* deleted automatically:
  upload or copy it in `onResult`, then delete it yourself or set
  `autoDeleteVideo: true` to remove it when the camera screen closes.

## 🔧 Developer goodies

- **Debug overlay** — `showDebugOverlay: true` shows live head angles,
  eye/smile probabilities, brightness, and replay-guard counters on
  screen. Perfect for tuning `DetectorTuning` thresholds on real devices.
- **Per-action callbacks** — `onActionStarted` / `onActionCompleted`
  (sync or async; never awaited, so detection never stalls on your code).
- **Session log** — `debugPrint(result.toString())` prints a readable
  block: actions, timings, confidence penalties, media counts.
- **Guidance state** — `state.guidance` tells you exactly what's wrong
  right now (`tooFar`, `tooClose`, `notCentered`, `lowLight`, `blurry`,
  `multipleFaces`) with translatable default messages.

## 📖 Honest notes — read before shipping

Plain-language notes on the rough edges. Every one has a setting you can
change; nothing requires forking the package.

**This is not bank-grade security on its own.** All checking happens on
the phone, and a determined attacker controls their own phone. Treat a
passing result as a good first gate, and have your server double-check the
photos/video you upload (compare against an ID photo, look for signs of
screens or prints). That's exactly why this package captures media
*during* the actions.

**Memory adds up if you turn everything up.** Photos are kept in memory
until the result is delivered. Defaults use roughly 15–35 MB per session.
Raising the frame rate *and* photo size together can OOM cheap Android
phones. `frameSequenceMaxFrames` caps the total as a safety net.

**Every face and phone is a little different.** How confidently the phone
detects a smile or head turn varies with the camera, lighting, glasses,
and the person. If one action fails too often for your users, loosen its
setting in `DetectorTuning`. Most sensitive: `fullTeethSmile` (depends on
lip-contour quality) and `eyesClosed` (brief false "eye open" flickers are
ignored; `eyesOpenTolerance` controls how brief).

**`drawCircleWithNose` is a fun extra, not a workhorse.** People must move
their whole head in a circle, and small/slow circles don't count. Expect
more retries. Test on your users' actual phones before making it
mandatory.

**Left and right.** `lookLeft` means the *user's* left. Calibrated for
Android and iPhone; if some device gets it backwards, `mirrorYaw: false`
flips it.

**Give people time.** Each action has a 15-second limit (`actionTimeout`)
and users must return to a neutral face between actions. For users who
find the actions difficult, use fewer/easier actions (blink, smile), a
longer timeout, and `requireNeutralBetweenActions: false`.

**It needs light — but it tells the user.** Too-dark, overexposed, and
blurry frames pause the session (they won't fail it) with a hint like
"Find better lighting". Thresholds: `brightnessMin`, `brightnessMax`,
`sharpnessMin`; disable with `enableQualityChecks: false`.

**The anti-spoof checks are honest heuristics, not magic.** The replay
guard catches static images and naive injected feeds; micro-motion flags
unnaturally still sessions in the confidence score. Neither stops a
sophisticated attacker with a high-quality replay rig — that's what
server-side review of the captured media is for. If the replay guard ever
misfires on a device (it shouldn't — real sensors are noisy),
`enableReplayGuard: false` turns it off.

---

<div align="center">

**Found a bug? Have an idea?** Issues and PRs welcome. 🙌

Made with ❤️ for developers who'd rather not pay per verification.

</div>
