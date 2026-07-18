# 0.4.0

Initial public release.

## Liveness detection

- 13 challenge actions, executed in the order you list them: `blink`,
  `smile`, `fullTeethSmile`, `nod`, `lookLeft`, `lookRight`, `lookUp`,
  `lookDown`, `tiltLeft`, `tiltRight`, `eyesClosed`, `openMouth`, and
  experimental `drawCircleWithNose`.
- `shuffleActions` randomizes the order per session (anti-replay); the
  executed order is reported in `LivenessResult.completedActions`.
- Every detection threshold is tunable via `DetectorTuning`; detectors are
  pure-Dart state machines with unit tests.
- Session flow: face search/centering, per-action timeouts, neutral-face
  reset between actions, single-face enforcement, face-lost grace period.

## Anti-spoof & quality (no ML models, no downloads)

- Replay guard: long runs of pixel-identical frames fail the session with
  `spoofSuspected` (`enableReplayGuard`).
- Micro-motion check: unnaturally still sessions lower the confidence
  score (soft signal only).
- Frame quality gates: too-dark / overexposed / blurry frames pause the
  session with user guidance instead of failing (`enableQualityChecks`,
  `brightnessMin/Max`, `sharpnessMin`).
- Opt-in color-flash challenge (`enableFlashChallenge`): the screen
  flashes randomly ordered colors and verifies the face reflects them —
  counters video replays on a second screen. Soft signal; result in
  `metadata['flashChallenge']`.
- `confidenceScore` (0–1) on every result, with raw penalty counters in
  `metadata` under `confidence_*`; securely random `sessionId` for audit
  trails.

## Capture & delivery (backend-agnostic)

- Capture any mix of: per-action JPEG images, native session video, or a
  steady frame sequence (`CaptureType.frameSequence`) that works on every
  device — with fps, dimension, and JPEG-quality controls.
- All JPEG encoding runs in background isolates; per-action captures have
  a synchronous fallback so no verification image is ever lost.
- `onResult` delivers everything; optional `LivenessUploader.custom(fn)`
  wraps any transport, and `HttpLivenessUploader` covers multipart POST.
- `LivenessResult.toString()` for readable logs and `toJson()` for
  JSON-safe summaries.
- `LivenessCapabilities.supportsVideoCapture()` probes whether a device
  can record while detecting; sessions self-heal to a plain stream when it
  can't (`metadata['videoUnavailable']`).
- Optional `autoDeleteVideo` cleanup for the recorded file.

## Modes & UX

- Assisted mode (`LivenessCameraMode.assisted`): operator points the back
  camera at the subject and relays instructions; torch lights the face
  (`assistedTorchEnabled`), left/right signs flip automatically, flash
  challenge is skipped, and `metadata['cameraMode']` records the mode.
- Screen auto-brightens during the session and restores afterward
  (`boostScreenBrightness`).
- `FaceGuidance` state (`tooFar`, `tooClose`, `notCentered`, `lowLight`,
  `blurry`, `multipleFaces`, `noFace`) with translatable messages.
- Full theming via `LivenessTheme` + `LivenessStrings` (all text
  localizable), or replace UI layers entirely with `overlayBuilder` /
  `instructionBuilder`.
- `showDebugOverlay` shows live angles, probabilities, brightness, and
  replay-guard counters for threshold tuning.
- Per-action callbacks (`onActionStarted` / `onActionCompleted`), sync or
  async.
