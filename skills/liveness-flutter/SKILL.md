---
name: liveness-flutter
description: Integrates the liveness_flutter package (on-device face liveness checks for Flutter using Google ML Kit) into a Flutter app. Covers Android and iOS setup, showing LivenessDetector, choosing and tuning actions, theming or a fully custom UI, LivenessController, capturing photos or video, uploading results, server challenges, attestation and custom anti-spoof models. Use when code imports package:liveness_flutter, pubspec.yaml lists liveness_flutter, or the user wants a liveness, selfie, face verification or KYC face check in a Flutter app.
license: MIT
metadata:
  package: liveness_flutter
  written-for: "0.6.0"
---

# liveness_flutter

liveness_flutter asks the user to do random actions (blink, smile, turn,
nod, 13 in all), checks them on the phone with Google ML Kit, and hands
the app one `LivenessResult` with the verdict and, if asked, the photos.
It is Android 7+ (API 24) and iOS 15.5+ only, needs Flutter 3.38+, and
ships no ML model and no backend.

## Before you write code

1. **Check the installed version.** Read `pubspec.lock` for
   `liveness_flutter`. This skill was written for the version in its
   `metadata.written-for`. The package is pre-1.0, so a minor version
   (0.5 → 0.6) can break the API; each break is listed under **Breaking**
   in the package's `CHANGELOG.md`.
2. **When in doubt, read the installed source.** Find the package root in
   `.dart_tool/package_config.json` (the `rootUri` of `liveness_flutter`).
   `lib/src/models/models.dart` has every config field with its doc
   comment and default, and `doc/` has the long-form guides. The installed
   source beats this skill if they disagree.
3. **Ask, or infer, what a pass unlocks.** It decides how much to build:
   - *Low stakes* (a sign-up gate, a "is a person there" check): the
     detector and `onResult` are enough.
   - *Anything with money, identity or regulation on the line* (KYC,
     account recovery, payouts): also capture `{CaptureType.images}`, get
     a challenge from the server, upload the result, verify it on the
     server, and plan an attestor. A `success: true` from the phone is a
     claim, not proof.

## Rules that are easy to get wrong

- **`onResult` is called exactly once per session, even after the screen
  is gone.** When the route is popped first, the result is `cancelled`
  with `metadata['cancelledBy'] == 'dispose'` and the widget's context is
  already unmounted. Always guard navigation:
  `if (!context.mounted) return;` and pop only when
  `ModalRoute.of(context)?.isCurrent ?? false`.
- **Include at least one motion action**: `blink`, `nod`, `openMouth` or
  `drawCircleWithNose`. Every other action is pose-only (`smile`,
  `fullTeethSmile`, `lookLeft`, `lookRight`, `lookUp`, `lookDown`,
  `tiltLeft`, `tiltRight`, `eyesClosed`) and can be faked with a photo
  tilted at the right moment.
- **Randomize.** Use `shuffleActions: true`, or `randomActionCount` to pick
  N actions from a pool, or (best) a server-issued `LivenessChallenge`.
  `randomActionCount` doesn't guarantee a motion action unless every
  action in the pool is one.
- **Never build the challenge in the app for anything real.** A challenge
  only binds the session when the server made it and checks it later.
  With a challenge set, pass `actions: const []`: the challenge's actions
  and order win.
- **`config` is read once per session.** Changing it on rebuild doesn't
  touch the running session. To apply a new config, give
  `LivenessDetector` a new `key`, or rebuild with it and then call
  `LivenessController.restart()`.
- **Nothing is captured by default.** `capture` is `{}`. The server has
  nothing to check unless you ask for `{CaptureType.images}`.
- **`CaptureType.video` is unreliable on many Android phones.** Call
  `LivenessCapabilities.supportsVideoCapture()` first, or use
  `CaptureType.frameSequence`, which works everywhere.
- **The video is a real temp file.** Upload or copy it in `onResult`, then
  delete it or set `autoDeleteVideo: true`. Photos live only in memory.
- **`HttpLivenessUploader.upload()` throws** `LivenessUploadException` on
  a non-2xx answer and `TimeoutException` on a timeout. Wrap it.
- **Physical devices only.** Simulators and emulators have no usable front
  camera; don't try to verify the flow on one.
- **Don't oversell it.** This is not certified liveness (no ISO/IEC
  30107-3 or iBeta result) and it does not reliably detect masks or
  deepfakes. Don't write UI copy, comments or docs that claim otherwise.
  For that, plug a trained model into `frameAnalyzers` and review the
  photos on the server.

## The smallest correct integration

After the platform setup in [references/setup.md](references/setup.md):

```dart
import 'package:flutter/material.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

class LivenessPage extends StatelessWidget {
  const LivenessPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LivenessDetector(
        config: const LivenessConfig(
          actions: [
            LivenessAction.blink, // a motion action
            LivenessAction.smile,
            LivenessAction.lookLeft,
          ],
          shuffleActions: true,
          capture: {CaptureType.images},
        ),
        onResult: (result) {
          if (!context.mounted) return;
          if (ModalRoute.of(context)?.isCurrent ?? false) {
            Navigator.pop(context, result);
          }
        },
      ),
    );
  }
}

/// Opens the check and returns its result, or null if the user left with
/// system back before it finished.
Future<LivenessResult?> runLivenessCheck(BuildContext context) {
  return Navigator.push<LivenessResult>(
    context,
    MaterialPageRoute(builder: (_) => const LivenessPage()),
  );
}
```

Then act on `result.success`, `result.failureReason` and
`result.confidenceScore`, and send the result to the server if a pass
matters.

## Reference files

Read only the one the task needs:

| Task | Read |
|---|---|
| Install, Android/iOS setup, reading the result, handling each failure reason | [references/setup.md](references/setup.md) |
| Which actions to ask for, timeouts, capture, quality checks, flash challenge, assisted mode, `DetectorTuning` | [references/configuration.md](references/configuration.md) |
| Colors, text and localization, your own overlay or instructions, `targetRegion`, `LivenessController`, callbacks | [references/custom-ui.md](references/custom-ui.md) |
| Uploading, server challenges, writing a `LivenessAttestor`, plugging in an anti-spoof model | [references/backend.md](references/backend.md) |
| Something misbehaves on a device: face never "in position", turns inverted, sessions failing | [references/troubleshooting.md](references/troubleshooting.md) |

The server side of the integration (checking nonces, hashes and
attestation tokens) has its own skill, `liveness-flutter-server`. If it
isn't installed, the package's `doc/server_verification.md` covers it.

## Checking your work

- `flutter analyze` passes.
- Every navigation in `onResult` is guarded by `context.mounted`.
- Every session gets at least one motion action: it's in the fixed list,
  every action in a `randomActionCount` pool is one, or the server
  guarantees one in each challenge.
- High-stakes flows capture images, use a server challenge and upload.
- For tuning on a real device, `showDebugOverlay: true` shows live head
  angles, eye and smile probabilities, brightness and a box where ML Kit
  sees the face. Remove it before release.
