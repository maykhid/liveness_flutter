# liveness_flutter example

Runnable demo: pick actions, choose capture modes, run a liveness session,
view captured images, and optionally upload to your API.

## What's in it

A test bench for every option in the package:

- **Presets**: Quick test, Server-bound (KYC), Everything on, Accessible.
- **Settings** grouped by area: actions (with `randomActionCount` and a
  warning when there's no motion action), timeouts, capture, security
  (server challenge, attestation, anti-spoof analyzer, colour flash,
  static-feed guard, face-change failure), camera and detection
  (`mirrorYaw`, `invertPitch`, debug overlay), look and feel (target
  shape and size, custom UI with `targetRegion`, light theme, partial
  French strings, haptics), permissions and upload.
- **On the liveness screen**: a live event log of every callback, and
  optionally a `LivenessController` bar (cancel, restart, plan, time left)
  in place of the close button, plus an in-screen "camera access is off"
  page.
- **Result page**: outcome and reason, confidence, the **simulated server
  checks** from `doc/server_verification.md` (nonce, action order, media
  hashes, attestation), anti-spoof signals, photos labelled with their
  kind and timestamp, frame-sequence and video playback, the event log,
  the raw `toJson()`, and upload with progress and error reporting.
- **What to test**: a checklist on the home screen, including a button
  that starts a session with an invalid config.

The "server", attestor and anti-spoof model are in-app fakes
(`lib/src/demo_security.dart`) so everything works offline. **None of
them is secure**: in a real app they live on your backend or come from
Play Integrity / App Attest and a trained model.

## Run it

If you cloned the repository, `android/` and `ios/` are already set up:
skip to "Finally" below.

The package published on pub.dev leaves the platform folders out, so if
you got the example from there, generate them:

```bash
cd example
flutter create --platforms android,ios .
```

Then apply these one-time edits:

**Android** — in `android/app/build.gradle` (or `build.gradle.kts`), make
sure the minimum SDK is at least 24 (recent Flutter templates already use
`flutter.minSdkVersion`, which is 24):

```
minSdk = 24
```

**iOS** — in `ios/Runner/Info.plist`, add inside `<dict>`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera is used for liveness verification.</string>
```

and in `ios/Podfile`, set `platform :ios, '15.5'` and (for
`permission_handler`) add inside `post_install`:

```ruby
installer.pods_project.targets.each do |target|
  target.build_configurations.each do |config|
    config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)', 'PERMISSION_CAMERA=1']
  end
end
```

Finally:

```bash
flutter pub get
flutter run
```

Use a **physical device** — simulators/emulators have no usable front camera.

## Testing the upload

Set the endpoint on the home screen, run a session, and tap **Upload** on
the result page. Any server that accepts multipart POSTs works. Quick
local test:

```bash
# http-echo style; or use webhook.site and paste its URL
npx http-echo-server 8080
```

Fields sent: `metadata` (`LivenessResult.toJson()`: session ID, confidence,
actions, SHA-256 of every photo), `images[i]` (JPEGs named like
`blink_peak_812ms.jpg`), `frames[i]` (if captured), `video` (if recorded),
and an `X-Liveness-Session` header. A non-2xx answer makes the upload throw
`LivenessUploadException`.
