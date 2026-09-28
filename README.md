<div align="center">

# 🛡️ liveness_flutter

**Face liveness checks for Flutter — free, on-device, and built for *your* backend.**

[![pub package](https://img.shields.io/pub/v/liveness_flutter.svg)](https://pub.dev/packages/liveness_flutter)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-green.svg)](#)
[![No ML models](https://img.shields.io/badge/models-none%20to%20download-orange.svg)](#)
[![Status: beta](https://img.shields.io/badge/status-beta-yellow.svg)](#-status-beta)

*Blink. Smile. Turn left. Verified.* ✅

</div>

---

You give it a list of actions (blink, smile, turn left…). It shows the
camera, guides the user through each action, and checks a real live person
performed them. When it's done you get one result object — optionally with
photos and/or video — and you send it **wherever you want**.

Everything runs on the phone. **No cloud service. No license fees. No
model downloads. No account.**

## 🧪 Status: beta

liveness_flutter is in **beta**. It's tested on real Android and iOS
devices, but it's still evolving and the API may change before 1.0. Until
then, a minor release (0.5 → 0.6) can include breaking changes; each one
is listed under **Breaking** in the [CHANGELOG](CHANGELOG.md). Depend on
`^0.5.0` and you'll only get compatible updates.

**Anyone can [open an issue](https://github.com/maykhid/liveness_flutter/issues)**
— bugs, a phone where detection misbehaves, confusing docs, or ideas. For
detection problems, include your phone model, OS version, and what
`showDebugOverlay: true` shows.

## ✨ Why this package?

| | |
|---|---|
| 🎯 **13 challenge actions** | blink, smile, fullTeethSmile, nod, look left/right/up/down, tilt left/right, eyes closed, open mouth, draw-a-circle-with-your-nose |
| 🎲 **Anti-replay** | random action order (and optionally a random pick of actions) per session, so a pre-recorded video can't follow the script |
| 🕵️ **Anti-spoof, zero ML** | static-feed guard (catches frozen or injected camera feeds), micro-motion analysis, frame-quality gates, opt-in color-flash challenge, plus hooks for server challenges, attestation and your own anti-spoof model |
| 📸 **Evidence capture** | a photo at the peak of each action, full video, or a works-everywhere frame sequence — your server verifies, not just the phone |
| 🔌 **Any backend** | `onResult` hands you everything; built-in multipart uploader with progress, errors and retries, or bring dio/S3/Firebase/anything |
| 🎨 **Fully yours** | theme every color and string (localizable), or replace whole UI layers with your own widgets — see the [branded fintech example](#-example-a-fully-branded-kyc-flow) |
| 🧑‍🤝‍🧑 **Assisted mode** | agent points the back camera at the customer — torch lighting, auto-flipped left/right |
| 🪶 **Featherlight** | pure Dart + Google ML Kit. No TensorFlow, no 20 MB downloads, minSdk 24 |

## 🗺️ Pick your path

| You want to… | Go to |
|---|---|
| Add a working liveness check to your app | **[Simple setup](#-simple-setup)** — about 10 minutes |
| See every example, or run one | [Examples](#-examples) |
| Make it look like your app (colours, text, your own screens) | [Make it look like your app](#-make-it-look-like-your-app) and the [fintech example](#-example-a-fully-branded-kyc-flow) |
| Use it for KYC or anything with real consequences | [Bind sessions to your server](#-bind-sessions-to-your-server-recommended-for-kyc) |
| Have an agent verify someone else | [Assisted mode](#-assisted-mode-verifying-someone-else) |
| Know the limits before shipping | [Honest notes](#-honest-notes--read-before-shipping) |

---

# 🚀 Simple setup

Four steps to a working check. Everything here uses defaults; the
[advanced](#-advanced) sections cover the rest.

### 1. Install and set up the platforms

```yaml
dependencies:
  liveness_flutter: ^0.5.0
```

Needs **Flutter 3.38+** (Dart 3.10+), the minimum for `package:camera`
0.12.

**Android** — set `minSdkVersion 24` in your app.

**iOS** — add to `ios/Runner/Info.plist` (without it the app crashes on
camera use):

```xml
<key>NSCameraUsageDescription</key>
<string>Camera is used for liveness verification.</string>
```

Also set `platform :ios, '15.5'` in `ios/Podfile` (the face detection
library needs iOS 15.5+).

You don't need a permissions package: the camera plugin asks for access
the first time. If the user says no, the session ends with
`failureReason == LivenessFailureReason.permissionDenied`.

### 2. Show the liveness screen

```dart
import 'package:liveness_flutter/liveness_flutter.dart';

class LivenessPage extends StatelessWidget {
  const LivenessPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LivenessDetector(
        config: const LivenessConfig(
          actions: [
            LivenessAction.blink,
            LivenessAction.smile,
            LivenessAction.lookLeft,
          ],
          shuffleActions: true,          // a new order every time
          capture: {CaptureType.images}, // photos your server can check
        ),
        onResult: (result) {
          // If the user pressed back, this screen is gone or animating
          // out, and popping would close the *previous* screen. Check first.
          if (!context.mounted) return;
          if (ModalRoute.of(context)?.isCurrent ?? false) {
            Navigator.pop(context, result);
          }
        },
      ),
    );
  }
}

// Somewhere in your app:
final result = await Navigator.push<LivenessResult>(
  context,
  MaterialPageRoute(builder: (_) => const LivenessPage()),
);
```

> ⚠️ `onResult` is called **exactly once** per session — even if the
> screen is closed before the check finishes (system back, route popped).
> In that case the result is `cancelled` with
> `metadata['cancelledBy'] == 'dispose'` and arrives just after the screen
> is gone, which is why the guard above matters. `cancelledBy` is `'user'`
> for the close button and `'lifecycle'` when the app goes to the
> background.

> 💡 **Why shuffle?** If actions always come in the same order, someone
> could record a video of a person doing that exact sequence and play it to
> the camera. Random order means yesterday's recording won't match today's.
>
> 🛡️ Include at least one **motion** action (`blink`, `nod`, `openMouth`,
> `drawCircleWithNose`). Pose-only actions (`smile`, `tiltLeft`/`tiltRight`,
> `lookUp`/`lookDown`) can be faked with a photo tilted or swapped at the
> right moment.

### 3. Read the result

The essentials of `LivenessResult`:

- `success` — did the person complete all actions in time?
- `failureReason` — why not (took too long, face left the screen, more
  than one face, static/injected input suspected, camera access denied,
  user cancelled…)
- `confidenceScore` — 0 to 1. A clean run on a real camera scores 0.9+.
- `images` — the photos, each labelled with its action and `kind`
  (`reference`, or `peak`: the moment the action was clearest, e.g. eyes
  shut for a blink)
- `sessionId` — a unique audit ID (e.g. `LV-018F3A2B9C4E-D7E31F08`)

`debugPrint(result.toString())` prints a readable summary, and
`result.toJson()` gives a JSON-safe one (no image bytes). The
[full list of fields](#-everything-in-the-result) is further down.

### 4. Send it to your server

```dart
try {
  await HttpLivenessUploader(
    endpoint: Uri.parse('https://api.example.com/liveness'),
    headers: {'Authorization': 'Bearer …'},
    onProgress: (sent, total) => progress.value = sent / total,
  ).upload(result);
} on LivenessUploadException catch (e) {
  // Your server answered with an error (e.statusCode, e.body).
}
```

It sends a `metadata` field with `result.toJson()` (session ID,
confidence, actions, a SHA-256 of every photo…), one file per photo named
like `blink_peak_812ms.jpg`, and an `X-Liveness-Session` header. Any
transport works instead: `LivenessUploader.custom((result) async { ... })`
wraps dio, S3, Firebase or anything else.

> ⏳ **Show a progress bar.** With photos an upload can be several MB. A
> common pattern: close the camera screen straight away and upload from
> the previous screen with a `LinearProgressIndicator` driven by
> `onProgress`.

**That's it** — you have a working liveness check. The complete runnable
version of these steps is [`example/lib/main.dart`](example/lib/main.dart).
Before using it for anything with real consequences, read
[Bind sessions to your server](#-bind-sessions-to-your-server-recommended-for-kyc)
and the [honest notes](#-honest-notes--read-before-shipping).

---

# 📚 Examples

Each file in [`example/`](example/) runs on its own on a **physical
device** (simulators have no usable front camera):

| Example | Shows | Run from `example/` |
|---|---|---|
| [Minimal](example/lib/main.dart) | The simple setup above, in ~90 lines | `flutter run` |
| [Branded fintech KYC flow](example/lib/recipes/fintech/main.dart) | A complete, fully custom-designed verification flow ([more below](#-example-a-fully-branded-kyc-flow)) | `flutter run -t lib/recipes/fintech/main.dart` |
| [Custom UI](example/lib/recipes/custom_ui.dart) | Your own overlay and instructions, with detection following your window | `flutter run -t lib/recipes/custom_ui.dart` |
| [Controller](example/lib/recipes/controller.dart) | Your own Cancel / Try again buttons and live state | `flutter run -t lib/recipes/controller.dart` |
| [Server-bound](example/lib/recipes/server_bound.dart) | A challenge from your backend, then upload with error handling | `flutter run -t lib/recipes/server_bound.dart --dart-define=BACKEND_URL=https://…` |
| [Test bench](example/lib/test_bench/main.dart) | Every option behind a settings screen, for trying the package on a device | `flutter run -t lib/test_bench/main.dart` |

Clone the repository to get the example with its Android and iOS folders
ready: `git clone https://github.com/maykhid/liveness_flutter && cd
liveness_flutter/example`. (The copy on pub.dev leaves the platform
folders out; the [example README](example/README.md) explains how to
generate them.)

## 🏦 Example: a fully branded KYC flow

[`example/lib/recipes/fintech/`](example/lib/recipes/fintech/main.dart)
shows how far customisation goes: a complete "upgrade your account"
verification flow, the way a mobile bank or fintech app would ship it,
built for a fictional brand ("AcmePay"). None of the package's default UI
is visible — only its detection.

<div align="center">

<img src="https://raw.githubusercontent.com/maykhid/liveness_flutter/main/screenshots/fintech_demo.gif" width="280" alt="A branded account-upgrade flow: account home, intro, a face check with nod and blink steps, then verified"/>

<sub>The full flow on an iPhone.</sub>

</div>

1. **Account home** — balance card, current tier, "Upgrade to Tier 2".
2. **Intro** — where the user is in the upgrade (phone ✓, BVN ✓, face
   check), tips for passing first time, and what the photos are used for.
3. **Face check** — a light screen with a circular window, a progress ring
   split into one segment per action, and a card with an icon, the current
   step, a hint that turns red when something needs fixing, and a
   countdown. The circle is passed as `targetRegion`, so the face must be
   inside what's drawn. A branded page handles denied camera access.
4. **Verifying → success or failure** — success unlocks Tier 2; failure
   explains what went wrong for each `LivenessFailureReason` and offers
   *Try again*.

**Run it:**

```bash
cd example
flutter run -t lib/recipes/fintech/main.dart
```

**Make it yours:** everything brand-specific — name, colours, wording,
which actions it asks for — is in
[`brand.dart`](example/lib/recipes/fintech/brand.dart). Change `primary`
to your colour and hot reload. The "Verifying" step simulates your
backend's approval: replace `_serverApproves` in `outcome_screens.dart`
with your upload and your server's decision.

---

# 🧰 Advanced

Independent topics — read the ones you need.

## 🎨 Make it look like your app

*You need this if* the default dark oval and white text don't match your
design.

**Theme and text** (no custom widgets): `LivenessTheme` sets colours,
borders, text styles, the target's size, position and shape (oval, circle
or rounded rectangle — this is also where the face must be), the close
button, and **every piece of text** through `LivenessStrings`:

```dart
LivenessDetector(
  theme: LivenessTheme(
    ovalShape: TargetShape.circle,
    progressColor: Colors.teal,
    strings: LivenessStrings(
      actionInstructions: {LivenessAction.blink: 'Clignez des yeux'},
      stepCounter: (current, total) => 'Étape $current sur $total',
    ),
  ),
  ...
)
```

Text maps (`actionInstructions`, `guidanceMessages`, `failureMessages`)
are merged over the English defaults, so you can override just a few
entries. Both `LivenessTheme` and `LivenessStrings` have `copyWith`. For
layout: `instructionAlignment`, `closeButtonBuilder`, and theme fields
like `closeIconColor` and `resultHoldDuration`.

**Your own widgets:** `overlayBuilder` replaces the dimmed overlay and
`instructionBuilder` the instruction area. Both receive the live
`LivenessSessionState` and rebuild on every change. Useful fields:

| Field | What it is |
|---|---|
| `phase` | searching, centering, performing an action, completed, failed… |
| `currentAction`, `actionPlan` | the action now, and every action in this session's order (known from the first frame) |
| `actionProgress`, `overallProgress` | 0–1 for the current action and for the whole session |
| `remaining`, `actionTimeout`, `sessionRemaining` | countdowns |
| `faceInPosition`, `guidance` | whether the face is in place, and what's wrong if not (`tooFar`, `lowLight`…) |
| `failureReason` | why it failed |

**If you draw your own window, tell detection where it is** with
`targetRegion` (normalised to the widget, e.g.
`Rect.fromLTWH(0.15, 0.2, 0.7, 0.5)`); otherwise the theme's oval still
decides where the face must be. Working code:
[custom UI recipe](example/lib/recipes/custom_ui.dart) and the
[fintech example](#-example-a-fully-branded-kyc-flow).

`DetectorTuning` sets how strict each action is (how big a smile counts,
how far to turn, how long to hold…). Tested defaults, all adjustable.

## 🎮 Control it from outside: `LivenessController`

*You need this if* you hide the built-in close button, want a *Try again*
without leaving the screen, or need the state outside the widget.

```dart
final controller = LivenessController(); // create in initState, dispose in dispose

LivenessDetector(
  controller: controller,
  showCloseButton: false,
  config: ...,
  onResult: ...,
);

controller.cancel();         // onResult gets a cancelled result (cancelledBy: 'user')
await controller.restart();  // fresh session: new sessionId, new shuffle
controller.state;            // live LivenessSessionState (it's a ChangeNotifier)
controller.actionPlan;       // the actions in the order this session runs them
```

Every session still gets exactly one `onResult`: restarting a session
that's still running delivers it as `cancelled` with
`cancelledBy: 'restart'`. See the
[controller recipe](example/lib/recipes/controller.dart).

## 🔐 Bind sessions to your server (recommended for KYC)

*You need this if* a passing result unlocks anything valuable. On its own,
the phone's verdict is unsigned: your server can't tell which actions it
expected or whether the result was edited. Three hooks fix that:

- **`LivenessConfig.challenge`**: your server issues a `LivenessChallenge`
  (single-use nonce, the actions in its chosen order, an expiry). The
  session runs exactly that order and echoes the nonce in
  `result.nonce`. An expired challenge fails with `challengeExpired`.
- **Image hashes**: `result.toJson()` (and so the uploader's `metadata`)
  lists the SHA-256 of every photo and frame, so the server can prove the
  files weren't swapped.
- **`LivenessConfig.attestor`**: plug in Play Integrity or App Attest
  through the `LivenessAttestor` interface. It signs a hash of
  `sessionId|nonce|success|actions|image hashes`; the token lands in
  `result.attestation`. The package doesn't implement the platform APIs.

Without a server challenge, `randomActionCount: 3` makes each session
pick 3 actions at random from your list *and* shuffle them — from all 13
actions that's 1,716 possible sequences instead of 6.

**[Server verification guide →](doc/server_verification.md)** covers what
your backend should check, with a payload-rebuild snippet. Working client
code: the [server-bound recipe](example/lib/recipes/server_bound.dart).

**Bring your own anti-spoof model (optional).** The package bundles no ML
model, but `LivenessConfig.frameAnalyzers` lets you plug one in (a
TFLite/ONNX presentation-attack detector, or a cloud call):

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

**Uploads, in more detail:** a non-2xx answer throws
`LivenessUploadException(statusCode, body)`; each attempt is limited by
`timeout` (default 60 s); set `maxRetries` to retry network errors,
timeouts and 5xx with exponential backoff (4xx is never retried).

## 📸 Photos, video, and "frame sequence" — which do I pick?

*You need this if* you want more evidence than one photo per action.

**Capturing nothing is the default.** With an empty `capture`,
`result.images` and `result.frameSequence` come back empty and
`videoPath` is null. Nothing is encoded, kept in memory, or written to
disk. You still get the verdict: `success`, `completedActions`,
`confidenceScore`, `sessionId`, and `metadata` — a few hundred bytes.

The trade-off: with no captured media, your server has nothing to
independently verify — you're fully trusting the on-device result. Fine
for low-stakes flows (gating a selfie upload); for KYC or anything with
real consequences, capture at least `{CaptureType.images}`.

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

**Media size & cleanup:**

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

## 🌈 Stop video replays: the color-flash challenge

*You need this if* you worry about someone playing a video of a real
person to the camera — the hardest cheap attack on any action-based check,
because the actions in the video were real when recorded.

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

**How it decides.** Only pixels inside the detected face are sampled
(background doesn't reflect the screen), the first 150 ms of each colour
is skipped while the display and camera catch up, and auto-exposure is
locked for the duration where the device allows it. Each colour must
raise its own channel clearly above the frame-to-frame noise measured
before the flash, both against that baseline and against the other
colours. By default all three colours must pass
(`flashAllowedMisses: 0`). In simulation, pure camera noise passes 0 times
in 5,000 runs, where the pre-0.5 rule passed about 1 in 20. White balance
can't be locked through the camera plugin, so strongly tinted light can
still skew it.

Other weakeners: phone held far from the face, very low screen brightness,
strongly colored ambient light. To help, the package **raises the screen
to full brightness automatically** during the session and restores it
afterward (app window only; opt out with `boostScreenBrightness: false`).

A failed challenge lowers `confidenceScore` by 0.35 and sets
`metadata['flashChallenge'] = 'failed'` — it never rejects the user by
itself. **Treat a failure as "review this one", not "this is fraud."**
Log the metadata for a few weeks and learn your real users' pass rate
before enforcing anything. Bonus: the flash moment is captured in your
video and frame sequence — a real face visibly changes color, which your
server can check too.

## 🧑‍🤝‍🧑 Assisted mode: verifying someone else

*You need this if* a bank agent or field officer holds the phone and
verifies **another person** — common in branch onboarding and doorstep
KYC:

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
  `metadata['flashChallenge'] = 'skippedAssistedMode'`. Static-feed guard,
  micro-motion, and quality gates still run.
- `metadata['cameraMode']` tells your backend which mode was used — decide
  whether assisted sessions need extra review, since the operator (not the
  subject) controls the device.

## 📦 Everything in the result

`LivenessResult`, in full:

- `success`, `failureReason` — the verdict and why. Cancelled results say
  who in `metadata['cancelledBy']`.
- `confidenceScore` — 0 to 1. Duplicate frames, a frozen head, many
  bad-quality frames, a failed flash challenge or anti-spoof model scores
  pull it down. Raw counters are in `metadata` under `confidence_*` and
  `identity_*` keys.
- `sessionId` — unique audit ID.
- `nonce` / `attestation` — the server challenge's nonce and the
  attestor's token, when you use them.
- `completedActions` — which actions, in the order performed.
- `images` — the photos, each with `action`, `kind`, `timestampMs` and a
  `sha256Hex`.
- `frameSequence` — the steady-stream photos, each with a timestamp.
- `videoPath` — where the video file is, if you recorded one.
- `metadata` — extras like how long each action took.
- `toJson()` / `toString()` — a JSON-safe summary (no media bytes) and a
  readable log block.

## 🔧 Developer tools

- **Debug overlay** — `showDebugOverlay: true` shows live head angles,
  eye/smile probabilities, brightness, and static-feed guard counters on
  screen, and draws a green box where the detector thinks your face is (if
  it doesn't sit on your face, please open an issue with your device).
  Perfect for tuning `DetectorTuning` thresholds on real devices.
- **Per-action callbacks** — `onActionStarted` / `onActionCompleted`
  (sync or async; never awaited, so detection never stalls on your code).
- **Feedback & accessibility** — `onFeedback` fires on action started,
  half-way, completed, and session passed/failed, for your own sounds,
  haptics or text-to-speech. `hapticFeedback: true` adds built-in haptics
  (handy for `eyesClosed`, which users can't see finish). Instructions are
  a screen-reader live region, so each new one is announced.
- **Permission handling in the screen** — `permissionDeniedBuilder:
  (context, retry) => ...` shows your own page when camera access is
  denied; calling `retry` starts a fresh session.
- **Test bench** — [`example/lib/test_bench/`](example/lib/test_bench/main.dart)
  puts every option behind a settings screen, logs every callback live,
  and runs the server-side checks on each result.

---

## 📖 Honest notes — read before shipping

Plain-language notes on the rough edges. Every one has a setting you can
change; nothing requires forking the package.

**This is not bank-grade security on its own.** All checking happens on
the phone, and a determined attacker controls their own phone. Treat a
passing result as a good first gate, and have your server double-check the
photos/video you upload (compare against an ID photo, look for signs of
screens or prints). That's exactly why this package captures media
*during* the actions. Server challenges, image hashes and attestation make
tampering detectable, but the face itself still has to be judged
server-side — see the [server verification guide](doc/server_verification.md).

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

**Left and right, up and down.** `lookLeft` means the *user's* left.
Calibrated for Android and iPhone; if some device gets it backwards,
`mirrorYaw: false` flips it. `invertPitch: true` does the same for
`lookUp`, `lookDown` and `nod` (the up/down sign hasn't been confirmed on
every iPhone yet; `showDebugOverlay` shows the live pitch).

**Give people time — but not forever.** Each action has a 15-second limit
(`actionTimeout`), users get 10 seconds to return to a neutral face
between actions (`neutralTimeout`), and the whole session ends after 2
minutes (`sessionTimeout`, `null` to disable). For users who find the
actions difficult, use fewer/easier actions (blink, smile), longer
timeouts, and `requireNeutralBetweenActions: false`. A second face in the
background is ignored if it's small, and only fails the session if it
stays for more than half a second (`multipleFacesGrace`).

**It needs light — but it tells the user.** Too-dark, overexposed, and
blurry frames pause the session with a hint like "Find better lighting".
The action's timer keeps running while paused, so a room that stays too
dark ends in `actionTimeout` rather than hanging. Thresholds:
`brightnessMin`, `brightnessMax`, `sharpnessMin`; disable with
`enableQualityChecks: false`.

**Same person throughout?** With ML Kit tracking (on unless an action
needs contours), a face ID that changes while a face stays in view lowers
the confidence score and shows up in `metadata['identity_*']`, along with
jumps in rough face geometry. Set `failOnFaceChange: true` to fail such
sessions outright. It's off by default because a very fast head turn can
make some devices re-assign the ID. This is no substitute for server-side
face matching.

**The anti-spoof checks are honest heuristics, not magic.** The
*static-feed guard* (called the replay guard before 0.5; the setting is
still `enableReplayGuard`) catches input that can't come from a live
camera: pixel-identical frames fail the session, and near-identical frames
with a frozen face box (a re-encoded still injected as a camera) lower the
confidence score. Micro-motion flags unnaturally still sessions the same
way. **None of it detects a photo, screen or video held up to a real
camera**: the real camera adds real noise and the hand adds real motion.
That's what the actions, the colour flash, and server-side review of the
captured media are for. If the guard ever misfires on a device (it
shouldn't — real sensors are noisy), `enableReplayGuard: false` turns it
off.

---

<div align="center">

**Found a bug? Have an idea?** [Open an issue](https://github.com/maykhid/liveness_flutter/issues) — anyone can, and PRs are welcome too. 🙌

Made with ❤️ for developers who'd rather not pay per verification.

</div>
