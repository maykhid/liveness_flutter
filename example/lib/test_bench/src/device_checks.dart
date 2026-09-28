// Guided device checks: each scenario applies its own settings, says what
// to do and what should happen, and records pass / fail. The report at the
// end can be copied and sent with a bug report.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

import '../../recipes/fintech/brand.dart';
import '../../recipes/fintech/face_capture_screen.dart';
import 'demo_settings.dart';

/// Where a check runs.
enum CheckTarget {
  /// The test bench's liveness screen, with [DeviceCheck.settings].
  testBench,

  /// The branded fintech face check (its circle sits under an app bar).
  fintech,
}

enum CheckStatus { notRun, passed, failed, skipped }

class DeviceCheck {
  const DeviceCheck({
    required this.id,
    required this.title,
    required this.steps,
    required this.expected,
    this.target = CheckTarget.testBench,
    this.settings,
    this.androidOnly = false,
  });

  final String id;
  final String title;
  final List<String> steps;
  final List<String> expected;
  final CheckTarget target;

  /// Test-bench settings for this check (ignored for [CheckTarget.fintech]).
  final DemoSettings Function()? settings;
  final bool androidOnly;
}

DemoSettings _only(List<LivenessAction> actions) => DemoSettings()
  ..actions = actions
  ..shuffle = false;

