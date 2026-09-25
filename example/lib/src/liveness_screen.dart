import 'package:flutter/material.dart';
import 'package:liveness_flutter/liveness_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import 'custom_ui.dart';
import 'demo_settings.dart';

/// Called for every session result, including ones delivered from
/// `dispose()` after a system back (when this screen is already gone).
typedef OnSessionResult = void Function(
  LivenessResult result,
  List<String> events,
  LivenessChallenge? challenge,
);

class LivenessScreen extends StatefulWidget {
  const LivenessScreen({
    super.key,
    required this.settings,
    required this.onResult,
    this.challenge,
  });

  final DemoSettings settings;
  final LivenessChallenge? challenge;
  final OnSessionResult onResult;

  @override
  State<LivenessScreen> createState() => _LivenessScreenState();
}

class _LivenessScreenState extends State<LivenessScreen> {
  final _controller = LivenessController();
  final _clock = Stopwatch()..start();
  final List<String> _events = [];

  /// Set once this screen starts leaving the tree. From then on, never
  /// look up the Navigator (a result can still arrive from dispose).
  bool _leaving = false;

  // LivenessDetector reads its config once, so build it once.
  late final LivenessConfig _config =
      widget.settings.toConfig(challenge: widget.challenge);
  late final LivenessTheme _theme = widget.settings.toTheme();

  DemoSettings get _s => widget.settings;

  void _log(String text) {
    final t = (_clock.elapsedMilliseconds / 1000).toStringAsFixed(1);
    _events.add('${t}s  $text');
    debugPrint('[liveness] $text');
    if (mounted && !_leaving) setState(() {});
  }

  void _onResult(LivenessResult result) {
    final by = result.metadata['cancelledBy'];
    _log('onResult: ${result.success ? 'passed' : result.failureReason?.name}'
        '${by == null ? '' : ' (cancelledBy: $by)'}');
    debugPrint(result.toString());
    widget.onResult(result, List.of(_events), widget.challenge);

    // A restart is already starting the next session: stay.
    if (by == 'restart') return;
    // The permission screen offers "try again": stay.
    if (result.failureReason == LivenessFailureReason.permissionDenied &&
        _s.permissionScreen) {
      return;
    }
    // After a system back this screen is gone or animating out: popping
    // then would close the *previous* screen. Only pop while we're the
    // current route.
    if (!_leaving && mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
      Navigator.pop(context);
    }
  }

  @override
  void deactivate() {
    _leaving = true;
    super.deactivate();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          LivenessDetector(
            controller: _controller,
            config: _config,
            theme: _theme,
            cameraResolution: _s.resolution,
            showDebugOverlay: _s.debugOverlay,
            showCloseButton: !_s.externalControls,
            instructionAlignment: _s.externalControls
                ? const Alignment(0, 0.45)
                : const Alignment(0, 0.72),
            overlayBuilder: _s.customUi ? customOverlay : null,
            instructionBuilder: _s.customUi ? customInstructions : null,
            // With a custom window, tell detection where it is.
            targetRegion: _s.customUi ? customWindow : null,
            permissionDeniedBuilder:
                _s.permissionScreen ? _permissionDenied : null,
            onActionStarted: (a, i) => _log('started #$i ${a.name}'),
            onActionCompleted: (a, i) => _log('completed #$i ${a.name}'),
            onFeedback: (f) {
              // Started/completed are logged above; show the rest.
              if (f.type == LivenessFeedbackType.actionProgressHalf ||
                  f.type == LivenessFeedbackType.sessionSucceeded ||
                  f.type == LivenessFeedbackType.sessionFailed) {
                _log('feedback: ${f.type.name}'
                    '${f.reason == null ? '' : ' (${f.reason!.name})'}');
              }
            },
            onError: (e, _) => _log('error: $e'),
            onResult: _onResult,
          ),
          if (_s.showEventLog)
            Positioned(
              left: 8,
              top: MediaQuery.paddingOf(context).top + 52,
              child: _EventLog(events: _events),
            ),
          if (_s.externalControls)
            Align(
              alignment: Alignment.bottomCenter,
              child: _ControllerBar(controller: _controller),
            ),
        ],
      ),
    );
  }

  Widget _permissionDenied(BuildContext context, VoidCallback retry) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, size: 40),
            const SizedBox(height: 8),
            const Text(
              'Camera access is off',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Allow camera access in Settings, then come back and try again.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                const OutlinedButton(
                  onPressed: openAppSettings,
                  child: Text('Open Settings'),
                ),
                FilledButton(onPressed: retry, child: const Text('Try again')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The last few callbacks, so you can see what the package reports live.
class _EventLog extends StatelessWidget {
  const _EventLog({required this.events});

  final List<String> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    final recent = events.length > 6 ? events.sublist(events.length - 6) : events;
    return IgnorePointer(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          recent.join('\n'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

/// Drives the session from outside through [LivenessController] and shows
/// the state a custom UI can read.
class _ControllerBar extends StatelessWidget {
  const _ControllerBar({required this.controller});

  final LivenessController controller;

  String _secs(Duration? d) =>
      d == null ? '—' : '${(d.inMilliseconds / 1000).toStringAsFixed(0)}s';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(16),
        ),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final s = controller.state;
            final plan = controller.actionPlan;
            const style = TextStyle(color: Colors.white70, fontSize: 12);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${s.phase.name}'
                  '${s.currentAction == null ? '' : ' · ${s.currentAction!.name}'}'
                  '${s.guidance == FaceGuidance.none ? '' : ' · ${s.guidance.name}'}',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text('Plan: ${plan.map((a) => a.name).join(' → ')}',
                    style: style),
                Text(
                  'Action left: ${_secs(s.remaining)} of '
                  '${_secs(s.actionTimeout)} · '
                  'Session left: ${_secs(s.sessionRemaining)}',
                  style: style,
                ),
                Text('Session ID: ${controller.sessionId ?? '—'}',
                    style: style),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white),
                        onPressed: controller.cancel,
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: controller.restart,
                        child: const Text('Restart'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.maybePop(context),
                  child: const Text(
                    'Leave screen (tests onResult from dispose)',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
