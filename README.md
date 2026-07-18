# liveness_flutter

Add face liveness checks to your Flutter app in minutes — free, and it works
with **your own backend**.

You give it a list of actions (blink, smile, turn left…). It shows the
camera, guides the user through each action in order, and checks that a real
live person performed them. When it's done, it hands you the results —
optionally with photos and/or video — and you send them wherever you want.
Everything runs on the phone. No cloud service, no license fees, no
account.

## What it can do

- **13 actions**, run in the order you list them: `blink`, `smile`,
  `fullTeethSmile`, `nod`, `lookLeft`, `lookRight`, `lookUp`, `lookDown`,
  `tiltLeft`, `tiltRight`, `eyesClosed`, `openMouth`, and an experimental
  `drawCircleWithNose`.
- **Optional photos & video.** Capture nothing, a photo per completed
  action, a full video, a steady stream of photos ("frame sequence" — more
  on that below), or any mix.
- **Your backend, your rules.** When the check finishes you get one result
  object with everything in it. Upload it with any tool you like. A ready-made
  HTTP uploader is included if you just want to POST it somewhere.
- **Make it look like your app.** Colors, text, sizes are all changeable —
  or replace whole parts of the screen with your own widgets.
- **Built-in protections** — all without heavy ML models or downloads:
  - Only one face allowed, a time limit per action, a required "neutral
    face" between actions.
  - Optional random action order (`shuffleActions`) so a pre-recorded video
    can't pass.
  - **Replay guard**: a real camera never produces two pixel-identical
    frames (sensor noise). A long run of identical frames means a static
    image or injected feed — the session fails with `spoofSuspected`.
  - **Micro-motion check**: a live head is never perfectly still. Sessions
    with unnaturally frozen head angles get a lower confidence score.
  - **Light & focus checks**: too-dark, overexposed, or blurry frames pause
    the session with a clear hint ("Find better lighting") instead of
    silently failing.
- **Confidence score & audit ID**: every result carries a 0–1
  `confidenceScore` (with the individual penalty counters in `metadata` so
  your server can re-weigh them) and a unique, securely random `sessionId`
  for audit trails.
- **Smart user hints**: the state tells you exactly what's wrong right now
  — `tooFar`, `tooClose`, `notCentered`, `lowLight`, `blurry`,
  `multipleFaces` — and the default UI shows a matching message (all
  translatable).
- **Debug overlay** for development: set `showDebugOverlay: true` on the
  widget to see live head angles, eye/smile probabilities, brightness, and
  replay-guard counters on screen while you tune thresholds.

## Quick start

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

Why `shuffleActions: true`? If the actions always come in the same order,
someone could record a video of a person doing that exact sequence and play
it to the camera. Random order means a recording made yesterday won't match
today's sequence.

## Setting up Android and iOS

**Android**: set `minSdkVersion 21` in your app.

**iOS**: add this to `ios/Runner/Info.plist` (it's the message shown when
iOS asks for camera permission — without it the app crashes on camera use):

```xml
<key>NSCameraUsageDescription</key>
<string>Camera is used for liveness verification.</string>
```

Also set `platform :ios, '15.5'` in `ios/Podfile` (the face detection
library needs iOS 15.5 or newer).

## Photos, video, and "frame sequence" — which do I pick?

| You want | Use | Notes |
|---|---|---|
| A photo of each completed action | `CaptureType.images` | Smallest uploads. Works everywhere. Best default. |
| A real video file of the session | `CaptureType.video` | Works well on iPhones. On many Android phones the camera can't record and detect at the same time — see below. |
| Something video-like that works on every phone | `CaptureType.frameSequence` | Takes a photo several times per second for the whole session. You get a list of photos, not a video file — but played one after another they look like a video. |

**The Android video problem, in plain words:** detecting your face and
recording a video both need the camera at the same time. iPhones handle
that fine. Many Android phones can't — and there's no official way to ask a
phone in advance. So this package gives you three tools:

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

## What you get back

`onResult` gives you a `LivenessResult` with:

- `success` — did the person complete all actions in time?
- `confidenceScore` — 0 to 1. A clean run on a real camera scores 0.9+.
  Duplicate frames, a frozen head, or many bad-quality frames pull it down.
  The raw counters are in `metadata` under `confidence_*` keys.
- `sessionId` — unique audit ID (e.g. `LV-018F3A2B9C4E-D7E31F08`)
- `completedActions` — which actions, in the order they were performed
- `images` — the photos, each labeled with the action it belongs to
- `frameSequence` — the steady-stream photos, each with a timestamp
- `videoPath` — where the video file is, if you recorded one
- `failureReason` — why it failed (took too long, face left the screen,
  more than one face, replay/static input suspected, user cancelled…)
