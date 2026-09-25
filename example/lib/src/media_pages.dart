import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:liveness_flutter/liveness_flutter.dart';
import 'package:video_player/video_player.dart';

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
