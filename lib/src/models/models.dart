import 'dart:typed_data';
import 'dart:ui';

/// Actions the user can be asked to perform, executed in list order.
enum LivenessAction {
  /// Blink both eyes once.
  blink,

  /// Smile (relaxed smile).
  smile,

  /// Big open smile showing teeth.
  fullTeethSmile,

  /// Nod head down and back up.
  nod,

  /// Turn head to the user's left.
  lookLeft,

  /// Turn head to the user's right.
  lookRight,

  /// Tilt head up.
  lookUp,

  /// Tilt head down.
  lookDown,

  /// Tilt (roll) head toward the left shoulder.
  tiltLeft,

  /// Tilt (roll) head toward the right shoulder.
  tiltRight,

  /// Keep both eyes closed for [DetectorTuning.eyesClosedHold].
  eyesClosed,

  /// Open mouth wide. Requires contours (enabled automatically).
  openMouth,

  /// Experimental: trace a circle in the air with the tip of your nose.
  drawCircleWithNose,
}

/// Who is holding the phone during the check.
enum LivenessCameraMode {
  /// The person being verified holds the phone and faces the FRONT camera.
  /// They see the oval, instructions, and progress themselves. This is the
  /// normal mode.
  selfService,

  /// **Assisted capture**: an operator (bank agent, field officer) holds
  /// the phone and points the BACK camera at the person being verified.
  /// The operator watches the screen and relays the instructions ("please
  /// blink", "turn left") out loud — the subject cannot see the screen.
  ///
  /// Because the screen faces away from the subject:
  /// - the color-flash challenge is automatically skipped
  ///   (`metadata['flashChallenge'] = 'skippedAssistedMode'`), and
  /// - the device torch is used instead to light the subject's face in dim
  ///   conditions (see `LivenessConfig.assistedTorchEnabled`).
  assisted,
}

/// What media the session should capture. Combine freely, or use none.
enum CaptureType {
  /// One JPEG per completed action (plus an optional neutral reference).
  images,

  /// Native video recording. Reliable on iOS; on Android, CameraX cannot
  /// guarantee recording + analysis simultaneously on all devices — prefer
  /// [frameSequence] there.
  video,

  /// Timestamped JPEG frames captured at a steady rate
  /// ([LivenessConfig.frameSequenceFps]) for the whole session. Works on
  /// every device. Your backend can assemble an MP4 with one ffmpeg call —
  /// see README.
  frameSequence,
}

/// A specific, user-fixable problem with the current frame. Orthogonal to
/// [LivenessPhase]: the phase says *where* the session is, the guidance says
/// *what to tell the user right now*.
enum FaceGuidance {
  none,
  noFace,
  multipleFaces,
  tooFar,
  tooClose,
  notCentered,
  lowLight,
  blurry,
}

/// Why a session failed.
enum LivenessFailureReason {
  /// The current action was not completed within its timeout.
  actionTimeout,

  /// More than one face appeared in frame.
  multipleFaces,

  /// The face left the frame for longer than the grace period.
  faceLost,

  /// The user cancelled the session.
  cancelled,

  /// The replay guard saw a long run of pixel-identical frames — a live
  /// camera always has sensor noise, so this indicates injected/static
  /// input rather than a real camera feed.
  spoofSuspected,

  /// Camera or ML pipeline error.
  systemError,
}

/// High-level phase of a running session.
enum LivenessPhase {
  /// Waiting for the camera / detector to warm up.
  initializing,

  /// Looking for a single face positioned inside the target oval.
  searchingFace,

  /// Face found; waiting for it to be centered and at the right distance.
  centeringFace,

  /// An action is being performed.
  performingAction,

  /// Waiting for the face to return to neutral between actions.
  awaitingNeutral,

  /// All actions completed successfully.
  completed,

  /// Session failed. See [LivenessSessionState.failureReason].
  failed,
}

/// A normalized, ML-Kit-independent snapshot of one detected face on one
/// frame. All positional values are normalized to the image size (0..1).
///
/// Detectors consume only this type, which keeps them pure Dart and
/// unit-testable without a device.
class FaceSnapshot {
  const FaceSnapshot({
    required this.timestampMs,
    this.smileProbability,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    this.headEulerAngleX,
    this.headEulerAngleY,
    this.headEulerAngleZ,
    this.noseBase,
    this.mouthOpenRatio,
    required this.boundingBox,
    this.trackingId,
  });

