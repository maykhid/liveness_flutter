# 0.5.0 (unreleased)

### Breaking

- New `LivenessFailureReason.sessionTimeout`. Exhaustive `switch`es over
  `LivenessFailureReason` need a new case.
- Sessions now end on their own: by default after 2 minutes overall
  (`sessionTimeout`) and after 10 s of not returning to a neutral face
  (`neutralTimeout`). Pass `sessionTimeout: null` for the old unbounded
  behaviour.
- `LivenessSession(config)` throws an `ArgumentError` for an invalid config.
- `multipleFaces` failures now need a second face for more than
  `multipleFacesGrace` (500 ms). Set it to `Duration.zero` for the old
  instant behaviour.
- Action photos are now taken at the action's peak by default, so their
  `timestampMs` is earlier than before. Set `captureAtPeak: false` for the
  old completion-frame photos. Custom `LivenessEvent` switches need an
  `ActionPeakEvent` case.
- New `FaceGuidance.tooBright` value. Exhaustive `switch`es over
  `FaceGuidance` need a new case.
- `onResult` can now run from `dispose()`, when the widget's context is
  unmounted. Code that navigates in `onResult` must check `context.mounted`
  first (the README example now does).
- `HttpLivenessUploader`'s `metadata` JSON is now `result.toJson()`: the
  diagnostics (`blink_ms`, `confidence_*`, `flashChallenge`, …) moved from
  the top level into a nested `metadata` object, and image file names
  changed from `<action>_<index>.jpg` to `<action>_<kind>_<t>ms.jpg`.
- `HttpLivenessUploader.upload()` now throws on non-2xx responses and on
  timeouts (60 s per attempt by default). Wrap it in `try`/`catch`.
- The face-in-position test now follows the drawn target. Faces that
  passed the old loose centre check may now get `notCentered`, `tooFar` or
  `tooClose`; tune `ovalSizeFactor` or `targetFillMin`/`targetFillMax`.
- The default `LivenessStrings.centeringFace` is now "Fit your face in the
  oval" (it sits above a specific hint now), and `FaceGuidance.multipleFaces`
  was removed from the default `guidanceMessages` map in favour of
  `LivenessStrings.multipleFaces`.
- `LivenessStrings.actionInstructions` / `guidanceMessages` are now getters
  returning your entries merged over the defaults (the constructor
  parameters are unchanged). The failed screen shows the reason-specific
  text from `failureMessages` instead of `failed`.

### Added

- `LivenessConfig.sessionTimeout` (default 2 min, nullable) and
  `LivenessConfig.neutralTimeout` (default 10 s).
- `LivenessSession.tick(timestampMs)`: advances timers without a frame.
  The widget calls it every 250 ms.
- `LivenessConfig.validate()` throws an `ArgumentError` for empty `actions`,
  `jpegQuality` outside 1–100, `maxImageDimension` < 64, `brightnessMin` ≥
  `brightnessMax`, and non-positive timeouts. `LivenessSession` calls it in
  its constructor; the constructor also asserts the numeric ranges.
- `LivenessConfig.multipleFacesGrace` (default 500 ms),
  `DetectorTuning.secondaryFaceMinAreaRatio` (default 0.35),
  `LivenessSession.relevantFaces()` and `FaceSnapshot.area`.
- `DetectorUpdate.isPeak`, `ActionPeakEvent`, `CapturedImage.kind`
  (`reference` | `peak` | `completion` | `sequence`) and
  `LivenessConfig.captureAtPeak` (default `true`).
- `LivenessSessionState.copyWith` gains `clearCurrentAction`,
  `clearFailureReason` and `clearRemaining`.
- `LivenessConfig.invertPitch` (default `false`): flips up/down head tilt
  for devices where `lookUp`, `lookDown` or `nod` behave inverted, like
  `mirrorYaw` does for left/right.
- `FaceGuidance.tooBright` with a default message, and
  `FrameQuality.issueFor(config)`.
- `metadata['cancelledBy']` on cancelled results: `'user'`, `'lifecycle'` or
  `'dispose'`.
- `HttpLivenessUploader.client`: inject an `http.Client` (your own, or a
  `MockClient` in tests).
- `HttpLivenessUploader.timeout` (default 60 s per attempt), `maxRetries`
  (default 0) and `retryDelay` (default 1 s, doubling): network errors,
  timeouts and 5xx responses are retried; 4xx never are.
  `LivenessUploadException`.
- `LivenessController` (`LivenessDetector.controller`, optional): read
  `state`, `actionPlan` and `sessionId`, and call `cancel()` or `restart()`
  from outside the widget. `restart()` starts a fresh session (new session
  ID, new shuffle, new camera) and still delivers exactly one result per
  session (`cancelledBy: 'restart'` for an interrupted one).
- `LivenessSessionState.actionPlan` (the executed order, from the first
  state), `actionTimeout` and `sessionRemaining`. `tick()` keeps `remaining`
  and `sessionRemaining` counting down when frames stall.
- `LivenessTheme.ovalCenter` (default `Offset(0.5, 0.44)`),
  `ovalAspectRatio` (default 1.35) and `ovalShape` (`TargetShape.oval` |
  `roundedRect` | `circle`); `LivenessDetector.targetRegion` so a custom
  overlay's window drives detection; `DetectorTuning.targetFillMin` (0.15)
  and `targetFillMax` (1.0). The debug overlay draws the detected face box
  in screen space.
