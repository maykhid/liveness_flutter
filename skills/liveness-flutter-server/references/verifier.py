"""Reference server checks for liveness_flutter uploads.

Standard library only (Python 3.9+). Port these functions to your
backend's language and framework; keep `_self_test` as a unit test.
Run `python3 verifier.py` to execute the self-test.

What this covers: issuing challenges and verifying an upload's shape,
nonce, session ID, outcome, action order, photo hashes and the app's
review signals, idempotently, so a retried upload gets the same answer.
What it does not: verifying the Play Integrity or App Attest token itself
(pass your own `verify_attestation`, see attestation.md), face matching,
and server-side presentation-attack detection. A "pass" here means the
signed parts of the upload are consistent with a challenge you issued;
the face still has to be judged.
"""

from __future__ import annotations

import hashlib
import json
import re
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

# A photo can't fake these. Every other action is pose-only and can be
# faked with a photo tilted at the right moment, so every challenge
# should include at least one of these.
MOTION_ACTIONS = {"blink", "nod", "openMouth", "drawCircleWithNose"}

CAPTURE_KINDS = {"reference", "peak", "completion", "sequence"}


# --- Verdicts ---------------------------------------------------------------

@dataclass
class Verdict:
    decision: str  # "pass", "review" or "reject"
    reasons: list[str] = field(default_factory=list)


# --- Challenges -------------------------------------------------------------

@dataclass
class Challenge:
    nonce: str
    user_id: str
    actions: list[str]
    expires_at: datetime
    # Set when the first upload for this challenge arrives.
    session_id: Optional[str] = None
    upload_digest: Optional[str] = None
    verdict: Optional[Verdict] = None


class ChallengeStore:
    """In-memory store. Use your database in production, and make `claim`
    one atomic statement, for example:

        UPDATE challenges
           SET session_id = $3, upload_digest = $4
         WHERE nonce = $1 AND user_id = $2 AND session_id IS NULL
        RETURNING actions, expires_at;

    and, when it updates no row, read the row to tell a repeat of the same
    upload (same nonce, user, session ID and digest) from anything else.
    """

    def __init__(self) -> None:
        self._items: dict[str, Challenge] = {}
        self._lock = threading.Lock()

    def save(self, challenge: Challenge) -> None:
        with self._lock:
            self._items[challenge.nonce] = challenge

    def claim(self, nonce: str, user_id: str, session_id: str,
              upload_digest: str) -> tuple[str, Optional[Challenge]]:
        """Ties the challenge to this upload, once.

        Returns ("new", challenge) for the first upload, ("repeat",
        challenge) for a byte-identical retry of that upload, and
        ("refused", None) for an unknown nonce, another user's nonce, or a
        different upload on a used nonce. A refused claim changes nothing,
        so a leaked nonce can't be used to spoil its owner's session.
        """
        with self._lock:
            challenge = self._items.get(nonce)
            if challenge is None or challenge.user_id != user_id:
                return "refused", None
            if challenge.session_id is None:
                challenge.session_id = session_id
                challenge.upload_digest = upload_digest
                return "new", challenge
            if (challenge.session_id == session_id and
                    challenge.upload_digest == upload_digest):
                return "repeat", challenge
            return "refused", None

    def save_verdict(self, nonce: str, verdict: Verdict) -> None:
        with self._lock:
            self._items[nonce].verdict = verdict


def issue_challenge(
    store: ChallengeStore,
    user_id: str,
    pool: list[str] = ALL_ACTIONS,
    count: int = 3,
    ttl: timedelta = timedelta(minutes=5),
    now: Optional[datetime] = None,
) -> dict:
    """Creates, stores and returns a challenge as the app expects it.

    `ttl` must cover the wait before the user starts plus the whole
    session: the app's `sessionTimeout` is 2 minutes by default, and the
    phone refuses a challenge that expires before the session ends.
    `verify_upload`'s `upload_grace` then covers the upload itself.
    """
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


def upload_digest(meta: dict, images: list[bytes], frames: list[bytes]) -> str:
    """Identifies one exact upload, so a retry can be told from a replay."""
    canonical = json.dumps(meta, sort_keys=True, separators=(",", ":"))
    files = ",".join(sha256_hex(b) for b in images + frames)
    return sha256_hex(f"{canonical}|{files}".encode("utf-8"))


# --- Shape --------------------------------------------------------------------

_SHA256 = re.compile(r"^[0-9a-f]{64}$")


