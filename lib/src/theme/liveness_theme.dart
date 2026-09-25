import 'package:flutter/material.dart';

import '../camera/detection_geometry.dart';
import '../models/models.dart';

/// Visual + textual customization for the built-in liveness UI.
///
/// Every string is overridable for localization; every color/style for
/// branding. For full control, use the builder parameters on
/// `LivenessDetector` instead.
class LivenessTheme {
  const LivenessTheme({
    this.backgroundColor = const Color(0xCC000000),
    this.ovalBorderColor = Colors.white,
    this.ovalBorderColorActive = const Color(0xFF4CAF50),
    this.ovalBorderWidth = 3,
    this.progressColor = const Color(0xFF4CAF50),
    this.progressTrackColor = const Color(0x33FFFFFF),
    this.instructionStyle = const TextStyle(
      color: Colors.white,
      fontSize: 20,
      fontWeight: FontWeight.w600,
    ),
    this.hintStyle = const TextStyle(color: Colors.white70, fontSize: 14),
    this.counterStyle = const TextStyle(color: Colors.white70, fontSize: 13),
    this.successColor = const Color(0xFF4CAF50),
    this.failureColor = const Color(0xFFE53935),
    this.ovalSizeFactor = 0.72,
    this.ovalCenter = const Offset(0.5, 0.44),
    this.ovalAspectRatio = 1.35,
    this.ovalShape = TargetShape.oval,
    this.closeIconColor = Colors.white,
    this.closeButtonAlignment = Alignment.topLeft,
    this.flashTintOpacity = 0.75,
    this.resultHoldDuration = const Duration(milliseconds: 400),
    this.strings = const LivenessStrings(),
  });

  /// Scrim drawn over the camera outside the oval cutout.
  final Color backgroundColor;

  final Color ovalBorderColor;

  /// Border color once the face is correctly positioned.
  final Color ovalBorderColorActive;
  final double ovalBorderWidth;

  /// Progress arc drawn around the oval.
  final Color progressColor;
  final Color progressTrackColor;

  final TextStyle instructionStyle;

  /// Style of the guidance hint ("Move closer", "Find better lighting")
  /// shown under the instruction.
  final TextStyle hintStyle;
  final TextStyle counterStyle;

  final Color successColor;
  final Color failureColor;

  /// Target width as a fraction of the view's shorter side. Also sets the
  /// detection zone: the face must fill this target (see
  /// [DetectorTuning.targetFillMin]).
  final double ovalSizeFactor;

  /// Target centre, normalised to the view (0..1).
  final Offset ovalCenter;

  /// Target height / width. Ignored for [TargetShape.circle].
  final double ovalAspectRatio;

  /// Shape of the target cut-out, which is also the detection zone.
  final TargetShape ovalShape;

  /// Colour of the built-in close icon. Pick a dark one on light scrims.
  final Color closeIconColor;

  /// Where the built-in close button sits (inside the safe area).
  final AlignmentGeometry closeButtonAlignment;

  /// Opacity of the colour-flash challenge tint (0–1). Higher lights the
  /// face more strongly.
  final double flashTintOpacity;

  /// How long the final success/failure state stays on screen before
  /// `onResult` is called.
  final Duration resultHoldDuration;