  /// Frame timestamp in milliseconds (monotonic).
  final int timestampMs;

  /// 0..1, null if classification unavailable this frame.
  final double? smileProbability;
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;

  /// Pitch in degrees. Positive = face tilted up.
  final double? headEulerAngleX;

  /// Yaw in degrees. After mirroring normalization (see
  /// `LivenessConfig.mirrorYaw`), positive = user's left.
  final double? headEulerAngleY;

  /// Roll in degrees. Positive = head tilted toward user's left shoulder.
  final double? headEulerAngleZ;

  /// Nose base position, normalized to image size (0..1).
  final Offset? noseBase;

  /// Vertical lip gap divided by face height. ~0 closed, >0.3 wide open.
  /// Null when contours are unavailable.
  final double? mouthOpenRatio;

  /// Face bounding box, normalized to image size (0..1).
  final Rect boundingBox;

  final int? trackingId;

  /// Whether both eyes are confidently open.
  bool get eyesOpen =>
      (leftEyeOpenProbability ?? 0) > 0.7 && (rightEyeOpenProbability ?? 0) > 0.7;

  /// Whether both eyes are confidently closed.
  bool get eyesClosed =>
      leftEyeOpenProbability != null &&
      rightEyeOpenProbability != null &&
      leftEyeOpenProbability! < 0.25 &&
      rightEyeOpenProbability! < 0.25;

  /// Whether the head is roughly front-facing and expression is neutral
  /// enough to start a new action.
  bool get isNeutral {
    final yaw = (headEulerAngleY ?? 0).abs();
    final pitch = (headEulerAngleX ?? 0).abs();
    final roll = (headEulerAngleZ ?? 0).abs();
    final smiling = (smileProbability ?? 0) > 0.6;
    return yaw < 12 && pitch < 12 && roll < 12 && !smiling && !eyesClosed;
  }
}

/// One captured still image tied to a moment in the session.
class CapturedImage {
  const CapturedImage({
    required this.bytes,
    required this.action,
    required this.timestampMs,
  });

  /// JPEG-encoded bytes.
  final Uint8List bytes;

  /// The action this frame documents, or null for the initial reference shot.
  final LivenessAction? action;

  final int timestampMs;
}

/// Final output of a liveness session, handed to `onResult`.
class LivenessResult {
  const LivenessResult({
    required this.success,
    required this.completedActions,
    this.failureReason,
    this.images = const [],
    this.frameSequence = const [],
    this.videoPath,
    required this.startedAt,
    required this.finishedAt,
    this.metadata = const {},
    this.confidenceScore = 1.0,
    this.sessionId = '',
  });

  final bool success;
  final List<LivenessAction> completedActions;
  final LivenessFailureReason? failureReason;

  /// Captured per-action JPEG frames (empty unless [CaptureType.images]).
  final List<CapturedImage> images;

  /// Steady-rate session frames (empty unless [CaptureType.frameSequence]),
  /// ordered by [CapturedImage.timestampMs] with `action == null`.
  final List<CapturedImage> frameSequence;

  /// Path to the recorded session video (null unless [CaptureType.video]).
  final String? videoPath;

  final DateTime startedAt;
  final DateTime finishedAt;

  /// Per-action durations (ms) and any extra diagnostics.
  final Map<String, Object?> metadata;

  /// 0–1 composite score. Starts at 1.0 and is reduced by suspicious
  /// signals: duplicate frames, unnaturally still head motion, and frame
  /// quality problems during the session. A clean pass on a real camera
  /// scores ≥ 0.9. The individual penalties are in [metadata] under
  /// `confidence_*` keys, so your backend can apply its own weighting.
  final double confidenceScore;

  /// Unique audit ID for this session, e.g. `LV-018F3A2B9C4E-D7E31F08`
  /// (timestamp hex + cryptographically random suffix).
  final String sessionId;

  Duration get duration => finishedAt.difference(startedAt);