- `metadata` — extras like how long each action took

## Sending results to your server

You never *have* to use anything built-in — `onResult` gives you the data,
and any upload code you already have will do. For convenience:

```dart
// The common case: POST everything as a multipart form.
await HttpLivenessUploader(
  endpoint: Uri.parse('https://api.example.com/liveness'),
  headers: {'Authorization': 'Bearer …'},
).upload(result);

// Or wrap your own function (dio, Firebase, S3, anything):
final uploader = LivenessUploader.custom((result) async {
  // your code here
});
```

## Making it look like your app

- `LivenessTheme` — colors, borders, text styles, the size of the face
  oval, and **every piece of text** (so you can translate it).
- `overlayBuilder` / `instructionBuilder` — swap out the dimmed overlay or
  the instruction text area entirely with your own widgets. Both receive
  the live session state and rebuild on every change. Useful fields:
  `state.phase`, `state.currentAction`, `state.completedActions`,
  `state.actionProgress` (current action, 0–1), `state.overallProgress`
  (whole session), `state.faceInPosition`, `state.remaining` (time left).

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
  // on top of the default-style scrim you draw yourself.
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
  centered — the face-position check expects the face near the middle of
  the frame.
- `DetectorTuning` — how strict each action is (how big a smile counts, how
  far to turn your head, how long to hold it…). The defaults are tested,
  but everything is adjustable.

## Photo/video size and cleanup

- **Photo size**: `maxImageDimension` (default 720 pixels on the longest
  side) and `jpegQuality` (default 85; lower = smaller files).
- **Video size**: `cameraResolution` on the `LivenessDetector` widget.
- **Cleanup**: photos live only in memory — they disappear on their own
  when you're done with the result. The **video is a real file on the
  phone** and is *not* deleted automatically. Upload or copy it in
  `onResult`, then either delete it yourself or set
  `LivenessConfig(autoDeleteVideo: true)` to have it deleted when the
  camera screen closes.

## Honest notes — read before shipping

Plain-language notes on the rough edges. Every one has a setting you can
change; nothing requires forking the package.

**This is not bank-grade security on its own.** All checking happens on the
phone, and a determined attacker controls their own phone. Treat a passing
result as a good first gate, and have your server double-check the photos/
video you upload (compare against an ID photo, look for signs of screens or
prints). That's exactly why this package captures media *during* the
actions.

**Memory adds up if you turn everything up.** Photos are kept in memory
until the result is delivered. Defaults use roughly 15–35 MB per session.
If you raise the frame rate (`frameSequenceFps`, up to 15/sec) *and* the
photo size (`maxImageDimension`) at the same time, cheap Android phones can
run out of memory. `frameSequenceMaxFrames` caps the total as a safety net.

**Every face and phone is a little different.** How confidently the phone
detects a smile or a head turn varies with the camera, lighting, glasses,
and the person. If one action fails too often for your users, loosen its
setting in `DetectorTuning` — that's what it's for. The two most sensitive
actions: `fullTeethSmile` (depends on how well the phone sees lips) and
`eyesClosed` (we ignore brief flickers where the phone wrongly thinks eyes
opened; `eyesOpenTolerance` controls how brief).

**`drawCircleWithNose` is a fun extra, not a workhorse.** People need to
move their whole head in a circle, not just look around, and small/slow
circles don't count. Expect more retries than other actions. Test it on
your users' actual phones before making it mandatory.

**Left and right.** `lookLeft` means the *user's* left. We've calibrated
this for Android and iPhone, but if some device gets it backwards, set
`mirrorYaw: false` to flip it.

**Give people time.** Each action has a 15-second limit
(`actionTimeout`) and users must return to a neutral face between actions.
For users who find the actions difficult, use fewer/easier actions (blink,
smile), a longer timeout, and `requireNeutralBetweenActions: false`.

**It needs light — but now it tells the user.** Face detection struggles in
the dark. The package detects too-dark, overexposed, and blurry frames,
pauses (it won't fail the session over lighting), and shows a hint like
"Find better lighting". Thresholds: `brightnessMin`, `brightnessMax`,
`sharpnessMin`; turn the whole check off with `enableQualityChecks: false`.

**The anti-spoof checks are honest heuristics, not magic.** The replay
guard catches static images and naive injected feeds; the micro-motion
check flags unnaturally still sessions in the confidence score. Neither
will stop a sophisticated attacker with a high-quality replay rig — that's
what server-side review of the captured photos/video is for. If the replay
guard ever misfires on a specific device (it shouldn't — real sensors are
noisy), `enableReplayGuard: false` turns it off.
