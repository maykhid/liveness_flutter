# liveness_flutter examples

Start small, then pick the recipe you need. Each file runs on its own with
`flutter run -t <file>` (on a **physical device**; simulators have no
usable front camera).

| File | What it shows |
|---|---|
| [`lib/main.dart`](lib/main.dart) | **Start here.** The smallest useful integration: about 90 lines. |
| [`lib/recipes/custom_ui.dart`](lib/recipes/custom_ui.dart) | Your own overlay and instructions, with `targetRegion` so detection follows your window. |
| [`lib/recipes/controller.dart`](lib/recipes/controller.dart) | Your own Cancel / Try again buttons and live state via `LivenessController`. |
| [`lib/recipes/server_bound.dart`](lib/recipes/server_bound.dart) | A challenge from your backend, then upload with error handling. Pass `--dart-define=BACKEND_URL=https://…`. |
| [`lib/recipes/fintech/`](lib/recipes/fintech/main.dart) | A fully branded KYC flow for a fictional fintech ("AcmePay"): account home → intro and tips → restyled face check → verifying → success or failure help. Brand colours and wording live in `brand.dart`. |
| [`lib/test_bench/main.dart`](lib/test_bench/main.dart) | Every option behind a settings screen, for trying the package on a device. Not a starting point. |

```bash
flutter run                                   # lib/main.dart
flutter run -t lib/recipes/fintech/main.dart  # the branded flow
flutter run -t lib/test_bench/main.dart       # the test bench
```

### About the test bench

Presets, grouped settings for every option, a live log of every callback,
a `LivenessController` bar, and a result page that runs the checks from
`doc/server_verification.md` (nonce, action order, media hashes,
attestation). Its "server", attestor and anti-spoof model are in-app fakes
in `lib/test_bench/src/insecure_fakes.dart` so everything works offline.
**None of them is secure**: in a real app they live on your backend or come
from Play Integrity / App Attest and a trained model.

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

In the test bench, set the endpoint under **Upload**, run a session, and
tap **Upload** on the result page (or use `lib/recipes/server_bound.dart`
with `BACKEND_URL`). Any server that accepts multipart POSTs works. Quick
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
