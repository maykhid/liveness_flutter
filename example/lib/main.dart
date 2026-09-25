import 'dart:math';

import 'package:flutter/material.dart';
import 'package:liveness_flutter/liveness_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import 'src/demo_security.dart';
import 'src/demo_settings.dart';
import 'src/liveness_screen.dart';
import 'src/result_page.dart';

void main() => runApp(const ExampleApp());

final _messenger = GlobalKey<ScaffoldMessengerState>();

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Liveness Example',
      scaffoldMessengerKey: _messenger,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  DemoSettings _s = DemoSettings();
  final _endpoint = TextEditingController();
  final List<SessionRecord> _history = [];

  @override
  void dispose() {
    _endpoint.dispose();
    super.dispose();
  }

  void _applyPreset(DemoSettings preset, String name) {
    setState(() {
      preset
        ..endpoint = _s.endpoint
        ..uploadRetries = _s.uploadRetries;
      _s = preset;
    });
    _messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Preset: $name')));
  }

  Future<void> _start({bool brokenConfig = false}) async {
    if (_s.requestPermissionFirst) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        _messenger.currentState?.showSnackBar(const SnackBar(
          content: Text('Camera permission denied. Turn off "Ask for camera '
              'permission first" to see how the package handles it.'),
        ));
        return;
      }
    }
    if (!mounted) return;

    LivenessChallenge? challenge;
    if (_s.challenge != ChallengeMode.off && !brokenConfig) {
      // In a real app: an HTTP call to your backend.
      final pool =
          _s.actions.isEmpty ? LivenessAction.values : _s.actions;
      challenge = FakeChallengeServer.instance.issue(
        pool: pool,
        count: _s.randomCount == 0 ? min(3, pool.length) : _s.randomCount,
        expired: _s.challenge == ChallengeMode.expired,
      );
    }

    final settings = brokenConfig ? (DemoSettings()..actions = []) : _s;
    _s.endpoint = _endpoint.text.trim();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => LivenessScreen(
          settings: settings,
          challenge: challenge,
          onResult: _onSessionResult,
        ),
      ),
    );
  }

  /// Every session lands here — including results delivered after a system
  /// back, when the liveness screen no longer exists.
  void _onSessionResult(
    LivenessResult result,
    List<String> events,
    LivenessChallenge? challenge,
  ) {
    final record = SessionRecord(
      result: result,
      events: events,
      challenge: challenge,
      checks: FakeChallengeServer.instance.verify(result),
      settingsSummary: _s.summary,
    );
    if (!mounted) return;
    setState(() => _history.insert(0, record));
    _messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Session ended: ${record.headline}'),
        action: SnackBarAction(label: 'View', onPressed: () => _open(record)),
      ));
  }

  void _open(SessionRecord record) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultPage(
          record: record,
          endpoint: _endpoint.text.trim(),
          uploadRetries: _s.uploadRetries,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('liveness_flutter example')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('Presets', style: text.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            ActionChip(
              label: const Text('Quick test'),
              onPressed: () => _applyPreset(DemoSettings.quick(), 'Quick test'),
            ),
            ActionChip(
              label: const Text('Server-bound (KYC)'),
              onPressed: () => _applyPreset(DemoSettings.kyc(), 'KYC'),
            ),
            ActionChip(
              label: const Text('Everything on'),
              onPressed: () =>
                  _applyPreset(DemoSettings.everything(), 'Everything on'),
            ),
            ActionChip(
              label: const Text('Accessible'),
              onPressed: () =>
                  _applyPreset(DemoSettings.accessible(), 'Accessible'),
            ),
          ]),
          const SizedBox(height: 8),
          ..._sections(context),
          const SizedBox(height: 8),
          _HowToTest(onBrokenConfig: () => _start(brokenConfig: true)),
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Sessions', style: text.titleMedium),
            for (final r in _history)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  r.result.success ? Icons.verified : Icons.error_outline,
                  color: r.result.success ? Colors.green : Colors.red,
                ),
                title: Text(r.headline),
                subtitle: Text(
                  '${(r.result.confidenceScore * 100).toStringAsFixed(0)} % · '
                  '${r.result.completedActions.length} action(s) · '
                  '${r.checks.where((c) => c.passed == false).isEmpty ? 'checks OK' : 'checks FAILED'}'
                  '\n${r.settingsSummary}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(r),
              ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton.icon(
            onPressed: _s.actions.isEmpty && _s.challenge == ChallengeMode.off
                ? null
                : _start,
            icon: const Icon(Icons.face),
            label: const Text('Start liveness check'),
          ),
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context) {
    final s = _s;
    void set(VoidCallback f) => setState(f);

    return [
      _Group(
        title: 'Actions',
        initiallyExpanded: true,
        children: [
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final action in LivenessAction.values)
              FilterChip(
                label: Text(action.name),
                selected: s.actions.contains(action),
                onSelected: (on) => set(() {
                  on ? s.actions.add(action) : s.actions.remove(action);
                  if (s.randomCount > s.actions.length) {
                    s.randomCount = s.actions.length;
                  }
                }),
              ),
          ]),
          const SizedBox(height: 6),
          Text(
            s.actions.isEmpty
                ? 'Select at least one action'
                : s.actions.map((a) => a.name).join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (s.actions.isNotEmpty && !s.hasMotionAction)
            const _Warning(
              'No motion action (blink, nod, openMouth, drawCircleWithNose): '
              'pose-only actions can be faked with a photo.',
            ),
          SwitchListTile(
            title: const Text('Shuffle order'),
            value: s.shuffle,
            onChanged: (v) => set(() => s.shuffle = v),
          ),
          _Dropdown<int>(
            label: 'Random pick per session (randomActionCount)',
            value: s.randomCount,
            items: {
              0: 'Off (use all)',
              for (var n = 1; n <= s.actions.length; n++) n: '$n of ${s.actions.length}',
            },
            onChanged: (v) => set(() => s.randomCount = v),
          ),
        ],
      ),
      _Group(
        title: 'Timing',
        children: [
          _Slider(
            label: 'Action timeout',
            value: s.actionTimeoutS,
            min: 3,
            max: 60,
            unit: 's',
            onChanged: (v) => set(() => s.actionTimeoutS = v),
          ),
          _Dropdown<int>(
            label: 'Session timeout',
            value: s.sessionTimeoutS,
            items: const {0: 'Off', 20: '20 s', 60: '1 min', 120: '2 min', 300: '5 min'},
            onChanged: (v) => set(() => s.sessionTimeoutS = v),
          ),
          _Slider(
            label: 'Neutral-face timeout',
            value: s.neutralTimeoutS,
            min: 2,
            max: 30,
            unit: 's',
            onChanged: (v) => set(() => s.neutralTimeoutS = v),
          ),
          SwitchListTile(
            title: const Text('Require neutral face between actions'),
            value: s.requireNeutral,
            onChanged: (v) => set(() => s.requireNeutral = v),
          ),
          SwitchListTile(
            title: const Text('Fast blink sampling (~20 fps)'),
            subtitle: const Text('mlIntervalBlink 50 ms instead of 100 ms'),
            value: s.fastBlinkSampling,
            onChanged: (v) => set(() => s.fastBlinkSampling = v),
          ),
        ],
      ),
      _Group(
        title: 'Capture',
        children: [
          for (final (type, label, hint) in const [
            (CaptureType.images, 'Photos', 'Reference + one per action'),
            (CaptureType.frameSequence, 'Frame sequence',
                'Steady JPEGs, works on every device'),
            (CaptureType.video, 'Video',
                'Reliable on iOS; device-dependent on Android'),
          ])
            CheckboxListTile(
              title: Text(label),
              subtitle: Text(hint),
              value: s.capture.contains(type),
              onChanged: (v) =>
                  set(() => v! ? s.capture.add(type) : s.capture.remove(type)),
            ),
          SwitchListTile(
            title: const Text('Photo at the action\'s peak'),
            subtitle: const Text('Eyes shut for blink, lowest point of nod'),
            value: s.captureAtPeak,
            onChanged: (v) => set(() => s.captureAtPeak = v),
          ),
          _Dropdown<ResolutionPreset>(
            label: 'Camera resolution',
            value: s.resolution,
            items: {for (final r in ResolutionPreset.values) r: r.name},
            onChanged: (v) => set(() => s.resolution = v),
          ),
        ],
      ),
      _Group(
        title: 'Security & anti-spoof',
        children: [
          _Dropdown<ChallengeMode>(
            label: 'Server challenge (fake server)',
            value: s.challenge,
            items: {for (final m in ChallengeMode.values) m: m.label},
            onChanged: (v) => set(() => s.challenge = v),
          ),
          SwitchListTile(
            title: const Text('Attestation (demo attestor)'),
            subtitle: const Text('Signs the payload; checked on the result page'),
            value: s.attestor,
            onChanged: (v) => set(() => s.attestor = v),
          ),
          _Dropdown<PadMode>(
            label: 'Anti-spoof model (demo analyzer)',
            value: s.pad,
            items: {for (final m in PadMode.values) m: m.label},
            onChanged: (v) => set(() => s.pad = v),
          ),
          SwitchListTile(
            title: const Text('Colour-flash challenge'),
            subtitle: const Text('Best indoors; lowers confidence if failed'),
            value: s.flashChallenge,
            onChanged: (v) => set(() => s.flashChallenge = v),
          ),
          if (s.flashChallenge)
            _Dropdown<int>(
              label: 'Flash colours allowed to fail',
              value: s.flashAllowedMisses,
              items: const {0: '0 (strict)', 1: '1', 2: '2'},
              onChanged: (v) => set(() => s.flashAllowedMisses = v),
            ),
          SwitchListTile(
            title: const Text('Static-feed guard'),
            subtitle: const Text('Fails on frozen / injected camera feeds'),
            value: s.replayGuard,
            onChanged: (v) => set(() => s.replayGuard = v),
          ),
          SwitchListTile(
            title: const Text('Fail when the face changes'),
            subtitle: const Text('failOnFaceChange (off: lowers confidence)'),
            value: s.failOnFaceChange,
            onChanged: (v) => set(() => s.failOnFaceChange = v),
          ),
        ],
      ),
      _Group(
        title: 'Camera & detection',
        children: [
          SwitchListTile(
            title: const Text('Assisted mode (back camera + torch)'),
            subtitle: const Text('An operator films someone else and reads '
                'the instructions out loud. Flash is skipped.'),
            value: s.assisted,
            onChanged: (v) => set(() => s.assisted = v),
          ),
          SwitchListTile(
            title: const Text('mirrorYaw'),
            subtitle: const Text('Turn off if left/right are swapped'),
            value: s.mirrorYaw,
            onChanged: (v) => set(() => s.mirrorYaw = v),
          ),
          SwitchListTile(
            title: const Text('invertPitch'),
            subtitle: const Text('Turn on if up/down or nod are inverted'),
            value: s.invertPitch,
            onChanged: (v) => set(() => s.invertPitch = v),
          ),
          SwitchListTile(
            title: const Text('Debug overlay'),
            subtitle: const Text('Live angles, probabilities, light, and a '
                'green box where the detector sees your face'),
            value: s.debugOverlay,
            onChanged: (v) => set(() => s.debugOverlay = v),
          ),
        ],
      ),
      _Group(
        title: 'Look & feel',
        children: [
          _Dropdown<TargetShape>(
            label: 'Target shape (also the detection zone)',
            value: s.ovalShape,
            items: {for (final t in TargetShape.values) t: t.name},
            onChanged: (v) => set(() => s.ovalShape = v),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Target size: ${s.ovalSize.toStringAsFixed(2)}'),
            subtitle: Slider(
              value: s.ovalSize,
              min: 0.4,
              max: 0.95,
              onChanged: (v) => set(() => s.ovalSize = v),
            ),
          ),
          SwitchListTile(
            title: const Text('Custom UI'),
            subtitle: const Text('overlayBuilder + instructionBuilder, with '
                'targetRegion so the window drives detection'),
            value: s.customUi,
            onChanged: (v) => set(() => s.customUi = v),
          ),
          SwitchListTile(
            title: const Text('Light theme'),
            subtitle: const Text('Light scrim, dark text and close icon'),
            value: s.lightTheme,
            onChanged: (v) => set(() => s.lightTheme = v),
          ),
          SwitchListTile(
            title: const Text('French (partial)'),
            subtitle: const Text('Untranslated entries fall back to English'),
            value: s.french,
            onChanged: (v) => set(() => s.french = v),
          ),
          SwitchListTile(
            title: const Text('Haptics'),
            value: s.haptics,
            onChanged: (v) => set(() => s.haptics = v),
          ),
          SwitchListTile(
            title: const Text('On-screen event log'),
            value: s.showEventLog,
            onChanged: (v) => set(() => s.showEventLog = v),
          ),
          SwitchListTile(
            title: const Text('External controls (LivenessController)'),
            subtitle: const Text('Hide the close button; cancel / restart and '
                'live state from a bar of our own'),
            value: s.externalControls,
            onChanged: (v) => set(() => s.externalControls = v),
          ),
        ],
      ),
      _Group(
        title: 'Permissions',
        children: [
          SwitchListTile(
            title: const Text('Ask for camera permission first'),
            subtitle: const Text('Off: let the package report '
                'permissionDenied itself'),
            value: s.requestPermissionFirst,
            onChanged: (v) => set(() => s.requestPermissionFirst = v),
          ),
          SwitchListTile(
            title: const Text('In-screen "permission denied" page'),
            subtitle: const Text('permissionDeniedBuilder with Settings + '
                'Try again'),
            value: s.permissionScreen,
            onChanged: (v) => set(() => s.permissionScreen = v),
          ),
        ],
      ),
      _Group(
        title: 'Upload',
        children: [
          TextField(
            controller: _endpoint,
            decoration: const InputDecoration(
              labelText: 'Endpoint (optional)',
              hintText: 'https://webhook.site/…',
              border: OutlineInputBorder(),
            ),
          ),
          _Dropdown<int>(
            label: 'Retries on network error / 5xx',
            value: s.uploadRetries,
            items: const {0: '0', 1: '1', 2: '2', 3: '3'},
            onChanged: (v) => set(() => s.uploadRetries = v),
          ),
        ],
      ),
    ];
  }
}