/// Every scenario, most important first. Checks 1–8 cover code that
/// changed after the review; 9 onward are a regression sweep.
final deviceChecks = <DeviceCheck>[
  const DeviceCheck(
    id: '1',
    title: 'Camera fills the circle under an app bar',
    target: CheckTarget.fintech,
    steps: [
      'Go through the face check.',
      'Look at the camera image inside the circle.',
      'Try with your face centred, then off to one side.',
    ],
    expected: [
      'The image is not stretched or oddly zoomed; nothing covers the top bar.',
      'Centred face is accepted; off to one side says "Centre your face".',
    ],
  ),
  DeviceCheck(
    id: '2',
    title: 'Face box sits on your face',
    settings: () => DemoSettings()
      ..debugOverlay = true
      ..ovalShape = TargetShape.circle
      ..ovalSize = 0.6,
    steps: const [
      'Start, then move your head around slowly.',
      'Move near the edge of the circle, then outside it.',
    ],
    expected: const [
      'The green box follows your face closely.',
      '"In position" (green ring) matches the circle drawn on screen.',
    ],
  ),
  DeviceCheck(
    id: '3',
    title: 'Restart five times quickly',
    settings: () => DemoSettings()..externalControls = true,
    steps: const [
      'Start, then tap Restart in the bottom bar 5 times in a row, fast.',
      'Wait for the camera after the last one.',
    ],
    expected: const [
      'The camera comes back every time.',
      'No "Camera problem" failure in the session list.',
    ],
  ),
  const DeviceCheck(
    id: '4',
    title: 'Close while the camera is starting',
    settings: DemoSettings.quick,
    steps: [
      'Start, and tap the X immediately — before the camera image appears.',
      'Run this check again 3–4 times.',
    ],
    expected: [
      'No error; each run opens the camera normally.',
    ],
  ),
  DeviceCheck(
    id: '5',
    title: 'Torch turns off when leaving',
    androidOnly: true,
    settings: () => DemoSettings()..assisted = true,
    steps: const [
      'Start (the back camera and torch come on), then leave immediately.',
      'Then run it again and leave after a few seconds.',
    ],
    expected: const ['The torch turns off both times.'],
  ),
  DeviceCheck(
    id: '6',
    title: 'Leave during the colour flash',
    settings: () => _only([LivenessAction.blink])..flashChallenge = true,
    steps: const [
      'Complete the blink.',
      'While the screen flashes colours, press back.',
      'Open the newest entry in the session list.',
    ],
    expected: const [
      'No crash.',
      'Result: "Failed: cancelled (dispose)" and flashChallenge: interrupted '
          'in the anti-spoof signals.',
    ],
  ),
  DeviceCheck(
    id: '7',
    title: 'Holds only count time the face was seen',
    settings: () => _only([LivenessAction.lookLeft]),
    steps: const [
      'Run once: turn left and hold normally.',
      'Run again: turn left, cover the camera with your hand for about half '
          'a second, then uncover while still turned.',
    ],
    expected: const [
      'First run passes about as quickly as before.',
      'Second run does NOT pass the instant you uncover; it needs a moment.',
    ],
  ),
  DeviceCheck(
    id: '8',
    title: 'Poor light ends, never hangs',
    settings: () => _only([LivenessAction.smile])..actionTimeoutS = 10,
    steps: const [
      'Start in a dim room (or cover most of the camera).',
      'Wait without improving the light.',
    ],
    expected: const [
      '"Find better lighting" shows while it is too dark.',
      'The session fails with a timeout within ~10 s instead of hanging.',
    ],
  ),
  DeviceCheck(
    id: '9',
    title: 'Photos show each action at its peak',
    settings: () => _only([
      LivenessAction.blink,
      LivenessAction.lookLeft,
      LivenessAction.nod,
    ]),
    steps: const [
      'Pass the session, then open its result and look at the photos.',
    ],
    expected: const [
      'Blink photo: eyes shut. Look-left photo: head turned. '
          'Nod photo: head down.',
    ],
  ),
  const DeviceCheck(
    id: '10',
    title: 'Server checks all green (KYC)',
    settings: DemoSettings.kyc,
    steps: ['Pass the session, then open its result.'],
    expected: [
      'All "server-side checks" are green: nonce, action order, media '
          'hashes, attestation.',
    ],
  ),
  DeviceCheck(
    id: '11',
    title: 'Fast blink is detected',
    settings: () => _only([LivenessAction.blink]),
    steps: const ['Blink as quickly as you can.'],
    expected: const ['The blink is detected.'],
  ),
  const DeviceCheck(
    id: '12',
    title: 'Back mid-session still reports a result',
    settings: DemoSettings.quick,
    steps: [
      'Start, and press the system back button (or swipe back) mid-session.',
    ],
    expected: [
      'A "cancelled (dispose)" entry appears in the session list.',
    ],
  ),
  const DeviceCheck(
    id: '13',
    title: 'Camera access denied',
    target: CheckTarget.fintech,
    steps: [
      'First turn camera access OFF for this app in the phone\'s Settings.',
      'Run the check.',
      'Turn access back on, return, tap "I\'ve allowed it".',
    ],
    expected: [
      'The branded "Allow camera access" card appears.',
      'After allowing, the face check starts normally.',
    ],
  ),
  DeviceCheck(
    id: '14',
    title: 'A second face fails the session',
    settings: () => _only([LivenessAction.smile])..actionTimeoutS = 20,
    steps: const [
      'Start with someone next to you, both faces in view and about the '
          'same size, for a couple of seconds.',
    ],
    expected: const [
      '"Only one face should be visible", then the session fails with '
          'multipleFaces after about half a second.',
    ],
  ),
  DeviceCheck(
    id: '15',
    title: 'A second face is ignored when allowed',
    settings: () => _only([LivenessAction.smile])
      ..actionTimeoutS = 20
      ..failOnMultipleFaces = false,
    steps: const [
      'Same as 14: someone next to you, both faces in view. Then smile.',
    ],
    expected: const [
      'The session runs normally (the larger face is used) and passes.',
    ],
  ),
];

/// Results for this app run.
class DeviceCheckLog extends ChangeNotifier {
  final Map<String, (CheckStatus, String)> _results = {};
  String deviceModel = '';

  CheckStatus statusOf(String id) =>
      _results[id]?.$1 ?? CheckStatus.notRun;
  String noteOf(String id) => _results[id]?.$2 ?? '';

  void record(String id, CheckStatus status, String note) {
    _results[id] = (status, note.trim());
    notifyListeners();
  }

  int count(CheckStatus status) =>
      deviceChecks.where((c) => statusOf(c.id) == status).length;

  /// Plain text to paste into an issue or a message.
  String report() {
    final b = StringBuffer()
      ..writeln('liveness_flutter device checks')
      ..writeln('Date: ${DateTime.now().toIso8601String().split('.').first}')
      ..writeln('Device: ${deviceModel.isEmpty ? '(not given)' : deviceModel}')
      ..writeln('OS: ${Platform.operatingSystem} '
          '${Platform.operatingSystemVersion}')
      ..writeln('Passed ${count(CheckStatus.passed)}, '
          'failed ${count(CheckStatus.failed)}, '
          'skipped ${count(CheckStatus.skipped)}, '
          'not run ${count(CheckStatus.notRun)}')
      ..writeln();
    for (final c in deviceChecks) {
      final label = switch (statusOf(c.id)) {
        CheckStatus.passed => 'PASS',
        CheckStatus.failed => 'FAIL',
        CheckStatus.skipped => 'SKIP',
        CheckStatus.notRun => '----',
      };
      b.writeln('[$label] ${c.id}. ${c.title}');
      final note = noteOf(c.id);
      if (note.isNotEmpty) b.writeln('       $note');
    }
    return b.toString();
  }
}

