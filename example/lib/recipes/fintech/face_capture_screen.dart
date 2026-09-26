import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liveness_flutter/liveness_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import 'brand.dart';
import 'outcome_screens.dart';

/// The liveness check with none of the package's default UI: our own top
/// bar, overlay (light scrim, circle, per-action progress ring) and
/// instruction card. The package still does all the detection.
class FaceCaptureScreen extends StatefulWidget {
  const FaceCaptureScreen({super.key});

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen> {
  final _controller = LivenessController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onResult(LivenessResult result) {
    // Closed with our X or system back: nothing to show.
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    // Camera denied: the in-screen page below handles it.
    if (result.failureReason == LivenessFailureReason.permissionDenied) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => result.success
            // Passed on the phone: now the server has to agree.
            ? VerifyingScreen(result: result)
            : FailureScreen(reason: result.failureReason),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.surface,
      body: LayoutBuilder(builder: (context, constraints) {
        // One circle, in pixels for painting and normalised for detection.
        final size = constraints.biggest;
        final diameter = size.shortestSide * 0.7;
        final circle = Rect.fromCenter(
          center: Offset(size.width / 2, size.height * 0.4),
          width: diameter,
          height: diameter,
        );
        final targetRegion = Rect.fromLTRB(
          circle.left / size.width,
          circle.top / size.height,
          circle.right / size.width,
          circle.bottom / size.height,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            LivenessDetector(
              controller: _controller,
              config: Brand.livenessConfig,
              theme: Brand.livenessTheme,
              showCloseButton: false,
              targetRegion: targetRegion,
              overlayBuilder: (context, state) =>
                  _Overlay(circle: circle, state: state),
              instructionBuilder: (context, state) =>
                  _InstructionCard(state: state),
              instructionAlignment: const Alignment(0, 0.74),
              permissionDeniedBuilder: (context, retry) =>
                  _PermissionCard(onRetry: retry),
              onResult: _onResult,
            ),
            const SafeArea(child: _TopBar()),
          ],
        );
      }),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close, color: Brand.ink),
            // Leaving cancels the session; the package still reports it.
            onPressed: () => Navigator.maybePop(context),
          ),
          const Expanded(
            child: Text(
              'Face check',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Brand.ink,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Brand.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Step 3 of 3',
              style: TextStyle(color: Brand.primary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Overlay extends StatelessWidget {
  const _Overlay({required this.circle, required this.state});

  final Rect circle;
  final LivenessSessionState state;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _CirclePainter(circle: circle, state: state)),
        if (state.phase == LivenessPhase.completed)
          Positioned(
            left: circle.center.dx - 28,
            top: circle.bottom - 28,
            child: const CircleAvatar(
              radius: 28,
              backgroundColor: Brand.success,
              child: Icon(Icons.check, color: Colors.white, size: 32),
            ),
          ),
      ],
    );
  }
}

/// Light scrim with a circular window, and a ring with one segment per
/// planned action: green when done, filling in blue while in progress.
class _CirclePainter extends CustomPainter {
  _CirclePainter({required this.circle, required this.state});

  final Rect circle;
  final LivenessSessionState state;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addOval(circle)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(scrim, Paint()..color = Brand.surface);

    // Thin edge that turns blue once the face is in place.
    canvas.drawOval(
      circle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = state.faceInPosition ? Brand.primary : Brand.track,
    );

    final ring = circle.inflate(12);
    Paint stroke(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = color;

    switch (state.phase) {
      case LivenessPhase.completed:
        canvas.drawOval(ring, stroke(Brand.success));
        return;
      case LivenessPhase.failed:
        canvas.drawOval(ring, stroke(Brand.danger));
        return;
      default:
        break;
    }

    final n = state.actionPlan.length;
    if (n == 0) {
      canvas.drawOval(ring, stroke(Brand.track));
      return;
    }
    const gap = 0.12; // radians between segments
    final sweep = (2 * math.pi - n * gap) / n;
    for (var i = 0; i < n; i++) {
      final start = -math.pi / 2 + gap / 2 + i * (sweep + gap);
      final done = i < state.completedActions.length;
      canvas.drawArc(
          ring, start, sweep, false, stroke(done ? Brand.success : Brand.track));
      final current = i == state.currentActionIndex &&
          state.phase == LivenessPhase.performingAction;
      if (current && state.actionProgress > 0) {
        canvas.drawArc(ring, start, sweep * state.actionProgress.clamp(0, 1),
            false, stroke(Brand.primary));
      }
    }
  }

  @override
  bool shouldRepaint(_CirclePainter old) =>
      old.circle != circle || old.state != state;
}

class _InstructionCard extends StatelessWidget {
  const _InstructionCard({required this.state});

  final LivenessSessionState state;

  @override
  Widget build(BuildContext context) {
    final guidance = Brand.guidanceFor(state.guidance);
    final (IconData icon, String title, String? subtitle) = switch (state.phase) {
      LivenessPhase.initializing => (
          Icons.photo_camera_outlined,
          'Opening your camera…',
          null,
        ),
      LivenessPhase.searchingFace || LivenessPhase.centeringFace => (
          Icons.face_outlined,
          'Fit your face in the circle',
          guidance ?? 'Hold your phone at eye level',
        ),
      LivenessPhase.awaitingNeutral => (
          Icons.thumb_up_alt_outlined,
          'Nice! Now look straight ahead',
          null,
        ),
      LivenessPhase.performingAction => () {
          final i = Brand.instructionFor(state.currentAction!);
          return (i.icon, i.title, guidance ?? i.hint);
        }(),
      LivenessPhase.completed => (
          Icons.verified_outlined,
          'All done',
          'Hang on a moment…',
        ),
      LivenessPhase.failed => (
          Icons.error_outline,
          Brand.failureHelp(state.failureReason).title,
          null,
        ),
    };
    final remaining = state.remaining;

    // Screen readers announce each new instruction.
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Brand.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
                color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 8)),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Brand.primary.withValues(alpha: 0.1),
              child: Icon(icon, color: Brand.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.phase == LivenessPhase.performingAction)
                    Text(
                      'Step ${state.currentActionIndex + 1} of '
                      '${state.actionPlan.length}',
                      style: const TextStyle(
                          color: Brand.muted, fontSize: 12),
                    ),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Brand.ink,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        // Guidance means "fix something": make it stand out.
                        color: guidance != null ? Brand.danger : Brand.muted,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
            if (remaining != null)
              Text(
                '${remaining.inSeconds}s',
                style: const TextStyle(
                  color: Brand.muted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Brand.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined,
              color: Brand.primary, size: 36),
          const SizedBox(height: 8),
          const Text(
            'Allow camera access',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Brand.ink,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '${Brand.name} needs your camera for the face check. Turn it on '
            'in Settings, then come back.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Brand.muted),
          ),
          const SizedBox(height: 16),
          const FilledButton(
            onPressed: openAppSettings,
            child: Text('Open Settings'),
          ),
          TextButton(onPressed: onRetry, child: const Text('I’ve allowed it')),
        ],
      ),
    );
  }
}