- `LivenessDetector.instructionAlignment` and `closeButtonBuilder`;
  `LivenessTheme.closeIconColor`, `closeButtonAlignment`, `flashTintOpacity`
  and `resultHoldDuration`; `LivenessStrings.close` (close-button tooltip and
  screen-reader label).
- `LivenessStrings.stepCounter` (`String Function(int current, int total)`),
  `failureMessages` (per `LivenessFailureReason`, shown on the failed
  screen), `failureFor()`, the `default*` maps, and `copyWith` on
  `LivenessTheme` and `LivenessStrings`.
- `LivenessDetector.onFeedback` with `LivenessFeedback` events
  (`actionStarted`, `actionProgressHalf`, `actionCompleted`,
  `sessionSucceeded`, `sessionFailed`) for sounds, haptics or TTS;
  `LivenessConfig.hapticFeedback` (opt-in); the instruction text is now a
  screen-reader live region, so each new instruction is announced.

### Fixed

- Sessions could hang forever while searching for or centering the face,
  while waiting for a neutral face, or while paused for bad lighting. The
  neutral case fails with `actionTimeout` and
  `metadata['timeoutPhase'] = 'awaitingNeutral'`. The action timer now keeps
  running during a quality pause.
- `LivenessConfig(actions: [])` threw a `RangeError` on every frame and never
  ended. An invalid config now produces one immediate `systemError` result
  (with `metadata['configError']`) and an `onError` call, without opening
  the camera.
- A single frame with a second face (a poster, a TV, someone walking past)
  failed the session instantly. Secondary faces under 35 % of the primary
  face's area are now ignored, and a comparable second face must stay for
  more than 500 ms before the session fails. Until then the session pauses
  with `FaceGuidance.multipleFaces`. The primary face is now the largest one,
  not the first one ML Kit returns.
- Evidence photos missed the action: they were taken after it completed
  (the blink photo showed open eyes, the nod photo a level head) and from the
  newest camera frame rather than the analysed one. Each action's photo now
  comes from its peak frame (eyes shut, deepest nod, start of a held pose).
- A single missed face detection (or one blurry or dark frame) reset the
  current action, restarting a 400 ms pose hold. The detector is now paused
  and keeps its progress for pauses up to `faceLostGrace`; a longer quality
  pause restarts the action so the unseen gap never counts as held.
- `state.remaining` kept a stale countdown after an action completed. It is
  now only set while an action is being performed.
- Overexposed frames told the user to "Find better lighting"
  (`FaceGuidance.lowLight`). They now report `FaceGuidance.tooBright`.
- `shuffleActions` used a non-cryptographic `Random()`; it now uses
  `Random.secure()`, since the shuffle is an anti-replay measure.
- `google_mlkit_face_detection` now allows `>=0.14.0 <0.16.0`. 0.15.x needs
  Flutter 3.44 / Dart 3.12; older SDKs keep resolving to 0.14.
- Raising the screen brightness no longer delays camera start: the
  platform call now runs in the background.
- `onResult` was never called when the detector was removed before the
  session ended (route popped, system back), despite the "called exactly
  once" promise. It is now delivered synchronously from `dispose()` as a
  `cancelled` result, or with the real outcome if the session had already
  ended. A throwing `onResult` there goes to `onError`.
- `HttpLivenessUploader` left out `sessionId` and `confidenceScore`, the two
  audit fields the README promotes. The `metadata` field is now
  `result.toJson()`, and the request carries an `X-Liveness-Session` header.
  Image file names now include the capture kind and timestamp
  (`blink_peak_812ms.jpg`, `reference_120ms.jpg`) instead of a list index.
- `HttpLivenessUploader.upload()` completed normally on any HTTP status,
  including 500. It now throws `LivenessUploadException(statusCode, body)` for
  non-2xx responses (after `onResponse` has seen them).
- The on-screen oval had no effect on detection: the face-position check
  used the image centre ±25 % and a 4–75 % face area, whatever
  `ovalSizeFactor` said. The drawn target is now mapped into camera space
  (cover-fit, sensor rotation, front-camera mirror) and the face must have
  its centre inside it and fill it within `targetFillMin`–`targetFillMax`.
- `LivenessTheme.hintStyle` and `LivenessStrings.multipleFaces` were declared
  but never used. Guidance hints ("Move closer", "Find better lighting") are
  now shown in `hintStyle` under the current instruction instead of replacing
  it, and `multipleFaces` is the multiple-faces hint unless
  `guidanceMessages` has its own entry. The close icon was always white
  (invisible on light scrims).
- "Step N of M" was hard-coded English; the failed screen always said
  "Verification failed" whatever the reason; and a partial
  `actionInstructions` or `guidanceMessages` map made every missing entry
  fall back to raw enum names like `lookLeft`. User maps are now merged over
  the defaults.

# 0.4.4

- Updated README.md

# 0.4.3

- Updated dependencies and minor improvements.

# 0.4.2

- Documentation: restyled README for pub.dev (no code changes).

# 0.4.1

- Fixed captured photos coming out landscape on pipelines that deliver
  already-upright buffers (notably iOS): quarter-turn rotations are now
  only applied to landscape buffers.
- Much faster frame encoding: decoding and downscaling are fused, so
  full-resolution intermediates are never materialized (~4x less work at
  1080p→720). Frame-sequence capture no longer starves on slower devices
  or debug builds.
- `HttpLivenessUploader.onProgress(sentBytes, totalBytes)`: drive an
  upload progress bar. Liveness payloads can be several MB — the example
  app now demonstrates a progress dialog, and the README documents the
  recommended loading-UX patterns.

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
