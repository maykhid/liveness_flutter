import 'package:flutter/material.dart';

import '../camera/detection_geometry.dart';
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

  /// The target's bounding rect in [size] (pixels). The detector maps the
  /// same rect into camera space for the face-in-position test, so what is
  /// drawn is what is checked.
  static Rect targetRect(Size size, LivenessTheme theme) {
    final width = size.shortestSide * theme.ovalSizeFactor;
    final height =
        theme.ovalShape == TargetShape.circle ? width : width * theme.ovalAspectRatio;
    return Rect.fromCenter(
      center: Offset(
        size.width * theme.ovalCenter.dx,
        size.height * theme.ovalCenter.dy,
      ),
      width: width,
      height: height,
    );
  }

  /// [targetRect] normalised to [size] (0..1), as used for detection.
  static Rect normalizedTargetRect(Size size, LivenessTheme theme) {
    final r = targetRect(size, theme);
    return Rect.fromLTRB(
      r.left / size.width,
      r.top / size.height,
      r.right / size.width,
      r.bottom / size.height,
    );
  }

  Path _shapePath(Rect rect) {
    final path = Path();
    switch (theme.ovalShape) {
      case TargetShape.oval:
      case TargetShape.circle:
        path.addOval(rect);
      case TargetShape.roundedRect:
        path.addRRect(RRect.fromRectAndRadius(
          rect,
          Radius.circular(rect.shortestSide * 0.18),
        ));
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final oval = targetRect(size, theme);

    // Scrim with target cutout.
    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addPath(_shapePath(oval), Offset.zero)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(scrim, Paint()..color = theme.backgroundColor);

    // Oval border.
    final borderColor = switch (phase) {
      LivenessPhase.completed => theme.successColor,
      LivenessPhase.failed => theme.failureColor,
      _ => faceInPosition ? theme.ovalBorderColorActive : theme.ovalBorderColor,
    };
    canvas.drawPath(
      _shapePath(oval),
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

  /// What's wrong with the frame right now, shown under the instruction in
  /// [LivenessTheme.hintStyle]; null when nothing is (or it would repeat
  /// the instruction).
  String? get _hint {
    if (state.guidance == FaceGuidance.none ||
        state.phase == LivenessPhase.completed ||
        state.phase == LivenessPhase.failed) {
      return null;
    }
    final hint = theme.strings.guidanceFor(state.guidance);
    return hint == _instruction ? null : hint;
  }

  String get _instruction {
    final s = theme.strings;
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
    final hint = _hint;
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
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(
            hint,
            key: const ValueKey('liveness-hint'),
            style: theme.hintStyle,
            textAlign: TextAlign.center,
          ),
        ],
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
