"""Reference server checks for liveness_flutter uploads.

Standard library only (Python 3.9+). Port these functions to your
backend's language and framework; keep `_self_test` as a unit test.
Run `python3 verifier.py` to execute the self-test.

What this covers: issuing challenges and verifying an upload's nonce,
session ID, outcome, action order, photo hashes and confidence signals.
What it does not: verifying the Play Integrity or App Attest token itself
(pass your own `verify_attestation`, see attestation.md), face matching,
and server-side presentation-attack detection. A "pass" here means the
upload is genuine and consistent; the face still has to be judged.
"""

from __future__ import annotations

import hashlib
import json
import secrets
import threading
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Callable, Optional

ALL_ACTIONS = [
    "blink", "smile", "fullTeethSmile", "nod", "lookLeft", "lookRight",
    "lookUp", "lookDown", "tiltLeft", "tiltRight", "eyesClosed",
    "openMouth", "drawCircleWithNose",
]

# A photo can't fake these, so every challenge should include one.
MOTION_ACTIONS = {"blink", "nod", "openMouth", "drawCircleWithNose"}


# --- Challenges -------------------------------------------------------------

@dataclass
class Challenge:
    nonce: str
    user_id: str
    actions: list[str]
    expires_at: datetime
    used: bool = False


class ChallengeStore:
    """In-memory store. Use your database in production, and make `take`
    a single atomic statement, e.g.
    UPDATE challenges SET used = true
     WHERE nonce = $1 AND used = false RETURNING ..."""

    def __init__(self) -> None:
        self._items: dict[str, Challenge] = {}
        self._lock = threading.Lock()

    def save(self, challenge: Challenge) -> None:
        with self._lock:
            self._items[challenge.nonce] = challenge

    def take(self, nonce: str) -> Optional[Challenge]:
        """Marks the challenge used and returns it, or None if it is
        unknown or was already used."""
        with self._lock:
            challenge = self._items.get(nonce)
            if challenge is None or challenge.used:
                return None
            challenge.used = True
            return challenge


