// Recipe: drive the session from your own buttons with LivenessController.
//
// Run: flutter run -t lib/recipes/controller.dart
//
// Useful when you hide the built-in close button, want a "Try again"
// without leaving the screen, or need the live state outside the widget.

import 'package:flutter/material.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

void main() => runApp(const MaterialApp(home: ControllerPage()));

class ControllerPage extends StatefulWidget {
  const ControllerPage({super.key});

  @override
  State<ControllerPage> createState() => _ControllerPageState();
}

class _ControllerPageState extends State<ControllerPage> {
  // Create it once and dispose it with the State, like a TextEditingController.
  final _controller = LivenessController();
  LivenessResult? _lastResult;

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
            showCloseButton: false, // our buttons replace it
            config: const LivenessConfig(
              actions: [LivenessAction.blink, LivenessAction.nod],
            ),
            // Each session — including one ended by restart() — reports
            // here exactly once.
            onResult: (result) {
              if (mounted) setState(() => _lastResult = result);
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                // Rebuilds whenever the session state changes.
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => _Controls(
                    state: _controller.state,
                    lastResult: _lastResult,
                    onCancel: _controller.cancel,
                    onRestart: _controller.restart,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.state,
    required this.lastResult,
    required this.onCancel,
    required this.onRestart,
  });

  final LivenessSessionState state;
  final LivenessResult? lastResult;
  final VoidCallback onCancel;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final ended = state.phase == LivenessPhase.completed ||
        state.phase == LivenessPhase.failed;
    final result = lastResult;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Everything a custom UI can read from the state.
            Text('Phase: ${state.phase.name}'),
            Text('Plan: ${state.actionPlan.map((a) => a.name).join(' → ')}'),
            if (state.remaining != null)
              Text('Time left for this action: '
                  '${state.remaining!.inSeconds}s'),
            if (result != null)
              Text('Last result: '
                  '${result.success ? 'passed' : result.failureReason?.name}'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: ended ? null : onCancel,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: onRestart,
                    child: Text(ended ? 'Try again' : 'Restart'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