  final LivenessStrings strings;
  /// A copy with the given fields replaced.
  LivenessTheme copyWith({
    Color? backgroundColor,
    Color? ovalBorderColor,
    Color? ovalBorderColorActive,
    double? ovalBorderWidth,
    Color? progressColor,
    Color? progressTrackColor,
    TextStyle? instructionStyle,
    TextStyle? hintStyle,
    TextStyle? counterStyle,
    Color? successColor,
    Color? failureColor,
    double? ovalSizeFactor,
    Offset? ovalCenter,
    double? ovalAspectRatio,
    TargetShape? ovalShape,
    Color? closeIconColor,
    AlignmentGeometry? closeButtonAlignment,
    double? flashTintOpacity,
    Duration? resultHoldDuration,
    LivenessStrings? strings,
  }) {
    return LivenessTheme(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      ovalBorderColor: ovalBorderColor ?? this.ovalBorderColor,
      ovalBorderColorActive: ovalBorderColorActive ?? this.ovalBorderColorActive,
      ovalBorderWidth: ovalBorderWidth ?? this.ovalBorderWidth,
      progressColor: progressColor ?? this.progressColor,
      progressTrackColor: progressTrackColor ?? this.progressTrackColor,
      instructionStyle: instructionStyle ?? this.instructionStyle,
      hintStyle: hintStyle ?? this.hintStyle,
      counterStyle: counterStyle ?? this.counterStyle,
      successColor: successColor ?? this.successColor,
      failureColor: failureColor ?? this.failureColor,
      ovalSizeFactor: ovalSizeFactor ?? this.ovalSizeFactor,
      ovalCenter: ovalCenter ?? this.ovalCenter,
      ovalAspectRatio: ovalAspectRatio ?? this.ovalAspectRatio,
      ovalShape: ovalShape ?? this.ovalShape,
      closeIconColor: closeIconColor ?? this.closeIconColor,
      closeButtonAlignment: closeButtonAlignment ?? this.closeButtonAlignment,
      flashTintOpacity: flashTintOpacity ?? this.flashTintOpacity,
      resultHoldDuration: resultHoldDuration ?? this.resultHoldDuration,
      strings: strings ?? this.strings,
    );
  }
}


/// All user-facing strings. Override for localization.
///
/// The three maps ([actionInstructions], [guidanceMessages],
/// [failureMessages]) are **merged over the English defaults**: pass only
/// the entries you want to change, and anything missing keeps its default
/// text rather than falling back to a raw enum name.
class LivenessStrings {
  const LivenessStrings({
    this.initializing = 'Starting camera…',
    this.searchingFace = 'Position your face in the oval',
    this.centeringFace = 'Fit your face in the oval',
    this.multipleFaces = 'Only one face should be visible',
    this.awaitingNeutral = 'Return to a neutral expression',
    this.completed = 'All done!',
    this.failed = 'Verification failed',
    this.holdStill = 'Hold still…',
    this.close = 'Close',
    this.stepCounter = _defaultStepCounter,
    Map<FaceGuidance, String> guidanceMessages = const {},
    Map<LivenessAction, String> actionInstructions = const {},
    Map<LivenessFailureReason, String> failureMessages = const {},
  })  : _guidanceMessages = guidanceMessages,
        _actionInstructions = actionInstructions,
        _failureMessages = failureMessages;

  final String initializing;
  final String searchingFace;
  final String centeringFace;

  /// Hint shown while more than one face is visible (unless
  /// [guidanceMessages] has its own entry for [FaceGuidance.multipleFaces]).
  final String multipleFaces;
  final String awaitingNeutral;
  final String completed;

  /// Failure text when [failureMessages] has nothing for the reason.
  final String failed;

  /// Shown during the color-flash challenge.
  final String holdStill;

  /// Tooltip and screen-reader label of the close button.
  final String close;

  /// "Step N of M" under the instruction. `current` is 1-based.
  final String Function(int current, int total) stepCounter;

  final Map<FaceGuidance, String> _guidanceMessages;
  final Map<LivenessAction, String> _actionInstructions;
  final Map<LivenessFailureReason, String> _failureMessages;

  static String _defaultStepCounter(int current, int total) =>
      'Step $current of $total';

  /// English defaults for [actionInstructions].
  static const defaultActionInstructions = <LivenessAction, String>{
    LivenessAction.blink: 'Blink your eyes',
    LivenessAction.smile: 'Smile',
    LivenessAction.fullTeethSmile: 'Give a big smile — show your teeth',
    LivenessAction.nod: 'Nod your head',
    LivenessAction.lookLeft: 'Turn your head to the left',
    LivenessAction.lookRight: 'Turn your head to the right',
    LivenessAction.lookUp: 'Tilt your head up',
    LivenessAction.lookDown: 'Tilt your head down',
    LivenessAction.tiltLeft: 'Tilt your head toward your left shoulder',
    LivenessAction.tiltRight: 'Tilt your head toward your right shoulder',
    LivenessAction.eyesClosed: 'Close your eyes and hold',
    LivenessAction.openMouth: 'Open your mouth wide',
    LivenessAction.drawCircleWithNose: 'Draw a circle with your nose',
  };

