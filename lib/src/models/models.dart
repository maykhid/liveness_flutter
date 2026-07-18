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

  Duration get duration => finishedAt.difference(startedAt);
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
    );
  }
}
