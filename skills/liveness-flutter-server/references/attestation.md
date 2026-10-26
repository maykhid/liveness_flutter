# Attestation: checking Play Integrity and App Attest tokens

Without attestation, everything in the upload can be produced by a script
that copies the request format: it asks for a challenge, skips the
camera, and uploads any photos with matching hashes. An attestation is
the one part a script can't forge: Google or Apple signs the session's
payload hash only for the genuine app on a real device. It also blocks
most fake-camera attacks, which need a rooted or modified phone.

The package only defines the hook (`LivenessAttestor` in the app). The
app's attestor decides the token format; the package's guide (and the
`liveness-flutter` skill) suggest this JSON string, which the uploader
sends in the `attestation` form field:

- Android: `{"platform": "android", "token": "<Play Integrity token>"}`
- iOS: `{"platform": "ios", "keyId": "<App Attest key ID>", "assertion": "<base64 CBOR>"}`

Confirm with the app's code what it actually sends.

## The payload hash

The attestor signed the SHA-256 of this UTF-8 string:

```
sessionId|nonce|success|action,action,…|sha256,sha256,…|sha256(metadata)
```

- `nonce` is empty when the session had no challenge.
- `success` is `true` or `false`.
- Actions are `completedActions`, comma-separated.
- Hashes are the `sha256` values of `metadata.images`, then
  `metadata.frames`, in listed order.
- The last part is the lowercase hex SHA-256 of the `metadata` form
  field's raw bytes, exactly as received. Hash the bytes before parsing
  them; parsing and re-encoding the JSON changes them.

Rebuild it from the uploaded metadata *after* checking the files match
their listed hashes, so the hash covers the photos you actually received.
Code for Python is in [verifier.py](verifier.py), for TypeScript and Go in
[protocol.md](protocol.md). Test with the vector in
[../SKILL.md](../SKILL.md).

## Android: Play Integrity (standard request)

Setup the app developer needs: the app installed from Google Play (the
internal testing track is enough; a sideloaded debug build gets an
unrecognized verdict), a Google Cloud project linked in Play Console's
App integrity page with the Play Integrity API enabled, and a service
account in that project for the server.

Server check:

1. Decode the token with Google:
   `POST https://playintegrity.googleapis.com/v1/<packageName>:decodeIntegrityToken`
   with body `{"integrity_token": "<token>"}`, authenticated with the
   service account (OAuth scope
   `https://www.googleapis.com/auth/playintegrity`). Google's client
   libraries wrap this call.
2. In the decoded `tokenPayloadExternal`, require:
   - `requestDetails.requestHash` equals the payload hash **as the app
     encoded it**. The package's Kotlin template sends lowercase hex;
     confirm in the app's code.
   - `requestDetails.requestPackageName` is the app's package name.
   - `requestDetails.timestampMillis` is within the last few minutes.
   - `appIntegrity.appRecognitionVerdict` is `PLAY_RECOGNIZED`.
   - `deviceIntegrity.deviceRecognitionVerdict` contains
     `MEETS_DEVICE_INTEGRITY` (or `MEETS_STRONG_INTEGRITY` for high-value
     flows; stricter, and it rejects more older phones).
   - Optionally `accountDetails.appLicensingVerdict` is `LICENSED`.

## iOS: App Attest

Two phases.

**Once per install, key registration.** The app generates a key, your
server issues a one-time challenge, the app calls `attestKey` with the
challenge's SHA-256 as client data hash, and your server verifies the
attestation object as Apple's "Validating apps that connect to your
server" describes: the certificate chain up to Apple's App Attest root,
the nonce, the App ID (`<TeamID>.<bundleID>`) hash, a counter of 0, the
`aaguid` (`appattestdevelop` while testing, `appattest` followed by
seven `0x00` bytes in production), and that the credential ID equals the
key ID. Store the public key and a counter of 0 for that key ID, tied to
the user. Libraries exist for most languages; prefer one over
hand-rolled CBOR and certificate parsing.

**Every session, the assertion.** For `{"keyId", "assertion"}`:

1. Look up the stored public key and counter for `keyId`, and check the
   key was registered by **the same user** as the upload; a key
   registered by someone else proves nothing about this user. Unknown
   key: review, and expect the app to register a new key.
2. Base64-decode the assertion and CBOR-decode it into `signature` and
   `authenticatorData`.
3. Compute `clientDataHash = payload hash` (the package's Swift template
   passes the payload hash unchanged as client data hash), then
   `nonce = SHA256(authenticatorData || clientDataHash)`.
4. Verify `signature` (ECDSA P-256, SHA-256) over `nonce` with the stored
   public key.
5. The first 32 bytes of `authenticatorData` (the RP ID hash) equal
   `SHA256("<TeamID>.<bundleID>")`.
6. The sign counter (the 4 bytes after the RP ID hash and the flags
   byte, so offsets 33 to 36, big-endian) is greater than the stored
   counter. Save the new value.

App Attest doesn't run on the simulator, and `DCAppAttestService` can be
unsupported on some devices; the app then has no attestation to send.

## Policy

- Missing `attestation` field, `metadata.metadata.attestationError`, or a
  failed check: **manual review**, not a pass and not an automatic
  reject. A phone without attestation support isn't proof of fraud, and
  isn't proof of anything else either.
- A valid attestation plus all the integrity checks: the whole
  `metadata` field (its hash is in the payload) and the photos came from
  your app on a real device, unedited, so the photos are the ones that
  session took and the scores are the ones the app computed. That says
  the app ran, not that the face is real: a score is still the app's own
  judgement, and the face still has to be judged (face match and
  server-side presentation-attack detection).
- Log the verdict fields alongside the session for later tuning.
