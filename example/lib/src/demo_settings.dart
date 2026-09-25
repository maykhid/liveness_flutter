import 'package:flutter/material.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

import 'demo_security.dart';

/// Whether (and how) the demo asks its fake server for a challenge.
enum ChallengeMode {
  off('Off (local order)'),
  valid('Valid challenge'),
  expired('Expired challenge');

  const ChallengeMode(this.label);
  final String label;
}

/// What the demo anti-spoof analyzer reports.
enum PadMode {
  off('Off'),
  passes('Says "live" (0.05)'),
  flagsAttack('Says "attack" (0.9)');

  const PadMode(this.label);
  final String label;
}

/// Everything the demo lets you change. Mutable on purpose: the home page
/// edits it in place and builds a [LivenessConfig] from it per session.
class DemoSettings {
  // Actions
  List<LivenessAction> actions = [
    LivenessAction.blink,
    LivenessAction.smile,
    LivenessAction.lookLeft,
    LivenessAction.nod,
  ];
  bool shuffle = true;

  /// 0 = off; otherwise pick this many from [actions] per session.
  int randomCount = 0;

  // Timing
  int actionTimeoutS = 15;

  /// 0 = no whole-session limit.
  int sessionTimeoutS = 120;
  int neutralTimeoutS = 10;
  bool requireNeutral = true;
  bool fastBlinkSampling = true;

  // Capture
  Set<CaptureType> capture = {CaptureType.images};
  bool captureAtPeak = true;
  ResolutionPreset resolution = ResolutionPreset.high;

  // Anti-spoof
  bool replayGuard = true;
  bool flashChallenge = false;
  int flashAllowedMisses = 0;
  bool failOnFaceChange = false;
  PadMode pad = PadMode.off;
  ChallengeMode challenge = ChallengeMode.off;
  bool attestor = false;

  // Camera & detection
  bool assisted = false;
  bool mirrorYaw = true;
  bool invertPitch = false;

  // Look & feel
  TargetShape ovalShape = TargetShape.oval;
  double ovalSize = 0.72;
  bool customUi = false;
  bool lightTheme = false;
  bool french = false;
  bool haptics = true;
  bool debugOverlay = false;
  bool showEventLog = true;

  /// Hide the built-in close button and drive the session from a bar of
  /// our own buttons through [LivenessController].
  bool externalControls = false;

  // Permissions
  /// Ask with permission_handler before opening the screen. Turn off to
  /// let the package handle a denial itself (permissionDenied).
  bool requestPermissionFirst = false;
  bool permissionScreen = true;

  // Upload
  String endpoint = '';
  int uploadRetries = 1;

  /// Pose-only actions can be faked with a photo; the README recommends at
  /// least one of these.
  static const motionActions = {
    LivenessAction.blink,
    LivenessAction.nod,
    LivenessAction.openMouth,
    LivenessAction.drawCircleWithNose,
  };

  bool get hasMotionAction => actions.any(motionActions.contains);

  LivenessConfig toConfig({LivenessChallenge? challenge}) => LivenessConfig(
        actions: challenge == null ? List.of(actions) : const [],
        challenge: challenge,
        shuffleActions: shuffle,
        randomActionCount: randomCount == 0 ? null : randomCount,
        capture: Set.of(capture),
        captureAtPeak: captureAtPeak,
        actionTimeout: Duration(seconds: actionTimeoutS),
        sessionTimeout:
            sessionTimeoutS == 0 ? null : Duration(seconds: sessionTimeoutS),
        neutralTimeout: Duration(seconds: neutralTimeoutS),
        requireNeutralBetweenActions: requireNeutral,
        mlIntervalBlink: Duration(milliseconds: fastBlinkSampling ? 50 : 100),
        enableReplayGuard: replayGuard,
        enableFlashChallenge: flashChallenge,
        flashAllowedMisses: flashAllowedMisses,
        failOnFaceChange: failOnFaceChange,
        frameAnalyzers: [
          if (pad != PadMode.off)
            DemoPadAnalyzer(score: pad == PadMode.passes ? 0.05 : 0.9),
        ],
        attestor: attestor ? const DemoAttestor() : null,
        cameraMode: assisted
            ? LivenessCameraMode.assisted
            : LivenessCameraMode.selfService,
        mirrorYaw: mirrorYaw,
        invertPitch: invertPitch,
        hapticFeedback: haptics,
      );