  /// JSON-safe summary (no image/video bytes — just facts and counts).
  /// Handy for logging and for sending alongside uploaded media.
  Map<String, Object?> toJson() => {
        'sessionId': sessionId,
        'success': success,
        'confidenceScore': double.parse(confidenceScore.toStringAsFixed(3)),
        'completedActions': completedActions.map((a) => a.name).toList(),
        'failureReason': failureReason?.name,
        'imageCount': images.length,
        'frameCount': frameSequence.length,
        'videoPath': videoPath,
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt.toIso8601String(),
        'durationMs': duration.inMilliseconds,
        'metadata': metadata,
      };

  /// Multi-line human-readable summary — `debugPrint(result.toString())`.
  @override
  String toString() {
    final b = StringBuffer('LivenessResult(\n')
      ..writeln('  sessionId: $sessionId')
      ..writeln('  success: $success'
          '${failureReason == null ? '' : ' (${failureReason!.name})'}')
      ..writeln(
          '  confidence: ${(confidenceScore * 100).toStringAsFixed(1)}%')
      ..writeln('  actions: ${completedActions.map((a) => a.name).join(' → ')}')
      ..writeln('  duration: ${duration.inMilliseconds} ms')
      ..writeln('  media: ${images.length} image(s), '
          '${frameSequence.length} frame(s)'
          '${videoPath == null ? '' : ', video: $videoPath'}');
    if (metadata.isNotEmpty) {
      b.writeln('  metadata:');
      metadata.forEach((k, v) => b.writeln('    $k: $v'));
    }
    b.write(')');
    return b.toString();
  }
}

/// Tunable thresholds for the built-in detectors. Defaults work for most
/// devices; override only if you need to.
class DetectorTuning {
  const DetectorTuning({
    this.blinkClosedThreshold = 0.25,
    this.blinkOpenThreshold = 0.7,
    this.blinkMaxDuration = const Duration(milliseconds: 1500),
    this.smileThreshold = 0.75,
    this.fullTeethSmileThreshold = 0.85,
    this.fullTeethMouthOpenRatio = 0.03,
    this.expressionHold = const Duration(milliseconds: 500),
    this.eyesClosedHold = const Duration(seconds: 2),
    this.eyesOpenTolerance = const Duration(milliseconds: 300),
    this.yawThreshold = 25,
    this.pitchThreshold = 15,
    this.rollThreshold = 20,
    this.poseHold = const Duration(milliseconds: 400),
    this.nodPitchThreshold = 12,
    this.mouthOpenRatioThreshold = 0.09,
    this.circleMinSweepDegrees = 270,
    this.circleWindow = const Duration(seconds: 10),
    this.circleMinRadius = 6,
  });

  final double blinkClosedThreshold;
  final double blinkOpenThreshold;
  final Duration blinkMaxDuration;
  final double smileThreshold;
  final double fullTeethSmileThreshold;
  final double fullTeethMouthOpenRatio;
  final Duration expressionHold;
  final Duration eyesClosedHold;

  /// Brief eye-open flickers shorter than this do not reset the
  /// eyes-closed hold timer (ML Kit probabilities jitter).
  final Duration eyesOpenTolerance;
  final double yawThreshold;
  final double pitchThreshold;
  final double rollThreshold;
  final Duration poseHold;
  final double nodPitchThreshold;
  final double mouthOpenRatioThreshold;
  final double circleMinSweepDegrees;
  final Duration circleWindow;

  /// Minimum head deflection (degrees, combined yaw+pitch magnitude) for a
  /// frame to count toward circular motion.
  final double circleMinRadius;
}

/// Configuration for a liveness session.
class LivenessConfig {
  const LivenessConfig({
    required this.actions,
    this.shuffleActions = false,
    this.capture = const {},
    this.actionTimeout = const Duration(seconds: 15),
    this.faceLostGrace = const Duration(milliseconds: 800),
    this.requireNeutralBetweenActions = true,
    this.failOnMultipleFaces = true,
    this.captureReferenceImage = true,
    this.tuning = const DetectorTuning(),
    this.mirrorYaw = true,
    this.maxImageDimension = 720,
    this.jpegQuality = 85,
    this.frameSequenceFps = 8,
    this.frameSequenceMaxFrames = 300,
    this.autoDeleteVideo = false,
    this.enableQualityChecks = true,
    this.brightnessMin = 0.10,
    this.brightnessMax = 0.95,
    this.sharpnessMin = 0.03,
    this.enableReplayGuard = true,
    this.enableFlashChallenge = false,
    this.boostScreenBrightness = true,
    this.cameraMode = LivenessCameraMode.selfService,
    this.assistedTorchEnabled = true,
  });

