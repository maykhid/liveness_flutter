# FAQ

**Does it work offline?** Yes. Face detection is Google's on-device ML
Kit, and nothing is sent anywhere unless your code sends it.

**Do I need a Firebase project or a paid ML Kit plan?** No. ML Kit's
on-device face detection is free and needs no account or project.

**Does it detect masks or deepfakes?** Not reliably on its own. The
actions, the static-feed guard and the flash challenge stop the cheap
attacks (photos, frozen feeds, many replayed videos); masks and deepfakes
need a trained anti-spoof model, which you can
[plug in](server_binding.md#bring-your-own-anti-spoof-model) with
`frameAnalyzers`, and server-side review.

**How much does it add to my app?** Mostly ML Kit's face-detection model,
which ships inside your app. Check the real number for your build with
`flutter build apk --analyze-size` (or `ipa` on iOS).

**Does it store or upload anything?** No. Photos are kept in memory until
`onResult`; the video (if you record one) is a temporary file. Where the
result goes is entirely up to your code.

**Web or desktop?** Not yet — Android and iOS only.
