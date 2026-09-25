# liveness_flutter example

Runnable demo: pick actions, choose capture modes, run a liveness session,
view captured images, and optionally upload to your API.

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

Point the endpoint field at any server that accepts multipart POSTs. Quick
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
