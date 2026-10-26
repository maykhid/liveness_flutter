# Wire format

What the app sends, field by field. This describes the package's built-in
`HttpLivenessUploader`. An app using `LivenessUploader.custom` can send
anything; ask what it sends, and insist it keeps `result.toJson()` and the
file bytes unchanged.

## The request

`POST <endpoint>`, `multipart/form-data`, plus any headers the app adds
(usually `Authorization`).

| Part | Kind | Content |
|---|---|---|
| `X-Liveness-Session` | header | The session ID, same as `metadata.sessionId`. |
| `metadata` | text field | `LivenessResult.toJson()` as JSON (below). |
| `images[0]`, `images[1]`, … | files | One JPEG per photo, in the order of `metadata.images`. Named `<action>_<kind>_<timestampMs>ms.jpg`, or `reference_<timestampMs>ms.jpg`. |
| `frames[0]`, `frames[1]`, … | files | Frame-sequence JPEGs, in the order of `metadata.frames`. Named `frame_0000_<timestampMs>ms.jpg`. |
| `video` | file | The session recording, if captured. Its container format depends on the platform. Not hashed in the metadata, so it carries no integrity guarantee. |

The part names can be renamed by the app (`imageFieldName`,
`frameFieldName`, `videoFieldName`, `metadataFieldName`). The literal
brackets are part of the field name: many frameworks keep `images[0]` as
the name (multer's `upload.any()`, FastAPI/Starlette's form, Go's
`multipart.Reader`); some (PHP, `qs`-style parsers) turn them into arrays.
Read the index from the name and don't rely on arrival order alone.

A large upload with photos is a few MB; with a frame sequence, tens of
MB. Set body limits accordingly.

## The `metadata` JSON

A sample (the test vector used in [../SKILL.md](../SKILL.md); real photo
hashes are of real JPEG bytes):

```json
{
  "sessionId": "LV-0192C3D4E5F6-0A1B2C3D",
  "nonce": "9f2c4e6a8b0d1f3e5a7c9e1b3d5f7a9c",
  "success": true,
  "confidenceScore": 0.97,
  "completedActions": ["blink", "lookLeft"],
  "failureReason": null,
  "imageCount": 3,
  "frameCount": 1,
  "images": [
    {"action": null, "kind": "reference", "timestampMs": 420,
     "sha256": "6b1e5f80828d2b0e6acbc3496026d3dd05163d39cb0b22ca86a360f86d69388e"},
    {"action": "blink", "kind": "peak", "timestampMs": 1310,
     "sha256": "80fb272a1dcf2d5f245583a1bab1f278aa62fea2a6907741ab0e8c78e37f0fef"},
    {"action": "lookLeft", "kind": "peak", "timestampMs": 2875,
     "sha256": "ac991dc77af749e06be09087288c3506c629d13b1cc08faba946f73ef37225c9"}
  ],
  "frames": [
    {"action": null, "kind": "sequence", "timestampMs": 125,
     "sha256": "f8952f8aff2a83a859aa47f33adb73441412143c3982ae0e7ec57d49d0ba7320"}
  ],
  "attestation": null,
  "videoPath": null,
  "startedAt": "2026-10-26T12:00:00.000Z",
  "finishedAt": "2026-10-26T12:00:04.250Z",
  "durationMs": 4250,
  "metadata": {"blink_ms": 890, "lookLeft_ms": 1240, "cameraMode": "selfService"}
}
```

In this vector the "photos" are the UTF-8 bytes of `reference-photo`,
`blink-peak-photo`, `lookLeft-peak-photo` and `frame-0`, so a test can
rebuild every hash.