/// Short checklist of things worth trying on a device.
class _HowToTest extends StatelessWidget {
  const _HowToTest({required this.onBrokenConfig});

  final VoidCallback onBrokenConfig;

  @override
  Widget build(BuildContext context) {
    const tips = [
      'Press system back mid-session: a "cancelled (dispose)" result still '
          'arrives.',
      'Cover the camera or leave the frame: the session ends by itself '
          '(faceLost / sessionTimeout), it never hangs.',
      'Hold a head turn after lookLeft: fails after the neutral timeout.',
      'Have someone walk past in the background: small or brief faces are '
          'ignored.',
      'Blink quickly: fast blinks should register.',
      'Debug overlay on: the green box should sit on your face, and '
          '"in position" should match the oval (try other shapes/sizes).',
      'iPhone: nod and look up/down. If inverted, turn on invertPitch.',
      'KYC preset: the result page shows the simulated server checks.',
      'Deny camera access in Settings: you get permissionDenied, not a '
          'generic error.',
    ];
    return Card(
      child: ExpansionTile(
        title: const Text('What to test'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final t in tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• $t'),
            ),
          TextButton(
            onPressed: onBrokenConfig,
            child: const Text('Start with an invalid config (empty actions)'),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
  });

  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(title),
      initiallyExpanded: initiallyExpanded,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: DropdownButton<T>(
        value: items.containsKey(value) ? value : items.keys.first,
        items: [
          for (final e in items.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final String unit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('$label: $value $unit'),
      subtitle: Slider(
        value: value.toDouble(),
        min: min.toDouble(),
        max: max.toDouble(),
        divisions: max - min,
        onChanged: (v) => onChanged(v.round()),
      ),
    );
  }
}