def _is_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _is_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def shape_problems(meta: object) -> list[str]:
    """Everything wrong with the shape and types of the metadata. Run it
    first: the other checks assume a well-formed upload."""
    if not isinstance(meta, dict):
        return ["metadata is not a JSON object"]
    problems = []

    def need(key: str, ok: Callable[[object], bool], what: str) -> None:
        if not ok(meta.get(key)):
            problems.append(f"{key} must be {what}")

    need("sessionId", lambda v: isinstance(v, str) and v != "", "a non-empty string")
    need("nonce", lambda v: v is None or isinstance(v, str), "a string or null")
    need("success", lambda v: isinstance(v, bool), "a boolean")
    need("confidenceScore", lambda v: _is_number(v) and 0 <= v <= 1, "a number from 0 to 1")
    need("completedActions",
         lambda v: isinstance(v, list) and all(a in ALL_ACTIONS for a in v),
         "a list of action names")
    need("failureReason", lambda v: v is None or isinstance(v, str), "a string or null")
    need("imageCount", _is_int, "an integer")
    need("frameCount", _is_int, "an integer")
    need("durationMs", lambda v: _is_int(v) and v >= 0, "a non-negative integer")
    need("attestation", lambda v: v is None or isinstance(v, str), "a string or null")
    need("metadata", lambda v: v is None or isinstance(v, dict), "an object")
    for key in ("images", "frames"):
        captures = meta.get(key)
        if not isinstance(captures, list):
            problems.append(f"{key} must be a list")
            continue
        for i, c in enumerate(captures):
            if not (isinstance(c, dict)
                    and "action" in c
                    and (c["action"] is None or c["action"] in ALL_ACTIONS)
                    and c.get("kind") in CAPTURE_KINDS
                    and _is_int(c.get("timestampMs"))
                    and isinstance(c.get("sha256"), str)
                    and _SHA256.match(c["sha256"])):
                problems.append(f"{key}[{i}] is malformed")
    return problems


# --- Verification -----------------------------------------------------------

def verify_upload(
    meta: object,
    images: list[bytes],
    frames: list[bytes],
    session_header: Optional[str],
    user_id: str,
    store: ChallengeStore,
    now: Optional[datetime] = None,
    verify_attestation: Optional[Callable[[str, bytes], bool]] = None,
    require_attestation: bool = True,
    upload_grace: timedelta = timedelta(minutes=2),
    review_below_confidence: float = 0.9,
    review_assisted: bool = False,
) -> Verdict:
    """Checks one upload. Safe to call again for a retried upload: the
    same upload gets the verdict it got the first time.

    `meta` is the parsed `metadata` field (LivenessResult.toJson()).
    `images[i]` / `frames[i]` are the bytes of the `images[i]` /
    `frames[i]` parts, exactly as received. `verify_attestation(token,
    payload_hash)` returns True when the platform token is valid for that
    hash. With `require_attestation` (the default), an upload without a
    verified attestation is never more than "review". Set it to False only
    for an app with no attestor, accepting that a script can then produce
    uploads that pass every check.
    """
    now = now or datetime.now(timezone.utc)

    # 0. Shape. A malformed upload is rejected without touching the nonce.
    problems = shape_problems(meta)
    if problems:
        return Verdict("reject", problems)
    assert isinstance(meta, dict)

    # 1. Nonce: issued to this user, tied to this upload once. A retry of
    # the same upload (the app retries timeouts and 5xx) gets the same
    # verdict; any other upload on a used nonce is refused.
    nonce = meta["nonce"]
    if not nonce:
        return Verdict("reject", ["no nonce: the app must use a server challenge"])
    state, challenge = store.claim(nonce, user_id, meta["sessionId"],
                                   upload_digest(meta, images, frames))
    if challenge is None:
        return Verdict("reject", ["unknown nonce, another user's nonce, "
                                  "or a different upload on a used nonce"])
    if state == "repeat" and challenge.verdict is not None:
        return challenge.verdict

    verdict = _check(meta, images, frames, session_header, challenge, now,
                     verify_attestation, require_attestation, upload_grace,
                     review_below_confidence, review_assisted)
    store.save_verdict(nonce, verdict)
    return verdict


