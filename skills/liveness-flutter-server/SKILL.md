---
name: liveness-flutter-server
description: Builds or reviews the backend for the liveness_flutter Flutter package, in any server language. Covers issuing single-use challenges, receiving the multipart upload from HttpLivenessUploader, checking the nonce, action order, session ID and SHA-256 photo hashes, rebuilding the attestation payload, verifying Play Integrity or App Attest tokens, and deciding pass, review or reject. Use when a backend receives liveness_flutter results (a metadata field, images[i] files, an X-Liveness-Session header) or the user asks how to verify liveness_flutter sessions on the server.
license: MIT
metadata:
  package: liveness_flutter
  written-for: "0.6.0"
---

# Verifying liveness_flutter sessions on a server

The Flutter app runs the liveness check on the phone and uploads the
result. **A `success: true` from a phone is a claim, not proof**: the
person being verified controls the phone. The server's job is to make
tampering and replay detectable, then judge the face itself.

What each layer proves:

| Check | Proves | Doesn't prove |
|---|---|---|
| Challenge (nonce, order, expiry) | This upload answers a challenge you issued, once, recently, in your order. | That a camera was used. |
| Photo hashes | The files are the ones the session reported. | That they show a live person. |
| Attestation (Play Integrity / App Attest) | The signed fields (below) came from your genuine app on a real device. | Anything about the unsigned fields, or that the face is live or the right person. |
| Face match + server-side anti-spoofing | It's the right person and not a photo, screen or mask. | (This is the actual judgment.) |

The package does none of the server work and ships no anti-spoof model.
Don't describe a passing session as certified liveness.

## Build these two endpoints

### 1. Issue a challenge

`POST /liveness/challenge`, authenticated as the user. Respond:

```json
{
  "nonce": "9f2c4e6a8b0d1f3e5a7c9e1b3d5f7a9c",
  "actions": ["lookLeft", "blink", "smile"],
  "expiresAt": "2026-10-26T12:05:00Z"
}
```

- `nonce`: at least 128 random bits from a CSPRNG, single use.
- `actions`: action names exactly as the Dart enum spells them (see
  [references/protocol.md](references/protocol.md)). Pick 2 to 4 at
  random from a pool, in random order, and include at least one motion
  action: `blink`, `nod`, `openMouth` or `drawCircleWithNose`. Every
  other action is pose-only and can be faked with a photo.
- `expiresAt`: ISO 8601 in UTC. It must cover the wait before the user
  starts plus the whole session (the app's `sessionTimeout`, 2 minutes by
  default): the phone refuses a challenge that expires before the session
  ends. 5 minutes is a good default; make it configurable. A nonce is
  single use, so a longer expiry gives an attacker almost nothing.
- Store `{nonce, user, actions, expiresAt}` plus empty `sessionId`,
  `uploadDigest` and `verdict` columns, filled by the first upload.

### 2. Accept the upload

