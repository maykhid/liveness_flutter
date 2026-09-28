# Assisted mode: verifying someone else

← [Back to the README](../README.md)

*You need this if* a bank agent or field officer holds the phone and
verifies **another person** — common in branch onboarding and doorstep
KYC:

```dart
LivenessConfig(
  actions: [...],
  cameraMode: LivenessCameraMode.assisted,
)
```

**Understand what assisted mode means before using it:**

- The **back camera** is used, pointed at the subject. The **operator**
  watches the screen and must **read each instruction out loud** ("please
  blink", "turn your head left") — the subject cannot see the screen.
- "Left" and "right" always mean the *subject's* left/right; detection
  signs are flipped automatically for the unmirrored back camera.
- The **device torch turns on** to light the subject's face (the screen,
  which normally does that job, faces the operator). Opt out with
  `assistedTorchEnabled: false`. Skipped on devices without a torch.
- The **color-flash challenge is automatically skipped** (the screen's
  colors can't reach the subject's face):
  `metadata['flashChallenge'] = 'skippedAssistedMode'`. Static-feed guard,
  micro-motion, and quality gates still run.
- `metadata['cameraMode']` tells your backend which mode was used — decide
  whether assisted sessions need extra review, since the operator (not the
  subject) controls the device.
