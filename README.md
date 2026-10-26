<div align="center">

# 🛡️ liveness_flutter

**Face liveness checks for Flutter — free, on-device, and built for *your* backend.**

[![pub package](https://img.shields.io/pub/v/liveness_flutter.svg)](https://pub.dev/packages/liveness_flutter)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-green.svg)](#)
[![No ML models](https://img.shields.io/badge/models-none%20to%20download-orange.svg)](#)
[![Status: beta](https://img.shields.io/badge/status-beta-yellow.svg)](doc/limitations.md#status-beta)

*Blink. Smile. Turn left. Verified.* ✅

<table>
  <tr>
    <td align="center">
      <img src="https://raw.githubusercontent.com/maykhid/liveness_flutter/main/screenshots/default_demo.gif" width="240" alt="The default screen: tap Verify, blink, turn left and smile inside an oval, then Passed with 100% confidence"/><br/>
      <sub><b>Out of the box</b> — about 10 lines of code</sub>
    </td>
    <td align="center">
      <img src="https://raw.githubusercontent.com/maykhid/liveness_flutter/main/screenshots/fintech_demo.gif" width="240" alt="A fully branded account-upgrade flow: account home, intro, a face check in a circle with nod and blink steps, then verified"/><br/>
      <sub><b>Fully branded</b> — <a href="doc/examples.md#a-fully-branded-kyc-flow">your design</a></sub>
    </td>
  </tr>
</table>

</div>

> 🧪 **Beta** — tested on real Android and iOS devices; the API may still
> change before 1.0 ([details](doc/limitations.md#status-beta)). Anyone can
> [open an issue](https://github.com/maykhid/liveness_flutter/issues).

Add a face liveness check to your Flutter app in a few lines. The user
blinks, smiles or turns their head when asked; the package checks a live
person did it, then hands you the result — and the photos, if you want
them — to send **wherever you want**.

```dart
LivenessDetector(
  config: const LivenessConfig(
    actions: [LivenessAction.blink, LivenessAction.smile, LivenessAction.lookLeft],
    shuffleActions: true,          // a new order every time
    capture: {CaptureType.images}, // photos your server can check
  ),
  onResult: (result) {
    if (result.success) sendToYourServer(result);
  },
)
```

Everything runs on the phone. **No cloud service. No license fees. No
model downloads. No account.**

**Requirements:** Flutter 3.38+ · Android 7.0+ (API 24) · iOS 15.5+

## ✨ Why this package?

| | |
|---|---|
| 🎯 **Proves a live person is there** | The user does random actions — blink, smile, turn, nod, 13 to choose from — in a new order every time, so a photo or a pre-recorded video can't follow along. |
| 🕵️ **Catches common tricks on the phone** | Frozen or injected camera feeds, an unnaturally still "face", a second or swapped face, bad lighting — plus an optional screen-flash test against replayed videos. No ML model to download. |
| 📸 **Gives your server the evidence** | A photo at the peak of each action (eyes shut for a blink), or video, with hashes and an optional server-issued challenge, so your backend can verify instead of trusting the phone. |
| 🎨 **Looks like your app** | Theme every color and word, or replace the screen with your own design — see the [branded fintech example](doc/examples.md#a-fully-branded-kyc-flow). |
| 🪶 **Free and light** | Pure Dart plus Google's on-device ML Kit. No per-check fees, no account, no server of ours. |

## 🚀 Install

```yaml
dependencies:
  liveness_flutter: ^0.6.0
```

**Android:** set `minSdkVersion 24`. **iOS:** set `platform :ios, '15.5'`
in `ios/Podfile` and add a camera description to `ios/Runner/Info.plist`
(without it the app crashes on camera use):

```xml
<key>NSCameraUsageDescription</key>
<string>Camera is used for liveness verification.</string>
```

Then follow **[Getting started](doc/getting_started.md)**: show the
screen, read the result, send it to your server, in about 10 minutes.

> 🤖 **Using an AI coding agent?** Run `dart run liveness_flutter:skills`
> from your app's root and the [agent skills](doc/agent_skills.md) teach
> Claude Code, Codex, Cursor, Copilot, Gemini CLI and others how to do the
> integration and the backend checks.

## 📖 Documentation

| You want to… | Read |
|---|---|
| Add a working check to your app | [Getting started](doc/getting_started.md) |
| See every example, or run one | [Examples](doc/examples.md) |
| Make it look like your app | [Customization](doc/customization.md) · [Controller](doc/controller.md) |
| Use it for KYC or anything with real consequences | [Bind sessions to your server](doc/server_binding.md) · [Server verification](doc/server_verification.md) |
| Capture photos, video or frames | [Capture guide](doc/capture_and_media.md) |
| Stop replayed videos | [Color-flash challenge](doc/flash_challenge.md) |
| Have an agent verify someone else | [Assisted mode](doc/assisted_mode.md) |
| Every field in the result | [Result reference](doc/result_reference.md) |
| Debug overlay, callbacks, test bench | [Developer tools](doc/developer_tools.md) |
| Quick answers (offline? app size? masks?) | [FAQ](doc/faq.md) |
| Know the limits before shipping | [Honest notes](doc/limitations.md) |

## ⚠️ Before you ship

This is not certified liveness, and it doesn't detect masks or deepfakes
on its own. All checks run on the phone, which a determined attacker
controls, so for anything with money on the line have your server verify
the upload and review the photos. The [honest notes](doc/limitations.md)
cover every rough edge and the setting that changes it.

## 🧪 Status: beta

Tested on real Android and iOS devices, but the API may change before
1.0. A minor release (0.5 → 0.6) can include breaking changes; each one is
listed under **Breaking** in the [CHANGELOG](CHANGELOG.md). Depend on
`^0.6.0` and you'll only get compatible updates.

---

<div align="center">

**Found a bug? Have an idea?** [Open an issue](https://github.com/maykhid/liveness_flutter/issues) — anyone can, and PRs are welcome too. 🙌

Made with ❤️ for developers who'd rather not pay per verification.

</div>
