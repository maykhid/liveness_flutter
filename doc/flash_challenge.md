# The color-flash challenge

← [Back to the README](../README.md)

*You need this if* you worry about someone playing a video of a real
person to the camera — the hardest cheap attack on any action-based check,
because the actions in the video were real when recorded.

`enableFlashChallenge: true` adds a defense: right after the actions
succeed, the screen flashes a short color sequence (red/green/blue, in a
**random order each session**, ~2.5 seconds, "Hold still…"). A real face
is lit by the phone's screen, so the camera sees each color reflected on
the skin. A replayed video was recorded before this session's random order
existed — its "face" doesn't reflect the right colors at the right times.

```dart
LivenessConfig(
  actions: [...],
  shuffleActions: true,
  enableFlashChallenge: true,
)
```

**It's a soft signal, on purpose — and lighting is why.** The trick
depends on the phone screen being a meaningful light source on the face:

| Environment | What to expect |
|---|---|
| 🌙 Dim / evening indoor | Strong signal — reflections clearly measurable |
| 🏠 Normal indoor lighting | Good signal — reliable for most users |
| 🏢 Bright office / large windows | Weak — real faces may score `'inconclusive'` or `'failed'` |
| ☀️ Outdoors in daylight | Little to no signal — results not meaningful |

**How it decides.** Only pixels inside the detected face are sampled
(background doesn't reflect the screen), the first 150 ms of each color
is skipped while the display and camera catch up, and auto-exposure is
locked for the duration where the device allows it. Each color must
raise its own channel clearly above the frame-to-frame noise measured
before the flash, both against that baseline and against the other
colors. By default all three colors must pass
(`flashAllowedMisses: 0`). In simulation, pure camera noise passes 0 times
in 5,000 runs, where the pre-0.5 rule passed about 1 in 20. White balance
can't be locked through the camera plugin, so strongly tinted light can
still skew it.

Other weakeners: phone held far from the face, very low screen brightness,
strongly colored ambient light. To help, the package **raises the screen
to full brightness automatically** during the session and restores it
afterward (app window only; opt out with `boostScreenBrightness: false`).

A failed challenge lowers `confidenceScore` by 0.35 and sets
`metadata['flashChallenge'] = 'failed'` — it never rejects the user by
itself. **Treat a failure as "review this one", not "this is fraud."**
Log the metadata for a few weeks and learn your real users' pass rate
before enforcing anything. Bonus: the flash moment is captured in your
video and frame sequence — a real face visibly changes color, which your
server can check too.