| Field | Type | Notes |
|---|---|---|
| `sessionId` | string | `LV-<timestamp hex>-<random hex>`. Unique per session. |
| `nonce` | string or null | The challenge's nonce; null when the app used no challenge. |
| `success` | bool | The phone's verdict. |
| `confidenceScore` | number | 0 to 1, three decimals. Lowered by suspicious signals; a clean pass is 0.9 or more. |
| `completedActions` | string[] | Actions done, in the order they ran. |
| `failureReason` | string or null | See the list below. |
| `imageCount`, `frameCount` | int | Lengths of `images` and `frames`. |
| `images`, `frames` | object[] | `action` (string or null), `kind`, `timestampMs` (milliseconds on the session's clock), `sha256` (lowercase hex of the JPEG bytes). |
| `attestation` | string or null | Whatever the app's attestor returned. Often a JSON string; see [attestation.md](attestation.md). |
| `videoPath` | string or null | A path on the phone. Meaningless to the server except as "a video was recorded". |
| `startedAt`, `finishedAt` | string | ISO 8601 from the phone's clock. Don't trust for expiry. |
| `durationMs` | int | |
| `metadata` | object | Diagnostics, below. Keys can be added in any release; ignore unknown ones. |

### Enum values

`completedActions` and `challenge.actions` use these names (13):
`blink`, `smile`, `fullTeethSmile`, `nod`, `lookLeft`, `lookRight`,
`lookUp`, `lookDown`, `tiltLeft`, `tiltRight`, `eyesClosed`, `openMouth`,
`drawCircleWithNose`. Motion actions (include at least one per
challenge): `blink`, `nod`, `openMouth`, `drawCircleWithNose`. The app
throws on a name it doesn't know, so don't send names a newer package
version added until the app is updated.

`kind`: `reference` (neutral face before the first action), `peak` (the
clearest moment of an action), `completion` (the frame where the action
passed, when there was no peak), `sequence` (frame-sequence frame).

`failureReason`: `actionTimeout`, `sessionTimeout`, `multipleFaces`,
`faceLost`, `cancelled`, `spoofSuspected`, `systemError`,
`permissionDenied`, `faceChanged`, `challengeExpired`. New values can
appear in minor releases.

### Diagnostics in `metadata.metadata`

| Key | Meaning |
|---|---|
| `<action>_ms` | Time the action took, e.g. `blink_ms`. |
| `cameraMode` | `selfService` (front camera, user holds it) or `assisted` (operator points the back camera at someone else). |
| `confidence_duplicateFrames`, `confidence_nearDuplicateFrames`, `confidence_nearDuplicateRuns` | Static-feed guard counters (frozen or injected feeds). |
| `confidence_lowMotionWindows`, `confidence_motionWindows` | Unnatural stillness. |
| `confidence_qualityViolations` | Frames too dark, too bright or blurry. |
| `identity_trackingIdChanges`, `identity_trackingIdChangesContinuous`, `identity_signatureFrames`, `identity_signatureJumps` | Signs that the face changed mid-session. |
| `flashChallenge` | `passed`, `failed`, `inconclusive`, `skippedAssistedMode` or `interrupted` when the app enabled it. |
| `analyzers` | Per anti-spoof model in the app: `{scores, mean, max, errors}`. |
| `attestationError` | Why there's no attestation (attestor threw, timed out after 15 s, or `skipped: disposed`). |
| `videoUnavailable` | `true` when the phone couldn't record video. |
| `cancelledBy` | For cancelled sessions: `user`, `lifecycle`, `restart`, `dispose`. |
| `timeoutPhase` | `awaitingNeutral` when the timeout was between actions. |
| `configError` | The app's config was invalid (`systemError`). |

Log the counters with each decision. They are the raw material for
learning what normal looks like before enforcing thresholds.

## Rebuilding the hash list in other languages

Python is in [verifier.py](verifier.py). TypeScript (Node):

```ts
import { createHash } from "node:crypto";

interface Capture { action: string | null; kind: string; timestampMs: number; sha256: string }
interface LivenessMeta {
  sessionId: string;
  nonce: string | null;
  success: boolean;
  completedActions: string[];
  images: Capture[];
  frames: Capture[];
}

export const sha256Hex = (bytes: Uint8Array): string =>
  createHash("sha256").update(bytes).digest("hex");

/** The string the app's attestor signed, and its SHA-256. */
export function payloadHash(meta: LivenessMeta): Buffer {
  const hashes = [...meta.images, ...meta.frames].map((c) => c.sha256);
  const payload = [
    meta.sessionId,
    meta.nonce ?? "",
    meta.success ? "true" : "false",
    meta.completedActions.join(","),
    hashes.join(","),
  ].join("|");
  return createHash("sha256").update(payload, "utf8").digest();
}

/** images[i] must hash to meta.images[i].sha256, and the same for frames. */
export function filesMatch(meta: LivenessMeta, images: Uint8Array[], frames: Uint8Array[]): boolean {
  const same = (files: Uint8Array[], listed: Capture[]) =>
    files.length === listed.length && files.every((f, i) => sha256Hex(f) === listed[i].sha256);
  return same(images, meta.images) && same(frames, meta.frames);
}
```

Go:

```go
package liveness

import (
	"crypto/sha256"
	"encoding/hex"
	"strings"
)

type Capture struct {
	Action      *string `json:"action"`
	Kind        string  `json:"kind"`
	TimestampMs int64   `json:"timestampMs"`
	SHA256      string  `json:"sha256"`
}

type Meta struct {
	SessionID        string    `json:"sessionId"`
	Nonce            *string   `json:"nonce"`
	Success          bool      `json:"success"`
	CompletedActions []string  `json:"completedActions"`
	Images           []Capture `json:"images"`
	Frames           []Capture `json:"frames"`
}

// PayloadHash is the SHA-256 the app's attestor signed.
func PayloadHash(m Meta) [32]byte {
	hashes := make([]string, 0, len(m.Images)+len(m.Frames))
	for _, c := range append(append([]Capture{}, m.Images...), m.Frames...) {
		hashes = append(hashes, c.SHA256)
	}
	nonce := ""
	if m.Nonce != nil {
		nonce = *m.Nonce
	}
	success := "false"
	if m.Success {
		success = "true"
	}
	payload := strings.Join([]string{
		m.SessionID, nonce, success,
		strings.Join(m.CompletedActions, ","),
		strings.Join(hashes, ","),
	}, "|")
	return sha256.Sum256([]byte(payload))
}

// FileHash is the lowercase hex SHA-256 of an uploaded file's bytes.
func FileHash(b []byte) string {
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}
```
