import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:liveness_flutter/liveness_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Liveness Example',
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
  // Pick your action sequence here. Order matters; shuffle for anti-replay.
  final List<LivenessAction> _actions = [
    LivenessAction.blink,
    LivenessAction.smile,
    LivenessAction.lookLeft,
    LivenessAction.lookRight,
    LivenessAction.nod,
  ];

  final Set<CaptureType> _capture = {CaptureType.images};
  bool _shuffle = false;
  bool _customUi = false;
  bool _debugOverlay = false;
  bool _flashChallenge = false;
  bool _assisted = false;

  // Optional: point this at your own API to test LivenessUploader.
  final TextEditingController _endpoint = TextEditingController();

  LivenessResult? _lastResult;

  Future<void> _start() async {
    final status = await Permission.camera.request();
    if (!status.isGranted || !mounted) return;

    final result = await Navigator.push<LivenessResult>(
      context,
      MaterialPageRoute(
        builder: (_) => LivenessScreen(
          actions: List.of(_actions),
          shuffle: _shuffle,
          capture: _capture,
          customUi: _customUi,
          debugOverlay: _debugOverlay,
          flashChallenge: _flashChallenge,
          assisted: _assisted,
          endpoint: _endpoint.text.trim(),
        ),
      ),
    );
    if (result != null) setState(() => _lastResult = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('liveness_flutter example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Actions (in order)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final action in LivenessAction.values)
                FilterChip(
                  label: Text(action.name),
                  selected: _actions.contains(action),
                  onSelected: (selected) => setState(() {
                    selected ? _actions.add(action) : _actions.remove(action);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _actions.isEmpty ? 'Select at least one action' : _actions.map((a) => a.name).join(' → '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(height: 32),
          Text('Capture', style: Theme.of(context).textTheme.titleMedium),
          CheckboxListTile(
            title: const Text('Per-action images'),
            value: _capture.contains(CaptureType.images),
            onChanged: (v) => setState(() => v!
                ? _capture.add(CaptureType.images)
                : _capture.remove(CaptureType.images)),
          ),
          CheckboxListTile(
            title: const Text('Session video (native recording)'),
            subtitle: const Text('Reliable on iOS; device-dependent on Android'),
            value: _capture.contains(CaptureType.video),
            onChanged: (v) => setState(() => v!
                ? _capture.add(CaptureType.video)
                : _capture.remove(CaptureType.video)),
          ),
          CheckboxListTile(
            title: const Text('Frame sequence (pseudo-video)'),
            subtitle: const Text('Steady JPEG frames; works on every device'),
            value: _capture.contains(CaptureType.frameSequence),
            onChanged: (v) => setState(() => v!
                ? _capture.add(CaptureType.frameSequence)
                : _capture.remove(CaptureType.frameSequence)),
          ),
          SwitchListTile(
            title: const Text('Shuffle action order'),
            subtitle: const Text('Recommended against replay attacks'),
            value: _shuffle,
            onChanged: (v) => setState(() => _shuffle = v),
          ),
          SwitchListTile(
            title: const Text('Assisted mode (back camera + torch)'),
            subtitle: const Text(
                'An operator points the phone at someone else and reads the '
                'instructions out loud — the subject can\'t see the screen. '
                'Flash challenge is skipped.'),
            value: _assisted,
            onChanged: (v) => setState(() => _assisted = v),
          ),
          SwitchListTile(
            title: const Text('Color-flash challenge'),
            subtitle: const Text(
                'Anti-replay: screen flashes random colors after the actions '
                'and checks the face reflects them. Works best indoors.'),
            value: _flashChallenge,
            onChanged: (v) => setState(() => _flashChallenge = v),
          ),
          SwitchListTile(
            title: const Text('Debug overlay'),
            subtitle: const Text(
                'Live yaw/pitch, eye & smile probabilities, brightness, '
                'replay-guard counters'),
            value: _debugOverlay,
            onChanged: (v) => setState(() => _debugOverlay = v),
          ),
          SwitchListTile(
            title: const Text('Custom UI'),
            subtitle: const Text(
                'Demo of overlayBuilder + instructionBuilder (rounded window, '
                'emoji instructions, step dots)'),
            value: _customUi,
            onChanged: (v) => setState(() => _customUi = v),
          ),
          const Divider(height: 32),
          TextField(
            controller: _endpoint,
            decoration: const InputDecoration(
              labelText: 'Upload endpoint (optional)',
              hintText: 'https://your-api.example.com/liveness',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _actions.isEmpty ? null : _start,
            icon: const Icon(Icons.face),
            label: const Text('Start liveness check'),
          ),
          if (_lastResult != null) ...[
            const Divider(height: 32),
            ResultCard(result: _lastResult!),
          ],
        ],
      ),
    );
  }
}

class LivenessScreen extends StatelessWidget {
  const LivenessScreen({
    super.key,
    required this.actions,
    required this.shuffle,
    required this.capture,
    required this.customUi,
    required this.debugOverlay,
    required this.flashChallenge,
    required this.assisted,
    required this.endpoint,
  });

  final List<LivenessAction> actions;
  final bool shuffle;
  final Set<CaptureType> capture;
  final bool customUi;
  final bool debugOverlay;
  final bool flashChallenge;
  final bool assisted;
  final String endpoint;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LivenessDetector(
        config: LivenessConfig(
          actions: actions,
          shuffleActions: shuffle,
          capture: capture,
          enableFlashChallenge: flashChallenge,
          cameraMode: assisted
              ? LivenessCameraMode.assisted
              : LivenessCameraMode.selfService,
        ),
        theme: const LivenessTheme(
          progressColor: Colors.tealAccent,
          ovalBorderColorActive: Colors.tealAccent,
        ),
        // When "Custom UI" is on, replace both the overlay and the
        // instruction area with our own widgets (see below).
        overlayBuilder: customUi ? _customOverlay : null,
        instructionBuilder: customUi ? _customInstructions : null,
        showDebugOverlay: debugOverlay,
        onActionCompleted: (action, index) =>
            debugPrint('Completed: ${action.name} ($index)'),
        onError: (e, st) => debugPrint('Liveness error: $e'),
        onResult: (result) async {
          // Full readable summary in the console on every session end.
          debugPrint(result.toString());

          if (endpoint.isNotEmpty && result.success && context.mounted) {
            // Uploading happens in YOUR code, so the loading UI is fully
            // yours. Here: a dialog with a progress bar driven by
            // HttpLivenessUploader.onProgress. Any transport works —
            // LivenessUploader.custom((r) async { ... }) wraps dio, S3, etc.
            await _uploadWithProgress(context, result, endpoint);
          }
          if (context.mounted) Navigator.pop(context, result);
        },
      ),
    );
  }
}

/// Uploads with a non-dismissible progress dialog. The progress bar is
/// driven by [HttpLivenessUploader.onProgress] via a [ValueNotifier].
Future<void> _uploadWithProgress(
  BuildContext context,
  LivenessResult result,
  String endpoint,
) async {
  final progress = ValueNotifier<double>(0);

  // Show the dialog; don't await it — the upload below controls when it
  // closes.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Uploading results…'),
            const SizedBox(height: 16),
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (_, value, __) => Column(
                children: [
                  LinearProgressIndicator(value: value == 0 ? null : value),
                  const SizedBox(height: 8),
                  Text('${(value * 100).toStringAsFixed(0)}%'),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  try {
    await HttpLivenessUploader(
      endpoint: Uri.parse(endpoint),
      onProgress: (sent, total) =>
          progress.value = total > 0 ? sent / total : 0,
      onResponse: (response) async =>
          debugPrint('Upload status: ${response.statusCode}'),
    ).upload(result);
  } catch (e) {
    debugPrint('Upload failed: $e');
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // close the dialog
    }
    progress.dispose();
  }
}

// ---------------------------------------------------------------------------
// Custom UI demo: everything below shows how to fully restyle the liveness
// screen with overlayBuilder + instructionBuilder.
// ---------------------------------------------------------------------------

Widget _customOverlay(BuildContext context, LivenessSessionState state) {
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

Widget _customInstructions(BuildContext context, LivenessSessionState state) {
  final text = switch (state.phase) {
    LivenessPhase.initializing => 'Warming up…',
    LivenessPhase.searchingFace => 'Show us your face 👀',
    LivenessPhase.centeringFace => 'A bit closer…',
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
    LivenessPhase.failed => 'Let\'s try that again',
  };

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
      // Step dots: green = done, white = current, faint = upcoming.
      Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(state.totalActions, (i) {
          final done = i < state.completedActions.length;
          final current = i == state.currentActionIndex &&
              state.phase == LivenessPhase.performingAction;
          return Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? Colors.greenAccent
                  : current
                      ? Colors.white
                      : Colors.white24,
            ),
          );
        }),
      ),
      if (state.remaining != null &&
          state.phase == LivenessPhase.performingAction)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('${state.remaining!.inSeconds}s',
              style: const TextStyle(color: Colors.white70)),
        ),
    ],
  );
}

