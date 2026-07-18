import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/liveness_theme.dart';

/// Paints the scrim with an oval cutout, oval border, and a progress arc.
class LivenessOverlayPainter extends CustomPainter {
  LivenessOverlayPainter({
    required this.theme,
    required this.faceInPosition,
    required this.progress,
    required this.phase,
  });

  final LivenessTheme theme;
  final bool faceInPosition;
  final double progress;
  final LivenessPhase phase;

  /// The oval used both for painting and for the face-in-position test.
  static Rect ovalRect(Size size, double sizeFactor) {
    final shortest = size.shortestSide;
    final width = shortest * sizeFactor;
    final height = width * 1.35;
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.44),
      width: width,
      height: height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final oval = ovalRect(size, theme.ovalSizeFactor);

    // Scrim with oval cutout.
    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addOval(oval)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(scrim, Paint()..color = theme.backgroundColor);

    // Oval border.
    final borderColor = switch (phase) {
      LivenessPhase.completed => theme.successColor,
      LivenessPhase.failed => theme.failureColor,
      _ => faceInPosition ? theme.ovalBorderColorActive : theme.ovalBorderColor,
    };
    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = theme.ovalBorderWidth
        ..color = borderColor,
    );

    // Progress arc around the oval.
    final arcRect = oval.inflate(theme.ovalBorderWidth * 3);
    canvas.drawArc(
      arcRect,
      -1.5708,
      6.2832,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = theme.ovalBorderWidth
        ..color = theme.progressTrackColor,
    );
    if (progress > 0) {
      canvas.drawArc(
        arcRect,
        -1.5708,
        6.2832 * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = theme.ovalBorderWidth * 1.5
          ..color = theme.progressColor,
      );
    }
  }

  @override
  bool shouldRepaint(LivenessOverlayPainter old) =>
      old.faceInPosition != faceInPosition ||
      old.progress != progress ||
      old.phase != phase ||
      old.theme != theme;
}

/// Default instruction panel: instruction text, hint, and step counter.
class DefaultInstructionPanel extends StatelessWidget {
  const DefaultInstructionPanel({
    super.key,
    required this.state,
    required this.theme,
  });

  final LivenessSessionState state;
  final LivenessTheme theme;

  String get _instruction {
    final s = theme.strings;
    // Frame-specific problems take priority — they tell the user exactly
    // what to fix right now.
    if (state.guidance != FaceGuidance.none &&
        state.phase != LivenessPhase.completed &&
        state.phase != LivenessPhase.failed) {
      final hint = s.guidanceFor(state.guidance);
      if (hint != null) return hint;
    }
    switch (state.phase) {
      case LivenessPhase.initializing:
        return s.initializing;
      case LivenessPhase.searchingFace:
        return s.searchingFace;
      case LivenessPhase.centeringFace:
        return s.centeringFace;
      case LivenessPhase.awaitingNeutral:
        return s.awaitingNeutral;
      case LivenessPhase.performingAction:
        final action = state.currentAction;
        return action == null ? '' : s.instructionFor(action);
      case LivenessPhase.completed:
        return s.completed;
      case LivenessPhase.failed:
        return s.failed;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            _instruction,
            key: ValueKey(_instruction),
            style: state.phase == LivenessPhase.failed
                ? theme.instructionStyle.copyWith(color: theme.failureColor)
                : theme.instructionStyle,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        if (state.phase == LivenessPhase.performingAction)
          Text(
            'Step ${state.currentActionIndex + 1} of ${state.totalActions}',
            style: theme.counterStyle,
          ),
      ],
    );
  }
}
