---
template: home.html
title: Face liveness for Flutter
hide:
  - navigation
  - toc
---

# Liveness Flutter

**Face liveness checks for Flutter — free, on-device, and built for *your* backend.**

> **Beta** — tested on real Android and iOS devices; the API may still
> change before 1.0 ([details](limitations.md#status-beta)). Anyone can
> [open an issue](https://github.com/maykhid/liveness_flutter/issues).

## A check in a few lines

The user blinks, smiles or turns their head when asked; the package checks
a live person did it, then hands you the result — and the photos, if you
want them — to send **wherever you want**.

```dart
LivenessDetector(
  config: const LivenessConfig(
    actions: [LivenessAction.blink, LivenessAction.smile, LivenessAction.lookLeft],
    shuffleActions: true,          // (1)!
    capture: {CaptureType.images}, // (2)!
  ),
  onResult: (result) {
    if (result.success) sendToYourServer(result);
  },
)
```

1. A new order every time, so yesterday's recording won't match today's.
2. A photo at the peak of each action, for your server to check.

**Requirements:** Flutter 3.38+ · Android 7.0+ (API 24) · iOS 15.5+

## Why this package?

<div class="grid cards" markdown>

-   :material-face-recognition:{ .lg .middle } **Proves a live person is there**

    ---

    Random actions — blink, smile, turn, nod, 13 to choose from — in a new
    order every time, so a photo or a pre-recorded video can't follow along.

-   :material-incognito-off:{ .lg .middle } **Catches common tricks**

    ---

    Frozen or injected camera feeds, an unnaturally still "face", a second
    or swapped face, bad lighting — plus an optional
    [screen-flash test](flash_challenge.md) against replayed videos.

-   :material-server-security:{ .lg .middle } **Gives your server the evidence**

    ---

    A photo at the peak of each action, or video, with hashes and an
    optional [server-issued challenge](server_binding.md), so your backend
    can verify instead of trusting the phone.

-   :material-palette:{ .lg .middle } **Looks like your app**

    ---

    Theme every color and word, or replace the screen with your own design
    — see the [branded fintech example](examples.md#a-fully-branded-kyc-flow).

-   :material-feather:{ .lg .middle } **Free and light**

    ---

    Pure Dart plus Google's on-device ML Kit. No per-check fees, no
    account, no server of ours.

-   :material-robot:{ .lg .middle } **Agent-ready**

    ---

    One command installs [agent skills](agent_skills.md) that teach your
    coding agent the integration and the backend checks.

</div>

## How it works

<img src="https://raw.githubusercontent.com/maykhid/liveness_flutter/main/screenshots/how_it_works.png" width="720" alt="Camera, then ML Kit finds the face, then actions and checks, then onResult on the phone (offline); you send the result to your server, which verifies and decides"/>

1. The camera streams frames, and Google's ML Kit finds the face — on the
   phone, offline.
2. The package asks for each action in turn and checks it was really done,
   while watching for frozen feeds, a second face and poor light.
3. `onResult` gives you one `LivenessResult`: pass or fail, a confidence
   score, and the photos if you asked for them.
4. You send it to your server, which can verify it before trusting it.

## Is this right for you?

<div class="grid" markdown>

!!! success "A great fit for"

    Sign-up and onboarding gates, confirming it's really the user before a
    sensitive action, marketplace and gig-worker checks, and KYC flows
    where your backend also reviews the photos.

!!! warning "Pair it with server checks for"

    Anything regulated or with money on the line. The phone's verdict
    alone can be tampered with: follow the
    [server verification guide](server_verification.md) and review the
    photos server-side (face match,
    [presentation-attack detection](https://www.asisonline.org/security-management-magazine/articles/2024/08/biometrics/presentation-attack-detection/)).

</div>

!!! danger "Not the right tool if"

    You need *certified* liveness — for example, a passed
    [ISO/IEC 30107-3](https://www.iso.org/standard/79520.html)
    presentation-attack evaluation such as
    [iBeta's](https://www.ibeta.com/biometric-spoofing-pad-testing/) — or
    protection against sophisticated masks and deepfakes. That takes a
    trained anti-spoof model and usually a paid provider. This package can
    [plug such a model in](server_binding.md#bring-your-own-anti-spoof-model)
    but doesn't ship one.

    *What that means:* a **presentation attack** is showing the camera
    something that isn't a live person, such as a photo, a screen, a mask or
    a deepfake. ISO/IEC 30107-3 is the international standard for testing
    how well a system catches them, and labs like iBeta certify products
    against it. ASIS has a short
    [plain-language introduction](https://www.asisonline.org/security-management-magazine/articles/2024/08/biometrics/presentation-attack-detection/).

Still deciding? The **[honest notes](limitations.md)** cover every rough
edge in plain language (what the anti-spoof checks can and can't catch,
memory, lighting, device quirks) and the setting that changes each one.

## Pick your path

<div class="grid cards" markdown>

-   :material-rocket-launch: **[Getting started](getting_started.md)**

    Add a working liveness check to your app in about 10 minutes.

-   :material-robot-happy: **[Agent skills](agent_skills.md)**

    Have an AI coding agent do the integration, with one command.

-   :material-cellphone-check: **[Examples](examples.md)**

    See every example, from 90 lines to a fully branded KYC flow.

-   :material-tune: **[Customization](customization.md)**

    Colors, text, your own overlay and instructions.

-   :material-lock-check: **[Bind sessions to your server](server_binding.md)**

    For KYC or anything with real consequences.

-   :material-account-eye: **[Assisted mode](assisted_mode.md)**

    An agent holds the phone and verifies someone else.

-   :material-help-circle: **[FAQ](faq.md)**

    Offline? App size? Masks? Quick answers.

-   :material-alert-circle: **[Honest notes](limitations.md)**

    Know the limits before shipping.

</div>