/// Dimmed background with a rounded-rectangle window instead of the
/// default oval.
class _WindowPainter extends CustomPainter {
  _WindowPainter({required this.borderColor});

  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final window = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.42),
        width: size.width * 0.75,
        height: size.width * 0.95,
      ),
      const Radius.circular(32),
    );
    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(window)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha: 0.75));
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

class ImagePreviewPage extends StatelessWidget {
  const ImagePreviewPage({super.key, required this.image, required this.label});

  final CapturedImage image;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(label),
      ),
      body: Center(
        child: InteractiveViewer(child: Image.memory(image.bytes)),
      ),
    );
  }
}

class VideoPreviewPage extends StatefulWidget {
  const VideoPreviewPage({super.key, required this.path});

  final String path;

  @override
  State<VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends State<VideoPreviewPage> {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _controller.play();
          _controller.setLooping(true);
        }
      });
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
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Session video'),
      ),
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const CircularProgressIndicator(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() {
          _controller.value.isPlaying
              ? _controller.pause()
              : _controller.play();
        }),
        child: Icon(
          _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
        ),
      ),
    );
  }
}

/// Plays a captured frame sequence back at its real timing.
class FrameSequencePage extends StatefulWidget {
  const FrameSequencePage({super.key, required this.frames});

  final List<CapturedImage> frames;

