# Everything in the result

← [Back to the README](../README.md)

`LivenessResult`, in full:

- `success`, `failureReason` — the verdict and why. Cancelled results say
  who in `metadata['cancelledBy']`.
- `confidenceScore` — 0 to 1. Duplicate frames, a frozen head, many
  bad-quality frames, a failed flash challenge or anti-spoof model scores
  pull it down. Raw counters are in `metadata` under `confidence_*` and
  `identity_*` keys.
- `sessionId` — unique audit ID.
- `nonce` / `attestation` — the server challenge's nonce and the
  attestor's token, when you use them.
- `completedActions` — which actions, in the order performed.
- `images` — the photos, each with `action`, `kind`, `timestampMs` and a
  `sha256Hex`.
- `frameSequence` — the steady-stream photos, each with a timestamp.
- `videoPath` — where the video file is, if you recorded one.
- `metadata` — extras like how long each action took.
- `toJson()` / `toString()` — a JSON-safe summary (no media bytes) and a
  readable log block.