`POST /liveness` (or whatever the app's `endpoint` is), multipart, from
`HttpLivenessUploader`: a `metadata` field (JSON), `images[i]` and
`frames[i]` files, an optional `video` file and an `X-Liveness-Session`
header. Exact format and a sample payload:
[references/protocol.md](references/protocol.md).

## The checks, in order

0. **Shape**: parse `metadata` and check every field's type before
   anything else (strings, booleans, numbers, lists of known action
   names, 64-character lowercase hex hashes). Reject a malformed upload
   without touching the nonce. Code that assumes well-formed input
   crashes on hostile input.
1. **Nonce, idempotently**: `metadata.nonce` names a challenge you issued
   **to this user**. Tie it to this upload in one atomic statement that
   also checks the user, so a leaked nonce can't spoil its owner's
   session:

   ```sql
   UPDATE challenges SET session_id = $3, upload_digest = $4
    WHERE nonce = $1 AND user_id = $2 AND session_id IS NULL
   RETURNING actions, expires_at;
   ```

   `upload_digest` is a hash of the metadata and every file's hash. If no
   row was updated, read the row: the same session ID and digest means a
   **retry** (the app retries timeouts and 5xx, and the first response
   may have been lost), so answer with the verdict you stored for it;
   anything else is a replay, so reject it. Store each verdict with its
   challenge.
2. **Expiry, by the server's clock**: reject if now is past `expiresAt`
   plus a grace for the upload (2 minutes is a good default). The phone
   already refused the challenge if it expired before the session ended.
3. **Session ID**: the `X-Liveness-Session` header equals
   `metadata.sessionId`.
4. **Outcome**: `metadata.success` is `true`. Store failed sessions as
   signals, but they are never a pass.
5. **Order**: `metadata.completedActions` equals the challenge's
   `actions`, same names, same order.
6. **Photos**: SHA-256 every uploaded image and frame. `images[i]` must
   hash to `metadata.images[i].sha256` and `frames[i]` to
   `metadata.frames[i].sha256`, with counts equal to `imageCount` and
   `frameCount`: nothing missing, extra or altered. An upload with no
   photos at all gives you nothing to judge; the app must capture
   `{CaptureType.images}`.
7. **Attestation**: rebuild the payload hash and verify the token with
   Google or Apple. See
   [references/attestation.md](references/attestation.md).

## What the attestation covers

The attestation signs only these fields: `sessionId`, `nonce`,
`success`, `completedActions`, and the `sha256` of every image and frame
(see the test vector below). **Everything else is unsigned**:
`confidenceScore`, all of `metadata.metadata` (`flashChallenge`,
`cameraMode`, `analyzers`, `attestationError`, the `confidence_*`
counters), each capture's `kind`, `action` and `timestampMs`, and
`durationMs`. A user running your genuine app can edit those in transit
(for example through a proxy on their own phone) without breaking the
attestation. So unsigned fields may send a session **to review**, but
must never be what makes it pass, and a high `confidenceScore` proves
nothing on its own.

## Deciding

- **Reject**: any of checks 0 to 6 failed.
- **Review**: no attestation, `metadata.metadata.attestationError` set, or
  the attestation check failed; or a completed action has no photo
  (`kind` `peak` or `completion`), or a `timestampMs` is outside 0 to
  `durationMs`; or `confidenceScore` is low (start at 0.9, then learn
  your users' real distribution); or
  `metadata.metadata.flashChallenge == "failed"`; or policy says assisted
  sessions (`metadata.metadata.cameraMode == "assisted"`) need a human.
- **Pass**: everything holds. Then still run face match against the ID
  document or enrolled face, and server-side presentation-attack
  detection, on the photos themselves. Judge the images, not their
  labels.

An app without an attestor can never reach "pass" under this policy, by
design: without attestation, a script can produce an upload that passes
every other check. Don't "fix" that by accepting any token. If the
product owner accepts the risk, make it an explicit setting (the
reference verifier's `require_attestation=False`) and write down why.

Note the nesting: the uploaded JSON is `LivenessResult.toJson()`, which
has the package's diagnostics in its own `metadata` key. So
`cameraMode` is at `metadata.metadata.cameraMode` when the multipart
field is called `metadata`.

A complete, dependency-free Python version of these checks, with a
self-test, is [references/verifier.py](references/verifier.py). Port it
to the backend's language rather than writing the checks from scratch,
and keep its self-test cases as unit tests.

## Test vector

For a unit test of the payload rebuild in any language, the sample
upload in [references/protocol.md](references/protocol.md) must give:

- payload string:
  `LV-0192C3D4E5F6-0A1B2C3D|9f2c4e6a8b0d1f3e5a7c9e1b3d5f7a9c|true|blink,lookLeft|6b1e5f80828d2b0e6acbc3496026d3dd05163d39cb0b22ca86a360f86d69388e,80fb272a1dcf2d5f245583a1bab1f278aa62fea2a6907741ab0e8c78e37f0fef,ac991dc77af749e06be09087288c3506c629d13b1cc08faba946f73ef37225c9,f8952f8aff2a83a859aa47f33adb73441412143c3982ae0e7ec57d49d0ba7320`
- SHA-256 of it (hex):
  `7e87017d4590b7be83dd7cdf5b72ee4f0db251e75394b7324e9523099fa00190`

## Mistakes to avoid

- Trusting `success`, `confidenceScore` or `expiresAt` checks done on the
  phone. Re-check on the server with server data.
- Letting the app choose the actions, or accepting a second, different
  upload on a used nonce.
- Rejecting a retry of the same upload as a reused nonce. The app retries
  timeouts and 5xx; return the stored verdict instead.
- Spending a nonce before checking it belongs to the uploading user.
- Comparing only counts of photos, or hashing re-encoded copies (hash the
  bytes as received, before any image processing).
- Treating a missing attestation as a pass. It means "review".
- Treating an attested upload's unsigned fields as trustworthy.
- Treating a low confidence score or a failed flash challenge as proven
  fraud. They are review signals; the flash challenge is weak in daylight.
- Storing photos longer than the product needs. They are biometric data
  in many jurisdictions (GDPR, BIPA): set retention and consent
  accordingly.
