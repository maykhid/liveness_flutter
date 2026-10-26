# liveness_flutter

**Face liveness checks for Flutter — free, on-device, and built for *your* backend.**

*Blink. Smile. Turn left. Verified.*

<table>
  <tr>
    <td align="center">
      <img src="https://raw.githubusercontent.com/maykhid/liveness_flutter/main/screenshots/default_demo.gif" width="240" alt="The default screen: tap Verify, blink, turn left and smile inside an oval, then Passed with 100% confidence"/><br/>
      <sub><b>Out of the box</b> — about 10 lines of code</sub>
    </td>
    <td align="center">
      <img src="https://raw.githubusercontent.com/maykhid/liveness_flutter/main/screenshots/fintech_demo.gif" width="240" alt="A fully branded account-upgrade flow: account home, intro, a face check in a circle with nod and blink steps, then verified"/><br/>
      <sub><b>Fully branded</b> — <a href="examples.md#a-fully-branded-kyc-flow">your design</a></sub>
    </td>
  </tr>
</table>

> **Beta** — tested on real Android and iOS devices; the API may still
> change before 1.0 ([details](limitations.md#status-beta)). Anyone can
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

## Why this package?

| | |
|---|---|
| **Proves a live person is there** | The user does random actions — blink, smile, turn, nod, 13 to choose from — in a new order every time, so a photo or a pre-recorded video can't follow along. |
| **Catches common tricks on the phone** | Frozen or injected camera feeds, an unnaturally still "face", a second or swapped face, bad lighting — plus an optional screen-flash test against replayed videos. No ML model to download. |
| **Gives your server the evidence** | A photo at the peak of each action (eyes shut for a blink), or video, with hashes and an optional server-issued challenge, so your backend can verify instead of trusting the phone. |
| **Looks like your app** | Theme every color and word, or replace the screen with your own design — see the [branded fintech example](examples.md#a-fully-branded-kyc-flow). |
| **Free and light** | Pure Dart plus Google's on-device ML Kit. No per-check fees, no account, no server of ours. |

## Is this right for you?

**A great fit for** sign-up and onboarding gates, confirming it's really
the user before a sensitive action, marketplace and gig-worker checks, and
KYC flows where your backend also reviews the photos.

**Pair it with server checks for** anything regulated or with money on
the line. The phone's verdict alone can be tampered with: follow the
[server verification guide](server_verification.md) and review the
photos server-side (face match, presentation-attack detection).

**Not the right tool if** you need *certified* liveness — for example, a
passed ISO/IEC 30107-3 presentation-attack evaluation such as iBeta's —
or protection against sophisticated masks and deepfakes. That takes a
trained anti-spoof model and usually a paid provider. This package can
[plug such a model in](server_binding.md#bring-your-own-anti-spoof-model)
but doesn't ship one.

## How it works

<img src="https://raw.githubusercontent.com/maykhid/liveness_flutter/main/screenshots/how_it_works.png" width="720" alt="Camera, then ML Kit finds the face, then actions and checks, then onResult on the phone (offline); you send the result to your server, which verifies and decides"/>

1. The camera streams frames, and Google's ML Kit finds the face — on the
   phone, offline.
2. The package asks for each action in turn and checks it was really done,
   while watching for frozen feeds, a second face and poor light.
3. `onResult` gives you one `LivenessResult`: pass or fail, a confidence
   score, and the photos if you asked for them.
4. You send it to your server, which can verify it before trusting it.

## Pick your path

| You want to… | Go to |
|---|---|
| Have an AI coding agent do the integration | **[Agent skills](agent_skills.md)** — one command |
| Add a working liveness check to your app | **[Getting started](getting_started.md)** — about 10 minutes |
| See every example, or run one | [Examples](examples.md) |
| Make it look like your app (colors, text, your own screens) | [Customization](customization.md) and the [fintech example](examples.md#a-fully-branded-kyc-flow) |
| Use it for KYC or anything with real consequences | [Bind sessions to your server](server_binding.md) |
| Have an agent verify someone else | [Assisted mode](assisted_mode.md) |
| Quick answers (offline? app size? masks?) | [FAQ](faq.md) |
| Know the limits before shipping | [Honest notes](limitations.md) |
