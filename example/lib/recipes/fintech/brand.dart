// Everything brand-specific in one place. "AcmePay" is fictional: change
// the name, colours and wording here and the whole flow follows.

import 'package:flutter/material.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

abstract final class Brand {
  static const name = 'AcmePay';

  static const primary = Color(0xFF1739C6);
  static const primaryDark = Color(0xFF0B1F7A);
  static const success = Color(0xFF12B76A);
  static const danger = Color(0xFFD92D20);
  static const surface = Color(0xFFF4F6FB);
  static const card = Colors.white;
  static const ink = Color(0xFF101828);
  static const muted = Color(0xFF667085);
  static const track = Color(0xFFE4E7EC);

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      surface: surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Liveness settings for this flow
  // -------------------------------------------------------------------

  /// Three random actions per session from a pool that can't produce a
  /// motion-free set (only two of the four are pose-only).
  static const livenessConfig = LivenessConfig(
    actions: [
      LivenessAction.blink,
      LivenessAction.nod,
      LivenessAction.smile,
      LivenessAction.lookLeft,
    ],
    randomActionCount: 3,
    capture: {CaptureType.images},
    hapticFeedback: true,
  );

  /// The package's own screens aren't used here (we replace the overlay
  /// and the instructions), but the theme still decides the target shape
  /// and how long the final state stays on screen.
  static const livenessTheme = LivenessTheme(
    ovalShape: TargetShape.circle,
    resultHoldDuration: Duration(milliseconds: 700),
  );

  // -------------------------------------------------------------------
  // Voice
  // -------------------------------------------------------------------

  static ({IconData icon, String title, String hint}) instructionFor(
    LivenessAction action,
  ) =>
      switch (action) {
        LivenessAction.blink => (
            icon: Icons.visibility_outlined,
            title: 'Blink your eyes',
            hint: 'A normal blink is enough',
          ),
        LivenessAction.smile => (
            icon: Icons.sentiment_satisfied_alt,
            title: 'Give us a smile',
            hint: 'Hold it for a moment',
          ),
        LivenessAction.nod => (
            icon: Icons.swap_vert,
            title: 'Nod your head',
            hint: 'Down, then back up',
          ),
        LivenessAction.lookLeft => (
            icon: Icons.arrow_back,
            title: 'Turn your head left',
            hint: 'Then hold still',
          ),
        LivenessAction.lookRight => (
            icon: Icons.arrow_forward,
            title: 'Turn your head right',
            hint: 'Then hold still',
          ),
        _ => (
            icon: Icons.face_retouching_natural,
            title: const LivenessStrings().instructionFor(action),
            hint: 'Follow the instruction',
          ),
      };

  static String? guidanceFor(FaceGuidance guidance) => switch (guidance) {
        FaceGuidance.none => null,
        FaceGuidance.noFace => 'We can’t see your face yet',
        FaceGuidance.multipleFaces => 'Make sure only you are in the frame',
        FaceGuidance.tooFar => 'Move your phone a little closer',
        FaceGuidance.tooClose => 'Move your phone back a little',
        FaceGuidance.notCentered => 'Centre your face in the circle',
        FaceGuidance.lowLight => 'Find a brighter spot',
        FaceGuidance.tooBright => 'Move out of direct light',
        FaceGuidance.blurry => 'Hold your phone steady',
      };

  /// What went wrong and what to do about it, per failure reason.
  static ({String title, List<String> tips}) failureHelp(
    LivenessFailureReason? reason,
  ) =>
      switch (reason) {
        LivenessFailureReason.actionTimeout ||
        LivenessFailureReason.sessionTimeout =>
          (
            title: 'That took a little too long',
            tips: [
              'Do each step as soon as it appears',
              'Keep your face inside the circle',
            ],
          ),
        LivenessFailureReason.faceLost => (
            title: 'We lost sight of your face',
            tips: [
              'Hold your phone at eye level',
              'Keep your whole face inside the circle',
            ],
          ),
        LivenessFailureReason.multipleFaces => (
            title: 'Someone else was in the frame',
            tips: ['Find a spot where only you are visible'],
          ),
        LivenessFailureReason.permissionDenied => (
            title: 'We need your camera',
            tips: ['Allow camera access for $name in Settings'],
          ),
        LivenessFailureReason.spoofSuspected ||
        LivenessFailureReason.faceChanged =>
          (
            title: 'We couldn’t verify you this time',
            tips: [
              'Use your phone’s own front camera',
              'Make sure it’s you doing every step',
            ],
          ),
        LivenessFailureReason.challengeExpired => (
            title: 'This verification expired',
            tips: ['Start again to get a fresh one'],
          ),
        LivenessFailureReason.cancelled => (
            title: 'Verification cancelled',
            tips: ['You can continue whenever you’re ready'],
          ),
        LivenessFailureReason.systemError || null => (
            title: 'Something went wrong on our side',
            tips: [
              'Close other apps that might be using the camera',
              'Wait a moment, then try again',
            ],
          ),
      };
}