  /// Actions executed in order (unless [shuffleActions] is true).
  final List<LivenessAction> actions;

  /// Randomize the order of [actions] once per session.
  ///
  /// Why this exists: with a fixed, predictable order an attacker can
  /// pre-record a video of someone performing the sequence and replay it to
  /// the camera. Randomizing per session means a recording made for one
  /// session won't match the order demanded by the next, so replay attacks
  /// must be produced live. Recommended `true` in production; leave `false`
  /// when a deterministic order matters (e.g. UI tests, demos, or flows
  /// where instructions are read out in a fixed script).
  ///
  /// The executed order is reported in `LivenessResult.completedActions`,
  /// so your backend can verify the sequence it expects.
  final bool shuffleActions;

  /// Which media to capture: `{}` (none), `{CaptureType.images}`,
  /// `{CaptureType.video}`, or both. This determines how the camera is
  /// initialized, so it cannot change mid-session.
  final Set<CaptureType> capture;

  /// Per-action timeout before the session fails.
  final Duration actionTimeout;

  /// How long the face may leave the frame before failing.
  final Duration faceLostGrace;

  /// Require a neutral face between actions (prevents pose-holding).
  final bool requireNeutralBetweenActions;

  final bool failOnMultipleFaces;

  /// Capture a neutral reference image right before the first action
  /// (only when [CaptureType.images] is enabled).
  final bool captureReferenceImage;

  final DetectorTuning tuning;

  /// Front cameras mirror the preview; when true, yaw is flipped so that
  /// [LivenessAction.lookLeft] means the *user's* left. Set false if your
  /// device reports inverted turns.
  final bool mirrorYaw;

  /// Captured JPEGs (images and frame-sequence frames) are downscaled so
  /// their longest side is at most this. Camera/video resolution is set
  /// separately via `LivenessDetector.cameraResolution`.
  final int maxImageDimension;

  /// JPEG encode quality (1–100) for images and frame-sequence frames.
  /// Lower = smaller uploads. 85 is visually lossless for review purposes.
  final int jpegQuality;

  /// Target rate for [CaptureType.frameSequence] frames (clamped 1–15).
  /// Sequence frames come from the raw camera callback (~30 fps), so rates
  /// above the ML pipeline's ~10 fps throttle are fine. 8–12 plays back
  /// smoothly video-like; higher costs memory and encode time.
  final int frameSequenceFps;

  /// Hard cap on frame-sequence memory use (300 frames ≈ 37s at 8 fps;
  /// JPEGs are held in memory until the result is delivered).
  final int frameSequenceMaxFrames;

  /// Delete the recorded video file automatically when the detector widget
  /// is disposed. Images/frames are in-memory only and need no cleanup, but
  /// the video is a real temp file that otherwise lives until the OS clears
  /// temp storage. Leave false if you read [LivenessResult.videoPath] after
  /// the detector closes (upload it or copy it first, then enable this).
  final bool autoDeleteVideo;

  /// Pause the session (with guidance shown) when the frame is too dark,
  /// overexposed, or blurry, instead of letting detection silently fail.
  final bool enableQualityChecks;

  /// Average frame brightness (0–1) below this = too dark.
  final double brightnessMin;

  /// Average frame brightness (0–1) above this = overexposed.
  final double brightnessMax;

  /// Brightness spread (0–1) below this = likely blurry / out of focus.
  final double sharpnessMin;

  /// Fail the session when a long run of pixel-identical frames is seen
  /// (a live camera always has sensor noise; identical frames mean a
  /// static/injected image). Also feeds the confidence score.
  final bool enableReplayGuard;