def _check(meta, images, frames, session_header, challenge, now,
           verify_attestation, require_attestation, upload_grace,
           review_below_confidence, review_assisted) -> Verdict:
    rejects: list[str] = []
    reviews: list[str] = []

    # The phone already refused the challenge if it expired before the
    # session ended; the grace covers the upload. Use the server's clock.
    if now >= challenge.expires_at + upload_grace:
        rejects.append("challenge expired")

    # 2. Session ID.
    if session_header != meta["sessionId"]:
        rejects.append("X-Liveness-Session header does not match sessionId")

    # 3. Outcome. Failed sessions are worth storing, never passing.
    if meta["success"] is not True:
        rejects.append(f"session failed on the device: {meta['failureReason']}")

    # 4. Order.
    if meta["completedActions"] != challenge.actions:
        rejects.append("completed actions differ from the challenge")

    # 5. Photos: images[i] hashes to metadata.images[i].sha256, etc.
    for key, files, count_key in (("images", images, "imageCount"),
                                  ("frames", frames, "frameCount")):
        listed = meta[key]
        if len(files) != len(listed) or len(files) != meta[count_key]:
            rejects.append(f"{key}: count mismatch")
        elif any(sha256_hex(b) != c["sha256"] for b, c in zip(files, listed)):
            rejects.append(f"{key}: a file does not match its listed hash")
    if not meta["images"]:
        rejects.append("no photos to verify (the app must capture images)")

    # 6. Attestation: missing or invalid means review, never pass.
    diagnostics = meta.get("metadata") or {}
    token = meta["attestation"]
    if verify_attestation is None:
        if require_attestation:
            reviews.append("no attestation check configured")
    elif not token:
        reviews.append("no attestation: "
                       f"{diagnostics.get('attestationError', 'not sent')}")
    elif not rejects and not verify_attestation(token, payload_hash(meta)):
        reviews.append("attestation did not verify")

    # Review signals. None of these are covered by the attestation: they
    # are only as honest as the app that sent them, so they can send a
    # session to review but never make one pass.
    photographed = {c["action"] for c in meta["images"]
                    if c["kind"] in ("peak", "completion")}
    missing = [a for a in meta["completedActions"] if a not in photographed]
    if meta["images"] and missing:
        reviews.append(f"no photo for: {', '.join(missing)}")
    if any(not 0 <= c["timestampMs"] <= meta["durationMs"]
           for c in meta["images"] + meta["frames"]):
        reviews.append("a capture timestamp is outside the session")
    if meta["confidenceScore"] < review_below_confidence:
        reviews.append(f"confidence {meta['confidenceScore']} "
                       f"below {review_below_confidence}")
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
              header=meta["sessionId"], user="user-1", store=None, at=now,
              **options):
        options.setdefault(
            "verify_attestation", lambda token, h: h.hex() == _VECTOR_HASH)
        return verify_upload(m, images, frames, header, user,
                             store or fresh_store(), at, **options)

    assert check().decision == "pass", check()

    # A retry of the same upload gets the same verdict; anything else on a
    # used nonce is refused.
    store = fresh_store()
    assert check(store=store).decision == "pass"
    assert check(store=store).decision == "pass"
    other = {**meta, "sessionId": "LV-OTHER"}
    assert check(m=other, header="LV-OTHER", store=store).decision == "reject"
    assert check(images=_VECTOR_IMAGES[:2], store=store).decision == "reject"

    # Another user's upload doesn't spend the nonce.
    store = fresh_store()
    assert check(user="user-2", store=store).decision == "reject"
    assert check(store=store).decision == "pass"

    assert check(header="LV-OTHER").decision == "reject"
    assert check(at=now + timedelta(minutes=3)).decision == "pass"  # grace
    assert check(at=now + timedelta(minutes=5)).decision == "reject"
    assert check(images=[b"swapped", *_VECTOR_IMAGES[1:]]).decision == "reject"
    assert check(frames=[]).decision == "reject"
    reordered = {**meta, "completedActions": ["lookLeft", "blink"]}
    assert check(m=reordered).decision == "reject"
    unattested = {**meta, "attestation": None}
    assert check(m=unattested).decision == "review"
    assert check(m=unattested, verify_attestation=None).decision == "review"
    assert check(m=unattested, verify_attestation=None,
                 require_attestation=False).decision == "pass"
    low = {**meta, "confidenceScore": 0.61}
    assert check(m=low).decision == "review"

    # Malformed uploads are rejected, not crashed on.
    reference_without_action = {k: v for k, v in meta["images"][0].items()
                                if k != "action"}
    malformed = [
        None,
        [],
        {**meta, "nonce": ["x"]},
        {**meta, "confidenceScore": "0.99"},
        {**meta, "images": None},
        {**meta, "images": [{"kind": "peak"}]},
        {**meta, "images": [reference_without_action, *meta["images"][1:]]},
        {**meta, "completedActions": ["wink"]},
        {**meta, "success": "true"},
    ]
    for bad in malformed:
        assert check(m=bad).decision == "reject", bad

    challenge = issue_challenge(ChallengeStore(), "user-1", now=now)
    assert len(challenge["nonce"]) == 32
    assert MOTION_ACTIONS & set(challenge["actions"])
    print("verifier self-test passed")


if __name__ == "__main__":
    _self_test()
