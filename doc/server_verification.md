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

## 3a. Writing an attestor

**Why you need one.** Sections 1–3 prove the upload is consistent: the
right nonce, the right order, the photos that were hashed. They don't
prove the upload came from your app. A script that copies the request
format can ask for a challenge, skip the camera, and send any photos with
matching hashes. An attestation is the only part a script can't forge:
Google or Apple signs the payload hash only when it comes from your
genuine app on a real device.

The package gives you the hook; Play Integrity and App Attest are tied to
your Google Play and Apple accounts, so the platform code lives in your
app. You need three things:

1. A `LivenessAttestor` in Dart that calls your native code.
2. A little native code: Play Integrity on Android, App Attest on iOS.
3. The server checks in "Check the token on your server" below.

### Set up the accounts first

- **Android:** the app must be installed from Google Play (the internal
  testing track is enough; a sideloaded debug build gets an
  "unrecognized" verdict). In Play Console, open App integrity and link a
  Google Cloud project, enable the Play Integrity API in it, and note the
  Cloud **project number**. Your server needs a service account in the
  same project.
- **iOS:** add the **App Attest** capability to the app in Xcode
  (entitlement `com.apple.developer.devicecheck.appattest-environment`,
  `development` while testing, `production` for release). Note your
  **Team ID** and bundle ID. App Attest doesn't run on the simulator.

### The Dart side

Return a small JSON string, so your server knows which platform's token
it got and iOS can send its key ID with the assertion:

```dart
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

class PlatformAttestor extends LivenessAttestor {
  PlatformAttestor({required this.cloudProjectNumber});

  static const _channel = MethodChannel('myapp/attestation');

  /// Google Cloud project number (Android only).
  final int cloudProjectNumber;

  Future<void>? _ready;

  @override
  Future<void> prepare() => _ready ??= _channel
      .invokeMethod<void>('prepare', {'cloudProjectNumber': cloudProjectNumber})
      .catchError((Object e) {
    _ready = null; // let attest() try again
    throw e;
  });

  @override
  Future<String> attest(Uint8List payloadHash) async {
    await prepare();
    final token = await _channel.invokeMapMethod<String, Object?>(
      'attest',
      {'hash': payloadHash},
    );
    return jsonEncode(token);
  }
}
```

```dart
LivenessConfig(
  actions: const [], // ignored when a challenge is set
  challenge: challengeFromYourServer,
  attestor: PlatformAttestor(cloudProjectNumber: 123456789012),
)
```

The package calls `prepare()` when the screen opens and `attest()` once
at the end, with a 15-second limit. If `attest()` throws or times out,
`result.attestation` is null and `metadata.attestationError` says why.

### Android: Play Integrity

Add `com.google.android.play:integrity` to `android/app/build.gradle`
and register this handler on the channel in `MainActivity`:

```kotlin
class AttestationHandler(context: Context) : MethodChannel.MethodCallHandler {
    private val manager = IntegrityManagerFactory.createStandard(context)
    private var provider: StandardIntegrityTokenProvider? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> {
                val project = call.argument<Number>("cloudProjectNumber")!!.toLong()
                manager.prepareIntegrityToken(
                    PrepareIntegrityTokenRequest.builder()
                        .setCloudProjectNumber(project).build()
                ).addOnSuccessListener { provider = it; result.success(null) }
                 .addOnFailureListener { result.error("prepare", it.message, null) }
            }
            "attest" -> {
                val p = provider
                    ?: return result.error("not_ready", "prepare() failed", null)
                // The payload hash as lowercase hex is the requestHash.
                val hash = call.argument<ByteArray>("hash")!!
                    .joinToString("") { "%02x".format(it) }
                p.request(
                    StandardIntegrityTokenRequest.builder()
                        .setRequestHash(hash).build()
                ).addOnSuccessListener {
                    result.success(mapOf("platform" to "android", "token" to it.token()))
                }.addOnFailureListener { result.error("attest", it.message, null) }
            }
            else -> result.notImplemented()
        }
    }
}
```

### iOS: App Attest

App Attest has two steps. Once per install, the app creates a key and
your server registers it with Apple. Then each session signs the payload
hash with that key.

```swift
import DeviceCheck
import CryptoKit

final class AttestationHandler {
    private let service = DCAppAttestService.shared
    private let keyIdDefaultsKey = "liveness.appAttestKeyId"

    /// "prepare": make sure this install has a registered key.
    func prepare() async throws {
        _ = try await registeredKeyId()
    }

    /// "attest": sign the payload hash. The hash is already a SHA-256,
    /// so it is passed as the client data hash unchanged.
    func attest(hash: Data) async throws -> [String: String] {
        let keyId = try await registeredKeyId()
        let assertion = try await service.generateAssertion(keyId, clientDataHash: hash)
        return ["platform": "ios", "keyId": keyId,
                "assertion": assertion.base64EncodedString()]
    }

    private func registeredKeyId() async throws -> String {
        guard service.isSupported else { throw AttestationError.unsupported }
        if let keyId = UserDefaults.standard.string(forKey: keyIdDefaultsKey) {
            return keyId
        }
        let keyId = try await service.generateKey()
        // Your server: a one-time challenge, then verify the attestation
        // with Apple and store the key's public key and a counter of 0.
        let challenge = try await YourApi.attestationChallenge()
        let attestation = try await service.attestKey(
            keyId, clientDataHash: Data(SHA256.hash(data: challenge)))
        try await YourApi.registerKey(keyId: keyId, attestation: attestation)
        UserDefaults.standard.set(keyId, forKey: keyIdDefaultsKey)
        return keyId
    }
}
```

Wire it to the channel in `AppDelegate`: `"prepare"` calls `prepare()`,
`"attest"` calls `attest(hash: (args["hash"] as! FlutterStandardTypedData).data)`.
If Apple later rejects the key (for example after the app is restored to
a new phone), delete the stored key ID so the next session registers a
new one.

### Check the token on your server

Parse `metadata.attestation` as JSON and rebuild `payload_hash(meta)`
(section 3). Then:

**Android** (`"platform": "android"`): send the token to Google's
`decodeIntegrityToken` API for your package name, authenticated with the
service account, and check the decoded payload:

- `requestDetails.requestHash` equals `payload_hash(meta).hex()`
- `requestDetails.requestPackageName` is your app
- `requestDetails.timestampMillis` is within the last few minutes
- `appIntegrity.appRecognitionVerdict` is `PLAY_RECOGNIZED`
- `deviceIntegrity.deviceRecognitionVerdict` contains
  `MEETS_DEVICE_INTEGRITY` (or `MEETS_STRONG_INTEGRITY` for high-value
  flows; stricter, and it rejects more older phones)

**iOS** (`"platform": "ios"`): look up the public key and counter you
stored for `keyId` at registration, decode the assertion (CBOR with
`signature` and `authenticatorData`), and check, following Apple's
"Validating apps that connect to your server" guide:

- `nonce = SHA256(authenticatorData + payload_hash(meta))`, and the
  signature verifies against `nonce` with the stored public key
- the first 32 bytes of `authenticatorData` equal
  `SHA256("<TeamID>.<bundleID>")`
- the counter in `authenticatorData` is greater than the stored one;
  save the new value

**Policy:** a missing attestation, `attestationError`, or a failed check
should send the session to manual review, not pass it. A phone that
doesn't support attestation is not proof of fraud, but it isn't proof of
anything else either.

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
