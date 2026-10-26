# Honest notes — read before shipping

Plain-language notes on the rough edges. Every one has a setting you can
change; nothing requires forking the package.

**This is not bank-grade security on its own.** All checking happens on
the phone, and a determined attacker controls their own phone. Treat a
passing result as a good first gate, and have your server double-check the
photos/video you upload (compare against an ID photo, look for signs of
screens or prints). That's exactly why this package captures media
*during* the actions. Server challenges, image hashes and attestation make
tampering detectable, but the face itself still has to be judged
server-side — see the [server verification guide](server_verification.md).

**Memory adds up if you turn everything up.** Photos are kept in memory
until the result is delivered. Defaults use roughly 15–35 MB per session.
Raising the frame rate *and* photo size together can OOM cheap Android
phones. `frameSequenceMaxFrames` caps the total as a safety net.

**Every face and phone is a little different.** How confidently the phone
detects a smile or head turn varies with the camera, lighting, glasses,
and the person. If one action fails too often for your users, loosen its
setting in `DetectorTuning`. Most sensitive: `fullTeethSmile` (depends on
lip-contour quality) and `eyesClosed` (brief false "eye open" flickers are
ignored; `eyesOpenTolerance` controls how brief).

**`drawCircleWithNose` is a fun extra, not a workhorse.** People must move
their whole head in a circle, and small/slow circles don't count. Expect
more retries. Test on your users' actual phones before making it
mandatory.

**Left and right, up and down.** `lookLeft` means the *user's* left.
Calibrated for Android and iPhone; if some device gets it backwards,
`mirrorYaw: false` flips it. `invertPitch: true` does the same for
`lookUp`, `lookDown` and `nod` (the up/down sign hasn't been confirmed on
every iPhone yet; `showDebugOverlay` shows the live pitch).

**Give people time — but not forever.** Each action has a 15-second limit
(`actionTimeout`), users get 10 seconds to return to a neutral face
between actions (`neutralTimeout`), and the whole session ends after 2
minutes (`sessionTimeout`, `null` to disable). For users who find the
actions difficult, use fewer/easier actions (blink, smile), longer
timeouts, and `requireNeutralBetweenActions: false`. A second face in the
background is ignored if it's small, and only fails the session if it
stays for more than half a second (`multipleFacesGrace`).

**It needs light — but it tells the user.** Too-dark, overexposed, and
blurry frames pause the session with a hint like "Find better lighting".
The action's timer keeps running while paused, so a room that stays too
dark ends in `actionTimeout` rather than hanging. Thresholds:
`brightnessMin`, `brightnessMax`, `sharpnessMin`; disable with
`enableQualityChecks: false`.

**Same person throughout?** With ML Kit tracking (on unless an action
needs contours), a face ID that changes while a face stays in view lowers
the confidence score and shows up in `metadata['identity_*']`, along with
jumps in rough face geometry. Set `failOnFaceChange: true` to fail such
sessions outright. It's off by default because a very fast head turn can
make some devices re-assign the ID. This is no substitute for server-side
face matching.

**The anti-spoof checks are honest heuristics, not magic.** The
*static-feed guard* (called the replay guard before 0.5; the setting is
still `enableReplayGuard`) catches input that can't come from a live
camera: pixel-identical frames fail the session, and near-identical frames
with a frozen face box (a re-encoded still injected as a camera) lower the
confidence score. Micro-motion flags unnaturally still sessions the same
way. **None of it detects a photo, screen or video held up to a real
camera**: the real camera adds real noise and the hand adds real motion.
That's what the actions, the [color flash](flash_challenge.md), and
server-side review of the captured media are for. If the guard ever
misfires on a device (it shouldn't — real sensors are noisy),
`enableReplayGuard: false` turns it off.

## Status: beta

liveness_flutter is in **beta**. It's tested on real Android and iOS
devices, but it's still evolving and the API may change before 1.0. Until
then, a minor release (0.5 → 0.6) can include breaking changes; each one
is listed under **Breaking** in the
[CHANGELOG](https://github.com/maykhid/liveness_flutter/blob/main/CHANGELOG.md).
Depend on `^0.6.0` and you'll only get compatible updates.

**Anyone can [open an issue](https://github.com/maykhid/liveness_flutter/issues)**
— bugs, a phone where detection misbehaves, confusing docs, or ideas. For
detection problems, include your phone model, OS version, and what
`showDebugOverlay: true` shows.
