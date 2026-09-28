# Verifying liveness results on your server

`liveness_flutter` runs its checks on the phone. A determined attacker
controls their own phone, so **a `success: true` from the device is a
claim, not a proof.** This guide describes what your backend should check
before trusting a session. None of it makes on-device liveness bank-grade
on its own. It makes tampering and replay detectable, and gives your
server-side face matching and presentation-attack detection (PAD) honest
inputs.

## 1. Issue a challenge before the session

Create the challenge on the server, not in the app:

```jsonc
// POST /liveness/challenge  →
{
  "nonce": "3q2+7w…",                        // ≥ 128 random bits, single use
  "actions": ["lookLeft", "blink", "smile"], // your choice and order
  "expiresAt": "2026-09-25T12:05:00Z"        // a few minutes out
}
```

Store it keyed by `nonce`, marked unused. In the app:

```dart
LivenessConfig(
  actions: const [],            // ignored when a challenge is set
  challenge: LivenessChallenge(
    nonce: json['nonce'],
    actions: [for (final a in json['actions']) LivenessAction.values.byName(a)],
    expiresAt: DateTime.parse(json['expiresAt']),
  ),
  capture: {CaptureType.images},
)
```

Choosing actions:

- **Include at least one motion action**: `blink`, `nod`,
  `drawCircleWithNose` or `openMouth`. Pose-only actions (`smile`,
  `tiltLeft`/`tiltRight`, `lookUp`/`lookDown`) can be satisfied by a photo
  that's tilted or swapped at the right moment.
- **Pick at random from a pool, per challenge.** Three random actions from
  the 13 give 1,716 ordered sequences, against 6 for a fixed list of three.
  (Without server challenges, `LivenessConfig.randomActionCount` does this
  on the device.)

## 2. Check the upload

`HttpLivenessUploader` sends a multipart request with:

| Part | Content |
|---|---|
| `X-Liveness-Session` header | the session ID |
| `metadata` field | `LivenessResult.toJson()` as JSON |
| `images[i]` files | one JPEG per photo, named `<action>_<kind>_<t>ms.jpg` or `reference_<t>ms.jpg` |
| `frames[i]` files | frame-sequence JPEGs, if captured |
| `video` file | the recording, if captured |

Reject the session unless **all** of these hold:

1. **Nonce.** `metadata.nonce` matches a challenge you issued that is
   unused and not expired by *your* clock (the device clock can be wrong or
   set back). Mark it used now, whatever the outcome, so it can't be
   replayed.
2. **Order.** For a successful session, `metadata.completedActions` equals
   the challenge's `actions` exactly, in order.
3. **Session ID.** The `X-Liveness-Session` header equals
   `metadata.sessionId`.
4. **Media integrity.** Hash every uploaded image and frame with SHA-256.
   The multiset of hashes must equal the `sha256` values listed in
   `metadata.images` and `metadata.frames`: no missing, extra or altered
   files. Check `kind` and `timestampMs` are plausible (a `peak` photo per
   action, timestamps increasing, inside the session's duration).
5. **Attestation** (if you configured a `LivenessAttestor`). Rebuild the
   payload and verify the token with the platform. See below.

## 3. Rebuild the attestation payload

The attestor signs the SHA-256 of this exact UTF-8 string:

```
sessionId|nonce|success|action,action,…|sha256,sha256,…
```

- `nonce` is empty if the session had no challenge.
- `success` is `true` or `false`.
- Actions are `completedActions` names, comma-separated.
- Hashes are lowercase hex SHA-256 of every image, then every frame, in the
  order listed in `metadata.images` then `metadata.frames`.

```python
import hashlib

def payload_hash(meta: dict) -> bytes:
    hashes = [i["sha256"] for i in meta["images"]] + \
             [f["sha256"] for f in meta["frames"]]
    payload = "|".join([
        meta["sessionId"],
        meta.get("nonce") or "",
        "true" if meta["success"] else "false",
        ",".join(meta["completedActions"]),
        ",".join(hashes),
    ])
    return hashlib.sha256(payload.encode("utf-8")).digest()
```

How the hash gets into the token depends on your attestor. For example,
pass it (base64 or hex, your choice) as Play Integrity's `requestHash`, or
as App Attest's client data hash. Verify the token with Google or Apple as
their documentation describes, and check that the hash inside matches
`payload_hash(meta)`. The package never implements the platform APIs
itself.

`metadata.attestationError` is set when the attestor failed or timed out
(15 s), or when the screen was closed before it could run. Decide whether
that's a reject or a review.

## 4. Then judge the face, server-side

Passing the checks above means "this device ran this challenge and these
are its genuine photos". It does **not** mean a live person was in front
of the camera. That's what these are for:

- **Face match**: compare the `reference` and `peak` photos against the
  ID document or the enrolled face.
- **Presentation-attack detection**: run a server-side PAD model on the
  photos or frames to catch screens, prints and masks held up to a real
  camera. The on-device replay guard only catches static or injected
  feeds, and the color-flash challenge is a soft signal that fails in
  daylight.
- **Review signals**: `confidenceScore`, `metadata.confidence_*`,
  `metadata.flashChallenge` and `metadata.cameraMode`. Treat low scores as
  "send to review", not as proof of fraud. Learn your real users'
  distribution before enforcing thresholds.
