# Getting started

Four steps to a working check. Everything here uses defaults; the guides
cover the rest.

> **Using a coding agent?** Do step 1, then run
> `dart run liveness_flutter:skills` from your app's root and ask your
> agent to do steps 2 to 4. The [agent skills](agent_skills.md) tell it
> how.

## 1. Install and set up the platforms

```yaml
dependencies:
  liveness_flutter: ^0.6.0
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

## 2. Show the liveness screen

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

> **`onResult` is called exactly once** per session — even if the
> screen is closed before the check finishes (system back, route popped).
> In that case the result is `cancelled` with
> `metadata['cancelledBy'] == 'dispose'` and arrives just after the screen
> is gone, which is why the guard above matters. `cancelledBy` is `'user'`
> for the close button and `'lifecycle'` when the app goes to the
> background.

> **Why shuffle?** If actions always come in the same order, someone
> could record a video of a person doing that exact sequence and play it to
> the camera. Random order means yesterday's recording won't match today's.
>
> Include at least one **motion** action (`blink`, `nod`, `openMouth`,
> `drawCircleWithNose`). Pose-only actions (`smile`, `tiltLeft`/`tiltRight`,
> `lookUp`/`lookDown`) can be faked with a photo tilted or swapped at the
> right moment.

## 3. Read the result

The essentials of `LivenessResult`:

- `success` — did the person complete all actions in time?
- `failureReason` — why not (took too long, face left the screen, more
  than one face, static/injected input suspected, camera access denied,
  user cancelled…)
- `confidenceScore` — 0 to 1. A clean run on a real camera scores 0.9+.
- `images` — the photos, each labeled with its action and `kind`
  (`reference`, or `peak`: the moment the action was clearest, e.g. eyes
  shut for a blink)
- `sessionId` — a unique audit ID (e.g. `LV-018F3A2B9C4E-D7E31F08`)

`debugPrint(result.toString())` prints a readable summary, and
`result.toJson()` gives a JSON-safe one (no image bytes). The
[full list of fields](result_reference.md) has the rest.

## 4. Send it to your server

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

It sends a `metadata` field with `result.evidenceJson` (`toJson()`
without the attestation: session ID, confidence, actions, a SHA-256 of
every photo…), the attestor's token in an `attestation` field when there
is one, one file per photo named like `blink_peak_812ms.jpg`, and an
`X-Liveness-Session` header. Any
transport works instead: `LivenessUploader.custom((result) async { ... })`
wraps dio, S3, Firebase or anything else.

> **Show a progress bar.** With photos an upload can be several MB. A
> common pattern: close the camera screen straight away and upload from
> the previous screen with a `LinearProgressIndicator` driven by
> `onProgress`.

**That's it** — you have a working liveness check. The complete runnable
version of these steps is
[`example/lib/main.dart`](https://github.com/maykhid/liveness_flutter/blob/main/example/lib/main.dart).
Before using it for anything with real consequences, read
[Bind sessions to your server](server_binding.md) and the
[honest notes](limitations.md).