def issue_challenge(
    store: ChallengeStore,
    user_id: str,
    pool: list[str] = ALL_ACTIONS,
    count: int = 3,
    ttl: timedelta = timedelta(minutes=3),
    now: Optional[datetime] = None,
) -> dict:
    """Creates, stores and returns a challenge as the app expects it."""
    if not MOTION_ACTIONS & set(pool):
        raise ValueError("the pool needs at least one motion action")
    rng = secrets.SystemRandom()
    while True:
        actions = rng.sample(pool, count)
        if MOTION_ACTIONS & set(actions):
            break
    now = now or datetime.now(timezone.utc)
    challenge = Challenge(
        nonce=secrets.token_hex(16),  # 128 bits
        user_id=user_id,
        actions=actions,
        expires_at=now + ttl,
    )
    store.save(challenge)
    return {
        "nonce": challenge.nonce,
        "actions": challenge.actions,
        "expiresAt": challenge.expires_at.strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


# --- Hashes -----------------------------------------------------------------

def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def attestation_payload(meta: dict) -> str:
    """The exact string the app's attestor signed (via its SHA-256)."""
    hashes = [c["sha256"] for c in meta["images"]] + \
             [c["sha256"] for c in meta["frames"]]
    return "|".join([
        meta["sessionId"],
        meta.get("nonce") or "",
        "true" if meta["success"] else "false",
        ",".join(meta["completedActions"]),
        ",".join(hashes),
    ])


def payload_hash(meta: dict) -> bytes:
    return hashlib.sha256(attestation_payload(meta).encode("utf-8")).digest()


# --- Verification -----------------------------------------------------------

@dataclass
class Verdict:
    decision: str  # "pass", "review" or "reject"
    reasons: list[str] = field(default_factory=list)


def verify_upload(
    meta: dict,
    images: list[bytes],
    frames: list[bytes],
    session_header: Optional[str],
    user_id: str,
    store: ChallengeStore,
    now: Optional[datetime] = None,
    verify_attestation: Optional[Callable[[str, bytes], bool]] = None,
    review_below_confidence: float = 0.9,
    review_assisted: bool = False,
) -> Verdict:
    """Checks one upload.

    `meta` is the parsed `metadata` field (LivenessResult.toJson()).
    `images[i]` / `frames[i]` are the bytes of the `images[i]` /
    `frames[i]` parts, exactly as received. `verify_attestation(token,
    payload_hash)` returns True when the platform token is valid for that
    hash; leave it None when the app has no attestor.
    """
    now = now or datetime.now(timezone.utc)
    rejects: list[str] = []
    reviews: list[str] = []

    # 1. Nonce: issued to this user, unused, unexpired by OUR clock. take()
    # marks it used whatever happens next, so it can't be replayed.
    nonce = meta.get("nonce")
    challenge = store.take(nonce) if nonce else None
    if challenge is None:
        rejects.append("unknown, missing or already used nonce")
    else:
        if challenge.user_id != user_id:
            rejects.append("challenge was issued to another user")
        if now >= challenge.expires_at:
            rejects.append("challenge expired")

    # 2. Session ID.
    if session_header != meta.get("sessionId"):
        rejects.append("X-Liveness-Session header does not match sessionId")

    # 3. Outcome. Failed sessions are worth storing, never passing.
    if meta.get("success") is not True:
        rejects.append(f"session failed on the device: {meta.get('failureReason')}")

    # 4. Order.
    if challenge is not None and meta.get("completedActions") != challenge.actions:
        rejects.append("completed actions differ from the challenge")

    # 5. Photos: images[i] hashes to metadata.images[i].sha256, etc.
    listed_images = meta.get("images", [])
    listed_frames = meta.get("frames", [])
    if len(images) != len(listed_images) or len(images) != meta.get("imageCount"):
        rejects.append("image count mismatch")
    elif any(sha256_hex(b) != c["sha256"] for b, c in zip(images, listed_images)):
        rejects.append("an image does not match its listed hash")
    if len(frames) != len(listed_frames) or len(frames) != meta.get("frameCount"):
        rejects.append("frame count mismatch")
    elif any(sha256_hex(b) != c["sha256"] for b, c in zip(frames, listed_frames)):
        rejects.append("a frame does not match its listed hash")

    if not listed_images:
        rejects.append("no photos to verify (the app must capture images)")
    else:
        photographed = {c["action"] for c in listed_images
                        if c["kind"] in ("peak", "completion")}
        missing = [a for a in meta.get("completedActions", [])
                   if a not in photographed]
        if missing:
            reviews.append(f"no photo for: {', '.join(missing)}")
        duration = meta.get("durationMs", 0)
        if any(not 0 <= c["timestampMs"] <= duration
               for c in listed_images + listed_frames):
            reviews.append("a capture timestamp is outside the session")

    # 6. Attestation: missing or invalid means review, not pass.
    diagnostics = meta.get("metadata") or {}
    token = meta.get("attestation")
    if verify_attestation is None:
        reviews.append("no attestation check configured")
    elif not token:
        reviews.append("no attestation: "
                       f"{diagnostics.get('attestationError', 'not sent')}")
    elif not rejects and not verify_attestation(token, payload_hash(meta)):
        reviews.append("attestation did not verify")

    # Soft signals.
    score = meta.get("confidenceScore", 0)
    if score < review_below_confidence:
        reviews.append(f"confidence {score} below {review_below_confidence}")
    if diagnostics.get("flashChallenge") == "failed":
        reviews.append("flash challenge failed")
    if review_assisted and diagnostics.get("cameraMode") == "assisted":
        reviews.append("assisted session")

    if rejects:
        return Verdict("reject", rejects + reviews)
    if reviews:
        return Verdict("review", reviews)
    return Verdict("pass")


# --- Self-test --------------------------------------------------------------

_VECTOR_META = json.loads("""
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
  "attestation": "{\\"platform\\":\\"test\\"}",
  "videoPath": null,
  "startedAt": "2026-10-26T12:00:00.000Z",
  "finishedAt": "2026-10-26T12:00:04.250Z",
  "durationMs": 4250,
  "metadata": {"blink_ms": 890, "lookLeft_ms": 1240, "cameraMode": "selfService"}
}
""")
_VECTOR_IMAGES = [b"reference-photo", b"blink-peak-photo", b"lookLeft-peak-photo"]
_VECTOR_FRAMES = [b"frame-0"]
_VECTOR_HASH = "7e87017d4590b7be83dd7cdf5b72ee4f0db251e75394b7324e9523099fa00190"


def _self_test() -> None:
    meta = _VECTOR_META
    assert payload_hash(meta).hex() == _VECTOR_HASH, payload_hash(meta).hex()

    now = datetime(2026, 10, 26, 12, 0, 5, tzinfo=timezone.utc)

    def fresh_store() -> ChallengeStore:
        store = ChallengeStore()
        store.save(Challenge(meta["nonce"], "user-1", ["blink", "lookLeft"],
                             now + timedelta(minutes=2)))
        return store

    def check(m=meta, images=_VECTOR_IMAGES, frames=_VECTOR_FRAMES,
              header=meta["sessionId"], user="user-1", store=None, at=now):
        return verify_upload(
            m, images, frames, header, user, store or fresh_store(), at,
            verify_attestation=lambda token, h: h.hex() == _VECTOR_HASH)

    assert check().decision == "pass", check()

    store = fresh_store()
    check(store=store)
    assert check(store=store).decision == "reject"  # nonce reused
    assert check(header="LV-OTHER").decision == "reject"
    assert check(user="user-2").decision == "reject"
    assert check(at=now + timedelta(minutes=5)).decision == "reject"
    assert check(images=[b"swapped", *_VECTOR_IMAGES[1:]]).decision == "reject"
    assert check(frames=[]).decision == "reject"
    reordered = {**meta, "completedActions": ["lookLeft", "blink"]}
    assert check(m=reordered).decision == "reject"
    unattested = {**meta, "attestation": None}
    assert check(m=unattested).decision == "review"
    low = {**meta, "confidenceScore": 0.61}
    assert check(m=low).decision == "review"

    challenge = issue_challenge(ChallengeStore(), "user-1", now=now)
    assert len(challenge["nonce"]) == 32
    assert MOTION_ACTIONS & set(challenge["actions"])
    print("verifier self-test passed")


if __name__ == "__main__":
    _self_test()
