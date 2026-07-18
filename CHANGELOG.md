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