/// Runs a check's test-bench settings (provided by the home page, which
/// owns the liveness screen and the session list).
typedef RunWithSettings = Future<void> Function(DemoSettings settings);

class DeviceChecksPage extends StatelessWidget {
  const DeviceChecksPage({
    super.key,
    required this.log,
    required this.runWithSettings,
  });

  final DeviceCheckLog log;
  final RunWithSettings runWithSettings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device checks'),
        actions: [
          IconButton(
            tooltip: 'Copy report',
            icon: const Icon(Icons.copy_all),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: log.report()));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Report copied')));
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: log,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              'Each check sets up the test bench for you. Run it, then mark '
              'it passed or failed. Copy the report (top right) when done.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: log.deviceModel,
              decoration: const InputDecoration(
                labelText: 'Phone model (for the report)',
                hintText: 'e.g. Pixel 7, iPhone 13',
              ),
              onChanged: (v) => log.deviceModel = v.trim(),
            ),
            const SizedBox(height: 8),
            Text(
              'Passed ${log.count(CheckStatus.passed)} · '
              'failed ${log.count(CheckStatus.failed)} · '
              'not run ${log.count(CheckStatus.notRun)}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            for (final check in deviceChecks)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _StatusIcon(status: log.statusOf(check.id)),
                title: Text('${check.id}. ${check.title}'),
                subtitle: check.androidOnly
                    ? const Text('Android only')
                    : check.target == CheckTarget.fintech
                        ? const Text('Uses the branded fintech screen')
                        : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DeviceCheckPage(
                      check: check,
                      log: log,
                      runWithSettings: runWithSettings,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class DeviceCheckPage extends StatefulWidget {
  const DeviceCheckPage({
    super.key,
    required this.check,
    required this.log,
    required this.runWithSettings,
  });

  final DeviceCheck check;
  final DeviceCheckLog log;
  final RunWithSettings runWithSettings;

  @override
  State<DeviceCheckPage> createState() => _DeviceCheckPageState();
}

class _DeviceCheckPageState extends State<DeviceCheckPage> {
  late final _note =
      TextEditingController(text: widget.log.noteOf(widget.check.id));

  DeviceCheck get _c => widget.check;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    switch (_c.target) {
      case CheckTarget.testBench:
        await widget.runWithSettings(_c.settings!());
      case CheckTarget.fintech:
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => Theme(
              data: Brand.theme(),
              child: const FaceCaptureScreen(),
            ),
          ),
        );
    }
  }

  void _mark(CheckStatus status) {
    widget.log.record(_c.id, status, _note.text);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('Check ${_c.id}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_c.title, style: text.titleLarge),
          if (_c.androidOnly) ...[
            const SizedBox(height: 4),
            const Text('Android only — skip on iPhone.'),
          ],
          const SizedBox(height: 16),
          Text('Do this', style: text.titleMedium),
          for (final (i, step) in _c.steps.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${i + 1}. $step'),
            ),
          const SizedBox(height: 16),
          Text('Expected', style: text.titleMedium),
          for (final e in _c.expected)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check, size: 18, color: Colors.green),
                  const SizedBox(width: 6),
                  Expanded(child: Text(e)),
                ],
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _run,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Run this check'),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Note (what you saw, if it failed)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: () => _mark(CheckStatus.passed),
                  child: const Text('Passed'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => _mark(CheckStatus.failed),
                  child: const Text('Failed'),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: () => _mark(CheckStatus.skipped),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final CheckStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
        CheckStatus.passed =>
          const Icon(Icons.check_circle, color: Colors.green),
        CheckStatus.failed => const Icon(Icons.cancel, color: Colors.red),
        CheckStatus.skipped =>
          const Icon(Icons.remove_circle_outline, color: Colors.grey),
        CheckStatus.notRun =>
          const Icon(Icons.radio_button_unchecked, color: Colors.grey),
      };
}