  LivenessTheme toTheme() {
    var theme = const LivenessTheme(
      progressColor: Colors.tealAccent,
      ovalBorderColorActive: Colors.tealAccent,
    );
    if (lightTheme) {
      theme = theme.copyWith(
        backgroundColor: const Color(0xDDFFFFFF),
        ovalBorderColor: Colors.black54,
        progressColor: Colors.teal,
        ovalBorderColorActive: Colors.teal,
        progressTrackColor: Colors.black12,
        instructionStyle: const TextStyle(
          color: Colors.black87,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: const TextStyle(color: Colors.black54, fontSize: 14),
        counterStyle: const TextStyle(color: Colors.black54, fontSize: 13),
        closeIconColor: Colors.black87,
      );
    }
    return theme.copyWith(
      // The custom UI's window is a rounded rectangle.
      ovalShape: customUi ? TargetShape.roundedRect : ovalShape,
      ovalSizeFactor: ovalSize,
      strings: french ? frenchStrings : null,
    );
  }

  /// Partial French translation: everything not listed falls back to the
  /// English defaults (maps are merged), which is what this demonstrates.
  static final frenchStrings = LivenessStrings(
    initializing: 'Démarrage de la caméra…',
    searchingFace: 'Placez votre visage dans l’ovale',
    centeringFace: 'Ajustez votre visage dans l’ovale',
    awaitingNeutral: 'Revenez à une expression neutre',
    completed: 'Terminé !',
    failed: 'Vérification échouée',
    holdStill: 'Ne bougez plus…',
    close: 'Fermer',
    stepCounter: (current, total) => 'Étape $current sur $total',
    actionInstructions: const {
      LivenessAction.blink: 'Clignez des yeux',
      LivenessAction.smile: 'Souriez',
      LivenessAction.lookLeft: 'Tournez la tête à gauche',
      LivenessAction.nod: 'Hochez la tête',
    },
    guidanceMessages: const {
      FaceGuidance.tooFar: 'Rapprochez-vous',
      FaceGuidance.tooClose: 'Reculez un peu',
    },
    failureMessages: const {
      LivenessFailureReason.actionTimeout: 'Trop long — réessayez',
      LivenessFailureReason.cancelled: 'Annulé',
    },
  );

  /// One-line summary for the history list.
  String get summary => [
        if (challenge != ChallengeMode.off) 'challenge',
        if (randomCount > 0) 'random $randomCount' else '${actions.length} actions',
        ...capture.map((c) => c.name),
        if (flashChallenge) 'flash',
        if (pad != PadMode.off) 'PAD',
        if (attestor) 'attest',
      ].join(' · ');

  // ---------------------------------------------------------------------
  // Presets
  // ---------------------------------------------------------------------

  static DemoSettings quick() => DemoSettings()
    ..actions = [LivenessAction.blink, LivenessAction.smile]
    ..shuffle = false;

  static DemoSettings everything() => DemoSettings()
    ..actions = List.of(LivenessAction.values)
    ..randomCount = 3
    ..capture = {CaptureType.images, CaptureType.frameSequence}
    ..flashChallenge = true
    ..pad = PadMode.passes
    ..challenge = ChallengeMode.off
    ..attestor = true
    ..debugOverlay = true
    ..externalControls = true;

  static DemoSettings kyc() => DemoSettings()
    ..capture = {CaptureType.images}
    ..challenge = ChallengeMode.valid
    ..attestor = true
    ..pad = PadMode.passes
    ..flashChallenge = true;

  static DemoSettings accessible() => DemoSettings()
    ..actions = [LivenessAction.blink, LivenessAction.smile]
    ..shuffle = false
    ..actionTimeoutS = 30
    ..sessionTimeoutS = 0
    ..requireNeutral = false
    ..haptics = true
    ..lightTheme = true;
}
