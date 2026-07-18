# 0.4.0

- **Assisted mode** (`cameraMode: LivenessCameraMode.assisted`): operator
  points the back camera at the person being verified and relays the
  instructions out loud. Torch lights the subject's face (opt out with
  `assistedTorchEnabled: false`), left/right detection signs flip
  automatically for the unmirrored back camera, the flash challenge is
  skipped (`metadata['flashChallenge'] = 'skippedAssistedMode'`), and
  `metadata['cameraMode']` records the mode for backend review.

- Screen is raised to full brightness while the liveness screen is open
  (restored on close; app window only). Helps detection in dim rooms and
  strengthens the flash challenge. Opt out with
  `boostScreenBrightness: false`. Adds the tiny `screen_brightness` plugin
  dependency.

- **Color-flash challenge** (opt-in `enableFlashChallenge`): after the
  actions succeed, the screen flashes randomly ordered colors and verifies
  the face reflects them — defeats video replays on a second screen. Soft
  signal: lowers `confidenceScore` by 0.35 on failure and reports
  `metadata['flashChallenge']` (`passed`/`failed`/`inconclusive`); never
  hard-fails. New translatable string `LivenessStrings.holdStill`.
- `LivenessResult.toString()` (readable session log) and `toJson()`
  (JSON-safe summary without media bytes).

# 0.3.0

All pure Dart — no new dependencies, no model downloads, minSdk unchanged.

- **Replay guard**: long runs of pixel-identical frames (impossible from a
  real camera) fail the session with `LivenessFailureReason.spoofSuspected`.
  Disable via `enableReplayGuard: false`.
- **Micro-motion check**: unnaturally still head angles lower the
  confidence score (soft signal, never hard-fails).
- **Frame quality gates**: too-dark/overexposed/blurry frames pause the
  session with guidance instead of silently failing detection. Thresholds:
  `brightnessMin/Max`, `sharpnessMin`; disable via
  `enableQualityChecks: false`.
- **`FaceGuidance`** on session state: `tooFar`, `tooClose`, `notCentered`,
  `lowLight`, `blurry`, `multipleFaces`, `noFace` — with translatable
  default messages (`LivenessStrings.guidanceMessages`).
- **`confidenceScore`** (0–1) and secure **`sessionId`** on
  `LivenessResult`; penalty counters exposed in `metadata` as
  `confidence_*`.
- **Debug overlay** (`showDebugOverlay: true`): live euler angles, eye and
  smile probabilities, brightness/sharpness, replay-guard counters.

# 0.2.0

- BREAKING: `LivenessUploader` is now an abstract strategy —
  `LivenessUploader.custom(anyAsyncFn)` wraps any transport; the old
  endpoint-based multipart helper is renamed `HttpLivenessUploader` (with an
  `onResponse` hook). `onResult` remains the primary, transport-free
  delivery point.
- New `LivenessCapabilities.supportsVideoCapture()` runtime probe, plus an
  in-session watchdog that falls back from video to a plain stream and sets
  `metadata['videoUnavailable']`.

- New `LivenessConfig.shuffleActions`: randomize action order once per
  session (anti-replay). Executed order is reported in
  `LivenessResult.completedActions`.
- New `CaptureType.frameSequence`: steady-rate timestamped JPEG frames
  (pseudo-video) that works on every device — recommended over native video
  on Android. Tunable via `frameSequenceFps` / `frameSequenceMaxFrames`.
- All JPEG encoding moved to background isolates; per-action captures no
  longer jank the detection pipeline.
- Platform-correct yaw/roll signs (iOS was flipped); `mirrorYaw: false`
  inverts both as an escape hatch.
- Circle detection: one full circle now completes it (CW/CCW tracked
  separately); switched to head yaw/pitch sweep.
- Fixed iOS solid-color captures (plane byte offset) and added NV12 support;
  NV21/BGRA row-stride handling.
- Relaxed `fullTeethSmile` (0.85 smile + lip-gap; contours optional) and
  mouth-open thresholds; eyes-closed hold now tolerates probability jitter.
- `LivenessUploader` also uploads `frames[i]` files.

# 0.1.0

- Initial release: enum-driven action sequences, 13 built-in actions,
  image/video capture, themable UI, backend-agnostic result callback,
  optional multipart uploader.
