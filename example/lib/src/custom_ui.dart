// Custom UI demo: fully restyle the liveness screen with overlayBuilder +
// instructionBuilder, and make detection follow the custom window with
// targetRegion.

import 'package:flutter/material.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

/// The custom window, normalised to the screen (0..1). The same rect is
/// painted below and passed as `LivenessDetector.targetRegion`, so the
/// face has to be where the window is drawn.
const customWindow = Rect.fromLTWH(0.125, 0.18, 0.75, 0.44);

Widget customOverlay(BuildContext context, LivenessSessionState state) {
  final borderColor = switch (state.phase) {
    LivenessPhase.completed => Colors.greenAccent,
    LivenessPhase.failed => Colors.redAccent,
    _ => state.faceInPosition ? Colors.tealAccent : Colors.white38,
  };

  return Stack(fit: StackFit.expand, children: [
    CustomPaint(painter: _WindowPainter(borderColor: borderColor)),
    // Whole-session progress bar at the top.
    Align(
      alignment: const Alignment(0, -0.85),
      child: SizedBox(
        width: 220,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: state.overallProgress,
            minHeight: 6,
            backgroundColor: Colors.white24,
            color: Colors.tealAccent,
          ),
        ),
      ),
    ),
  ]);
}

Widget customInstructions(BuildContext context, LivenessSessionState state) {
  final text = switch (state.phase) {
    LivenessPhase.initializing => 'Warming up…',
    LivenessPhase.searchingFace => 'Show us your face 👀',
    LivenessPhase.centeringFace => switch (state.guidance) {
        FaceGuidance.tooFar => 'A bit closer…',
        FaceGuidance.tooClose => 'A bit further…',
        FaceGuidance.notCentered => 'Into the window…',
        _ => 'Almost there…',
      },
    LivenessPhase.awaitingNeutral => 'Relax your face',
    LivenessPhase.performingAction => switch (state.currentAction!) {
        LivenessAction.blink => 'Blink! 😉',
        LivenessAction.smile => 'Smile! 😊',
        LivenessAction.fullTeethSmile => 'Big smile — show those teeth! 😁',
        LivenessAction.nod => 'Nod your head 🙂↕️',
        LivenessAction.lookLeft => 'Look left ⬅️',
        LivenessAction.lookRight => 'Look right ➡️',
        LivenessAction.lookUp => 'Look up ⬆️',
        LivenessAction.lookDown => 'Look down ⬇️',
        LivenessAction.tiltLeft => 'Tilt to your left shoulder ↖️',
        LivenessAction.tiltRight => 'Tilt to your right shoulder ↗️',
        LivenessAction.eyesClosed => 'Close your eyes and hold 😌',
        LivenessAction.openMouth => 'Open wide 😮',
        LivenessAction.drawCircleWithNose => 'Draw a circle with your nose ⭕',
      },
    LivenessPhase.completed => 'You\'re verified ✅',
    LivenessPhase.failed => switch (state.failureReason) {
        LivenessFailureReason.actionTimeout ||
        LivenessFailureReason.sessionTimeout =>
          'Out of time ⏱️',
        LivenessFailureReason.faceLost => 'We lost you 🫥',
        LivenessFailureReason.cancelled => 'Cancelled',
        _ => 'Let\'s try that again',
      },
  };

  final remaining = state.remaining;
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
      const SizedBox(height: 12),
      // One labelled dot per planned action (state.actionPlan is known
      // from the first frame): green = done, white = current.
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < state.actionPlan.length; i++)
            _StepChip(
              label: state.actionPlan[i].name,
              done: i < state.completedActions.length,
              current: i == state.currentActionIndex &&
                  state.phase == LivenessPhase.performingAction,
            ),
        ],
      ),
      if (remaining != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: 160,
            child: LinearProgressIndicator(
              value: remaining.inMilliseconds /
                  state.actionTimeout.inMilliseconds,
              backgroundColor: Colors.white24,
              color: Colors.white70,
            ),
          ),
        ),
    ],
  );
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.label,
    required this.done,
    required this.current,
  });

  final String label;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: done
            ? Colors.greenAccent.withValues(alpha: 0.8)
            : current
                ? Colors.white
                : Colors.white24,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: done || current ? Colors.black : Colors.white70,
        ),
      ),
    );
  }
}

/// Dimmed background with a rounded-rectangle window at [customWindow].
class _WindowPainter extends CustomPainter {
  _WindowPainter({required this.borderColor});

  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final window = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        customWindow.left * size.width,
        customWindow.top * size.height,
        customWindow.right * size.width,
        customWindow.bottom * size.height,
      ),
      const Radius.circular(32),
    );
    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(window)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
        scrim, Paint()..color = Colors.black.withValues(alpha: 0.75));
    canvas.drawRRect(
      window,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = borderColor,
    );
  }

  @override
  bool shouldRepaint(_WindowPainter old) => old.borderColor != borderColor;
}