  /// Opt-in screen-reflection challenge against video replays.
  ///
  /// After the actions succeed, the screen flashes a short sequence of
  /// randomly ordered colors (~2.5 s, "hold still"). A real face reflects
  /// the phone screen's light, so the camera sees each color's channel
  /// rise; a video replayed on another screen can't know this session's
  /// random order and won't respond correctly.
  ///
  /// Soft signal by design, because the physics depends on ambient light:
  /// the screen must be a meaningful light source on the face. Strong in
  /// dim/normal indoor lighting; weak in bright offices or near large
  /// windows (real faces may score inconclusive/failed); meaningless
  /// outdoors in daylight. Low screen brightness and strongly colored
  /// ambient light also weaken it. A failed challenge therefore only
  /// lowers [LivenessResult.confidenceScore] by 0.35 and sets
  /// `metadata['flashChallenge'] = 'failed'` — it never fails the session
  /// on its own. Treat failures as "review", not "fraud", and decide the
  /// weight server-side. See the README section on this feature.
  final bool enableFlashChallenge;

  /// Raise the screen to full brightness while the liveness screen is open,
  /// restoring the user's setting when it closes. The screen lights the
  /// face — this helps detection in dim rooms and materially strengthens
  /// the color-flash challenge (and counters battery-saver dimming).
  /// Only affects this app's window, never the system brightness setting.
  final bool boostScreenBrightness;

  /// See [LivenessCameraMode]. Default is [LivenessCameraMode.selfService]
  /// (front camera, user verifies themself). Choose
  /// [LivenessCameraMode.assisted] only for operator-held flows — the
  /// subject cannot see the instructions, so the operator must relay them.
  final LivenessCameraMode cameraMode;

  /// In [LivenessCameraMode.assisted], turn on the device torch for the
  /// whole session to light the subject's face (the screen, which normally
  /// does that job, faces the operator instead). Best-effort: ignored on
  /// devices without a torch.
  final bool assistedTorchEnabled;

  bool get captureImages => capture.contains(CaptureType.images);
  bool get captureVideo => capture.contains(CaptureType.video);
  bool get captureFrameSequence => capture.contains(CaptureType.frameSequence);
}

/// Immutable snapshot of session state, emitted on every change.
class LivenessSessionState {
  const LivenessSessionState({
    required this.phase,
    this.currentAction,
    this.currentActionIndex = 0,
    required this.totalActions,
    this.actionProgress = 0,
    this.completedActions = const [],
    this.failureReason,
    this.faceInPosition = false,
    this.remaining,
    this.guidance = FaceGuidance.none,
  });

  final LivenessPhase phase;
  final LivenessAction? currentAction;
  final int currentActionIndex;
  final int totalActions;

  /// 0..1 progress of the current action (e.g. hold timers, circle sweep).
  final double actionProgress;

  final List<LivenessAction> completedActions;
  final LivenessFailureReason? failureReason;

  /// Whether a single face is currently centered in the target oval.
  final bool faceInPosition;

  /// Time remaining before the current action times out.
  final Duration? remaining;

  /// What's wrong with the current frame, if anything — drive specific user
  /// hints from this ("move closer", "too dark", …).
  final FaceGuidance guidance;

  /// Overall progress including completed actions.
  double get overallProgress => totalActions == 0
      ? 0
      : ((completedActions.length + actionProgress.clamp(0, 1)) / totalActions)
          .clamp(0, 1)
          .toDouble();

  LivenessSessionState copyWith({
    LivenessPhase? phase,
    LivenessAction? currentAction,
    int? currentActionIndex,
    int? totalActions,
    double? actionProgress,
    List<LivenessAction>? completedActions,
    LivenessFailureReason? failureReason,
    bool? faceInPosition,
    Duration? remaining,
    FaceGuidance? guidance,
  }) {
    return LivenessSessionState(
      phase: phase ?? this.phase,
      currentAction: currentAction ?? this.currentAction,
      currentActionIndex: currentActionIndex ?? this.currentActionIndex,
      totalActions: totalActions ?? this.totalActions,
      actionProgress: actionProgress ?? this.actionProgress,
      completedActions: completedActions ?? this.completedActions,
      failureReason: failureReason ?? this.failureReason,
      faceInPosition: faceInPosition ?? this.faceInPosition,
      remaining: remaining ?? this.remaining,
      guidance: guidance ?? this.guidance,
    );
  }
}
