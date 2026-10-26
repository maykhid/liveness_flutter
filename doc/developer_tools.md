# Developer tools

- **Debug overlay** — `showDebugOverlay: true` shows live head angles,
  eye/smile probabilities, brightness, and static-feed guard counters on
  screen, and draws a green box where the detector thinks your face is (if
  it doesn't sit on your face, please
  [open an issue](https://github.com/maykhid/liveness_flutter/issues) with
  your device). Perfect for tuning `DetectorTuning` thresholds on real
  devices.
- **Per-action callbacks** — `onActionStarted` / `onActionCompleted`
  (sync or async; never awaited, so detection never stalls on your code).
- **Feedback & accessibility** — `onFeedback` fires on action started,
  half-way, completed, and session passed/failed, for your own sounds,
  haptics or text-to-speech. `hapticFeedback: true` adds built-in haptics
  (handy for `eyesClosed`, which users can't see finish). Instructions are
  a screen-reader live region, so each new one is announced.
- **Permission handling in the screen** — `permissionDeniedBuilder:
  (context, retry) => ...` shows your own page when camera access is
  denied; calling `retry` starts a fresh session.
- **Test bench** —
  [`example/lib/test_bench/`](https://github.com/maykhid/liveness_flutter/blob/main/example/lib/test_bench/main.dart)
  puts every option behind a settings screen, logs every callback live,
  and runs the server-side checks on each result.
