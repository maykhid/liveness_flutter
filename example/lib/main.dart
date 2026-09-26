// The smallest useful liveness_flutter integration.
//
// More, one topic per file (each runs with `flutter run -t <file>`):
//   lib/recipes/custom_ui.dart       your own overlay and instructions
//   lib/recipes/controller.dart      your own cancel / retry buttons
//   lib/recipes/server_bound.dart    challenge from your backend + upload
//   lib/recipes/fintech/main.dart    a fully branded KYC flow
//   lib/test_bench/main.dart         every option, for testing on a device

import 'package:flutter/material.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

void main() => runApp(const MaterialApp(home: HomePage()));

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  LivenessResult? _result;

  Future<void> _verify() async {
    final result = await Navigator.push<LivenessResult>(
      context,
      MaterialPageRoute(builder: (_) => const LivenessPage()),
    );
    if (result != null) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('liveness_flutter')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: _verify,
              child: const Text("Verify it's me"),
            ),
            if (result != null) ...[
              const SizedBox(height: 24),
              Text(result.success
                  ? 'Passed ✅'
                  : 'Failed: ${result.failureReason?.name}'),
              Text('Confidence: '
                  '${(result.confidenceScore * 100).toStringAsFixed(0)} %'),
              Text('Photos: ${result.images.length}'),
            ],
          ],
        ),
      ),
    );
  }
}

class LivenessPage extends StatelessWidget {
  const LivenessPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LivenessDetector(
        config: const LivenessConfig(
          // Include at least one motion action (blink, nod, …): pose-only
          // actions can be faked with a photo.
          actions: [
            LivenessAction.blink,
            LivenessAction.smile,
            LivenessAction.lookLeft,
          ],
          shuffleActions: true, // a new order every time (anti-replay)
          capture: {CaptureType.images}, // photos your server can check
        ),
        onResult: (result) {
          // Send `result` to your backend here — see
          // lib/recipes/server_bound.dart.

          // If the user pressed back, this screen is gone or on its way
          // out: popping then would close the previous screen instead.
          if (!context.mounted) return;
          if (ModalRoute.of(context)?.isCurrent ?? false) {
            Navigator.pop(context, result);
          }
        },
      ),
    );
  }
}