  @override
  State<FrameSequencePage> createState() => _FrameSequencePageState();
}

class _FrameSequencePageState extends State<FrameSequencePage> {
  int _index = 0;
  bool _playing = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleNext();
  }

  void _scheduleNext() {
    if (!_playing || widget.frames.length < 2) return;
    final next = (_index + 1) % widget.frames.length;
    // Real inter-frame delay; loop restart uses the median-ish default.
    final delayMs = next == 0
        ? 500
        : (widget.frames[next].timestampMs - widget.frames[_index].timestampMs)
            .clamp(50, 1000);
    _timer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      setState(() => _index = next);
      _scheduleNext();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = widget.frames[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Frame ${_index + 1}/${widget.frames.length} '
            '· ${frame.timestampMs} ms'),
      ),
      body: Center(child: Image.memory(frame.bytes, gaplessPlayback: true)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() {
          _playing = !_playing;
          _timer?.cancel();
          if (_playing) _scheduleNext();
        }),
        child: Icon(_playing ? Icons.pause : Icons.play_arrow),
      ),
    );
  }
}

class ResultCard extends StatelessWidget {
  const ResultCard({super.key, required this.result});

  final LivenessResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  result.success ? Icons.verified : Icons.error,
                  color: result.success ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  result.success
                      ? 'Liveness passed'
                      : 'Failed: ${result.failureReason?.name}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Completed: '
                '${result.completedActions.map((a) => a.name).join(', ')}'),
            Text('Duration: ${result.duration.inMilliseconds} ms'),
            Text('Confidence: '
                '${(result.confidenceScore * 100).toStringAsFixed(0)}%'),
            Text('Session: ${result.sessionId}',
                style: Theme.of(context).textTheme.bodySmall),
            Text('Images captured: ${result.images.length}'),
            if (result.frameSequence.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.burst_mode),
                label: Text(
                    'Play frame sequence (${result.frameSequence.length})'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        FrameSequencePage(frames: result.frameSequence),
                  ),
                ),
              ),
            ],
            if (result.videoPath != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Play session video'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VideoPreviewPage(path: result.videoPath!),
                  ),
                ),
              ),
            ],
            if (result.images.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: result.images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final image = result.images[i];
                    final label = image.action?.name ?? 'reference';
                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ImagePreviewPage(image: image, label: label),
                        ),
                      ),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              image.bytes,
                              height: 72,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Text(
                            label,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
