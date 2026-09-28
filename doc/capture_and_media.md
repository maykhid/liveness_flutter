# Photos, video, and frame sequence

← [Back to the README](../README.md)

*You need this if* you want more evidence than one photo per action.

**Capturing nothing is the default.** With an empty `capture`,
`result.images` and `result.frameSequence` come back empty and
`videoPath` is null. Nothing is encoded, kept in memory, or written to
disk. You still get the verdict: `success`, `completedActions`,
`confidenceScore`, `sessionId`, and `metadata` — a few hundred bytes.

The trade-off: with no captured media, your server has nothing to
independently verify — you're fully trusting the on-device result. Fine
for low-stakes flows (gating a selfie upload); for KYC or anything with
real consequences, capture at least `{CaptureType.images}`.

| You want | Use | Notes |
|---|---|---|
| A photo of each completed action | `CaptureType.images` | Smallest uploads. Works everywhere. **Best default.** |
| A real video file of the session | `CaptureType.video` | Great on iPhones. On many Android phones the camera can't record and detect at the same time — see below. |
| Something video-like that works on every phone | `CaptureType.frameSequence` | Several photos per second for the whole session. A list of photos, not a video file — but played back they look like one. |

<details>
<summary>🤖 <b>The Android video problem, in plain words</b> (click to expand)</summary>

Detecting your face and recording a video both need the camera at the same
time. iPhones handle that fine. Many Android phones can't — and there's no
official way to ask a phone in advance. So this package gives you three
tools:

1. `LivenessCapabilities.supportsVideoCapture()` — call it once when your
   app starts (takes 2–3 seconds, remembers the answer). It quietly tries
   recording and tells you `true`/`false`:

   ```dart
   final canRecord = await LivenessCapabilities.supportsVideoCapture();
   final capture = canRecord
       ? {CaptureType.images, CaptureType.video}
       : {CaptureType.images, CaptureType.frameSequence};
   ```

2. If you skip that and video fails mid-session anyway, the check **doesn't
   break** — it quietly continues without video and marks
   `result.metadata['videoUnavailable'] = true` so you know.

3. Frame sequence as the works-everywhere alternative. If your server wants
   a real video file from those photos, one command turns them into an MP4:

   ```bash
   ffmpeg -framerate 8 -pattern_type glob -i 'frame_*.jpg' \
     -c:v libx264 -pix_fmt yuv420p session.mp4
   ```

</details>

**Media size & cleanup:**

- **Photo size**: `maxImageDimension` (default 720 px longest side) and
  `jpegQuality` (default 85; lower = smaller files).
- **Video size**: `cameraResolution` on the `LivenessDetector` widget.
- **Frame rate**: `frameSequenceFps` (default 8, max 15) and
  `frameSequenceMaxFrames` (default 300) cap memory. Encoding runs in
  background isolates — capture never stalls detection.
- **Cleanup**: photos live only in memory — gone when you're done with the
  result. The **video is a real file** and is *not* deleted automatically:
  upload or copy it in `onResult`, then delete it yourself or set
  `autoDeleteVideo: true` to remove it when the camera screen closes.
