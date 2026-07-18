import 'package:flutter/material.dart';

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
  final TextStyle hintStyle;
  final TextStyle counterStyle;

  final Color successColor;
  final Color failureColor;

  /// Oval width as a fraction of the preview's shorter side.
  final double ovalSizeFactor;

  final LivenessStrings strings;
}

/// All user-facing strings. Override for localization.
class LivenessStrings {
  const LivenessStrings({
    this.initializing = 'Starting camera…',
    this.searchingFace = 'Position your face in the oval',
    this.centeringFace = 'Move closer and center your face',
    this.multipleFaces = 'Only one face should be visible',
    this.awaitingNeutral = 'Return to a neutral expression',
    this.completed = 'All done!',
    this.failed = 'Verification failed',
    this.guidanceMessages = const {
      FaceGuidance.noFace: 'Position your face in the oval',
      FaceGuidance.multipleFaces: 'Only one face should be visible',
      FaceGuidance.tooFar: 'Move closer',
      FaceGuidance.tooClose: 'Move back a little',
      FaceGuidance.notCentered: 'Center your face in the oval',
      FaceGuidance.lowLight: 'Find better lighting',
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
  final String multipleFaces;
  final String awaitingNeutral;
  final String completed;
  final String failed;
  final Map<LivenessAction, String> actionInstructions;

  /// Frame-specific hints ("move closer", "too dark", …) shown when
  /// something is wrong with the current frame.
  final Map<FaceGuidance, String> guidanceMessages;

  String instructionFor(LivenessAction action) =>
      actionInstructions[action] ?? action.name;

  String? guidanceFor(FaceGuidance guidance) => guidanceMessages[guidance];
}