  /// English defaults for [guidanceMessages]. The multiple-faces hint is
  /// [multipleFaces].
  static const defaultGuidanceMessages = <FaceGuidance, String>{
    FaceGuidance.noFace: 'Position your face in the oval',
    FaceGuidance.tooFar: 'Move closer',
    FaceGuidance.tooClose: 'Move back a little',
    FaceGuidance.notCentered: 'Center your face in the oval',
    FaceGuidance.lowLight: 'Find better lighting',
    FaceGuidance.tooBright: 'Too bright — move out of direct light',
    FaceGuidance.blurry: 'Hold still — the image is blurry',
  };

  /// English defaults for [failureMessages].
  static const defaultFailureMessages = <LivenessFailureReason, String>{
    LivenessFailureReason.actionTimeout: 'Took too long — please try again',
    LivenessFailureReason.sessionTimeout: 'Took too long — please try again',
    LivenessFailureReason.multipleFaces: 'More than one face was visible',
    LivenessFailureReason.faceLost: 'Your face left the frame',
    LivenessFailureReason.cancelled: 'Cancelled',
    LivenessFailureReason.spoofSuspected: "We couldn't confirm a live camera",
    LivenessFailureReason.systemError: 'Camera problem — please try again',
    LivenessFailureReason.permissionDenied:
        'Camera access is needed — allow it in Settings',
    LivenessFailureReason.faceChanged: 'A different face appeared',
    LivenessFailureReason.challengeExpired:
        'This check expired — please start again',
  };

  /// Instruction per action: your entries merged over
  /// [defaultActionInstructions].
  Map<LivenessAction, String> get actionInstructions =>
      {...defaultActionInstructions, ..._actionInstructions};

  /// Frame-specific hints ("move closer", "too dark", …): your entries
  /// merged over [defaultGuidanceMessages].
  Map<FaceGuidance, String> get guidanceMessages =>
      {...defaultGuidanceMessages, ..._guidanceMessages};

  /// Why the session failed, shown on the failed screen: your entries
  /// merged over [defaultFailureMessages].
  Map<LivenessFailureReason, String> get failureMessages =>
      {...defaultFailureMessages, ..._failureMessages};

  String instructionFor(LivenessAction action) =>
      _actionInstructions[action] ??
      defaultActionInstructions[action] ??
      action.name;

  String? guidanceFor(FaceGuidance guidance) =>
      _guidanceMessages[guidance] ??
      defaultGuidanceMessages[guidance] ??
      (guidance == FaceGuidance.multipleFaces ? multipleFaces : null);

  /// Failure text for [reason], or [failed] when there's no reason.
  String failureFor(LivenessFailureReason? reason) =>
      (reason == null
          ? null
          : _failureMessages[reason] ?? defaultFailureMessages[reason]) ??
      failed;

  /// A copy with the given fields replaced. Maps given here replace your
  /// earlier overrides (and are again merged over the defaults).
  LivenessStrings copyWith({
    String? initializing,
    String? searchingFace,
    String? centeringFace,
    String? multipleFaces,
    String? awaitingNeutral,
    String? completed,
    String? failed,
    String? holdStill,
    String? close,
    String Function(int current, int total)? stepCounter,
    Map<FaceGuidance, String>? guidanceMessages,
    Map<LivenessAction, String>? actionInstructions,
    Map<LivenessFailureReason, String>? failureMessages,
  }) {
    return LivenessStrings(
      initializing: initializing ?? this.initializing,
      searchingFace: searchingFace ?? this.searchingFace,
      centeringFace: centeringFace ?? this.centeringFace,
      multipleFaces: multipleFaces ?? this.multipleFaces,
      awaitingNeutral: awaitingNeutral ?? this.awaitingNeutral,
      completed: completed ?? this.completed,
      failed: failed ?? this.failed,
      holdStill: holdStill ?? this.holdStill,
      close: close ?? this.close,
      stepCounter: stepCounter ?? this.stepCounter,
      guidanceMessages: guidanceMessages ?? _guidanceMessages,
      actionInstructions: actionInstructions ?? _actionInstructions,
      failureMessages: failureMessages ?? _failureMessages,
    );
  }
}
