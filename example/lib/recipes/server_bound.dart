// Recipe: bind the session to your backend, then upload the result.
//
// Run:  flutter run -t lib/recipes/server_bound.dart \
//         --dart-define=BACKEND_URL=https://your-api.example.com
//
// The flow:
//   1. Your server issues a challenge (nonce + actions + expiry).
//   2. The session runs exactly those actions and echoes the nonce.
//   3. You upload the result; your server verifies it before trusting it.
//      What to check is in the package's doc/server_verification.md.
//
// Without BACKEND_URL the recipe still runs, using a local stand-in
// challenge and skipping the upload. That stand-in proves nothing:
// a challenge only means something when your server made it.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:liveness_flutter/liveness_flutter.dart';

const backendUrl = String.fromEnvironment('BACKEND_URL');

void main() => runApp(const MaterialApp(home: ServerBoundPage()));

/// Step 1: ask your backend for a challenge.
///
/// Expected response: `{"nonce": "...", "actions": ["blink", "smile"],
/// "expiresAt": "2026-09-26T12:05:00Z"}`.
Future<LivenessChallenge> fetchChallenge() async {
  if (backendUrl.isEmpty) return _localStandIn();
  final response = await http
      .post(Uri.parse('$backendUrl/liveness/challenge'))
      .timeout(const Duration(seconds: 15));
  if (response.statusCode != 200) {
    throw Exception('Challenge request failed: HTTP ${response.statusCode}');
  }
  final json = jsonDecode(response.body) as Map<String, dynamic>;
  return LivenessChallenge(
    nonce: json['nonce'] as String,
    actions: [
      for (final name in json['actions'] as List)
        LivenessAction.values.byName(name as String),
    ],
    expiresAt: DateTime.parse(json['expiresAt'] as String),
  );
}

/// Step 3: upload. The uploader sends `result.toJson()` (with the nonce and
/// a SHA-256 of every photo), the photos, and an X-Liveness-Session header.
Future<String> uploadResult(LivenessResult result) async {
  if (backendUrl.isEmpty) return 'No BACKEND_URL, so nothing was uploaded.';
  try {
    await HttpLivenessUploader(
      endpoint: Uri.parse('$backendUrl/liveness'),
      headers: const {'Authorization': 'Bearer <your user token>'},
      maxRetries: 2, // network errors, timeouts and 5xx; never 4xx
    ).upload(result);
    return 'Uploaded. Your server now decides whether to trust it.';
  } on LivenessUploadException catch (e) {
    return 'The server rejected it (HTTP ${e.statusCode}).';
  } on TimeoutException {
    return 'The upload timed out.';
  } catch (e) {
    return 'The upload failed: $e';
  }
}

/// For tests: [uploadResult] with a result that was never captured.
@visibleForTesting
Future<String> uploadResultForTest() => uploadResult(LivenessResult(
      success: true,
      completedActions: const [],
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
    ));

/// Stand-in so the recipe runs without a backend. Not secure: an attacker
/// controls anything the app generates for itself.
LivenessChallenge _localStandIn() {
  final random = Random.secure();
  final actions = [
    LivenessAction.blink,
    LivenessAction.smile,
    LivenessAction.lookLeft,
    LivenessAction.nod,
  ]..shuffle(random);
  return LivenessChallenge(
    nonce: List.generate(16, (_) => random.nextInt(16).toRadixString(16))
        .join(),
    actions: actions.take(3).toList(),
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
  );
}

class ServerBoundPage extends StatefulWidget {
  const ServerBoundPage({super.key});

  @override
  State<ServerBoundPage> createState() => _ServerBoundPageState();
}

class _ServerBoundPageState extends State<ServerBoundPage> {
  bool _busy = false;
  String? _message;

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final challenge = await fetchChallenge();
      if (!mounted) return;
      final result = await Navigator.push<LivenessResult>(
        context,
        MaterialPageRoute(
          builder: (_) => _LivenessPage(challenge: challenge),
        ),
      );
      if (result == null) return; // closed with system back
      final uploaded = await uploadResult(result);
      _message = '${result.success ? 'Passed' : 'Failed: '
              '${result.failureReason?.name}'} · nonce ${result.nonce}\n'
          '$uploaded';
    } catch (e) {
      _message = 'Could not start: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Server-bound session')),
      body: Column(
        children: [
          if (backendUrl.isEmpty)
            const MaterialBanner(
              content: Text(
                'No BACKEND_URL: using a local stand-in challenge and '
                'skipping the upload. Fine for trying the flow, not secure.',
              ),
              actions: [SizedBox.shrink()],
            ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton(
                      onPressed: _busy ? null : _verify,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text("Verify it's me"),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 24),
                      Text(_message!, textAlign: TextAlign.center),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LivenessPage extends StatelessWidget {
  const _LivenessPage({required this.challenge});

  final LivenessChallenge challenge;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LivenessDetector(
        config: LivenessConfig(
          actions: const [], // the challenge decides the actions
          challenge: challenge, // runs its order; refuses it once expired
          capture: const {CaptureType.images},
        ),
        onResult: (result) {
          if (!context.mounted) return;
          if (ModalRoute.of(context)?.isCurrent ?? false) {
            Navigator.pop(context, result);
          }
        },
      ),
    );
  }
}
