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
}

/// All user-facing strings. Override for localization.
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
    this.guidanceMessages = const {
      FaceGuidance.noFace: 'Position your face in the oval',
      FaceGuidance.tooFar: 'Move closer',
      FaceGuidance.tooClose: 'Move back a little',
      FaceGuidance.notCentered: 'Center your face in the oval',
      FaceGuidance.lowLight: 'Find better lighting',
      FaceGuidance.tooBright: 'Too bright — move out of direct light',
      FaceGuidance.blurry: 'Hold still — the image is blurry',
    },
    this.actionInstructions = const {
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
    },
  });

  final String initializing;
  final String searchingFace;
  final String centeringFace;

  /// Hint shown while more than one face is visible (unless
  /// [guidanceMessages] has its own entry for [FaceGuidance.multipleFaces]).
  final String multipleFaces;
  final String awaitingNeutral;
  final String completed;
  final String failed;

  /// Shown during the color-flash challenge.
  final String holdStill;

  /// Tooltip and screen-reader label of the close button.
  final String close;

  final Map<LivenessAction, String> actionInstructions;

  /// Frame-specific hints ("move closer", "too dark", …) shown when
  /// something is wrong with the current frame.
  final Map<FaceGuidance, String> guidanceMessages;

  String instructionFor(LivenessAction action) =>
      actionInstructions[action] ?? action.name;

  String? guidanceFor(FaceGuidance guidance) =>
      guidanceMessages[guidance] ??
      (guidance == FaceGuidance.multipleFaces ? multipleFaces : null);
}
