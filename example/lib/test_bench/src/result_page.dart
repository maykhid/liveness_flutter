import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

import 'insecure_fakes.dart';
import 'media_pages.dart';

/// Everything the demo keeps about one finished session.
class SessionRecord {
  SessionRecord({
    required this.result,
    required this.events,
    required this.checks,
    required this.settingsSummary,
    this.challenge,
  }) : receivedAt = DateTime.now();

  final LivenessResult result;
  final List<String> events;

  /// The simulated server's verdict, computed once when the result arrived
  /// (verification marks the nonce as used).
  final List<Check> checks;
  final String settingsSummary;
  final LivenessChallenge? challenge;
  final DateTime receivedAt;

  String get headline {
    final r = result;
    if (r.success) return 'Passed';
    final by = r.metadata['cancelledBy'];
    return 'Failed: ${r.failureReason?.name}${by == null ? '' : ' ($by)'}';
  }
}

class ResultPage extends StatelessWidget {
  const ResultPage({
    super.key,
    required this.record,
    required this.endpoint,
    required this.uploadRetries,
  });

  final SessionRecord record;
  final String endpoint;
  final int uploadRetries;

  LivenessResult get _r => record.result;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final meta = _r.metadata;
    return Scaffold(
      appBar: AppBar(
        title: Text(record.headline),
        actions: [
          IconButton(
            tooltip: 'Copy JSON',
            icon: const Icon(Icons.copy),
            onPressed: () => _copyJson(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _OutcomeCard(record: record),
          const SizedBox(height: 12),
          _Section(
            title: 'Server-side checks (simulated)',
            subtitle: 'What a backend should verify before trusting this '
                'result — see doc/server_verification.md',
            children: [
              for (final c in record.checks) _CheckTile(check: c),
            ],
          ),
          _Section(
            title: 'Anti-spoof signals',
            subtitle: 'Soft signals that lowered (or would lower) the '
                'confidence score',
            children: [
              _kv('Flash challenge', meta['flashChallenge'] ?? 'off'),
              if (meta['flashChallengeOrder'] != null)
                _kv('Flash order', (meta['flashChallengeOrder'] as List).join(' → ')),
              for (final e in meta.entries.where((e) =>
                  e.key.startsWith('confidence_') ||
                  e.key.startsWith('identity_')))
                _kv(e.key, e.value),
              if (meta['analyzers'] != null)
                for (final a in (meta['analyzers'] as Map).entries)
                  _kv('analyzer ${a.key}',
                      'mean ${(a.value as Map)['mean']} · errors ${(a.value as Map)['errors']}'),
            ],
          ),
          _Section(
            title: 'Media',
            children: [
              if (_r.images.isEmpty &&
                  _r.frameSequence.isEmpty &&
                  _r.videoPath == null)
                const Text('Nothing captured (capture is empty).'),
              if (_r.images.isNotEmpty) _ImageStrip(images: _r.images),
              if (_r.frameSequence.isNotEmpty)
                OutlinedButton.icon(
                  icon: const Icon(Icons.burst_mode),
                  label: Text(
                      'Play frame sequence (${_r.frameSequence.length})'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          FrameSequencePage(frames: _r.frameSequence),
                    ),
                  ),
                ),
              if (_r.videoPath != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Play session video'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VideoPreviewPage(path: _r.videoPath!),
                    ),
                  ),
                ),
              if (meta['videoUnavailable'] == true)
                const Text('Video was unavailable on this device '
                    '(metadata.videoUnavailable).'),
            ],
          ),
          _Section(
            title: 'Event log',
            subtitle: 'Callbacks as they fired (onActionStarted, '
                'onActionCompleted, onFeedback, onError, onResult)',
            children: [
              SelectableText(
                record.events.isEmpty ? '—' : record.events.join('\n'),
                style: text.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ],
          ),
          _Section(
            title: 'Raw result (toJson)',
            initiallyExpanded: false,
            children: [
              SelectableText(
                const JsonEncoder.withIndent('  ').convert(_r.toJson()),
                style: text.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Text(endpoint.isEmpty
                ? 'Upload (set an endpoint on the home screen)'
                : 'Upload to $endpoint'),
            onPressed:
                endpoint.isEmpty ? null : () => _upload(context),
          ),
        ],
      ),
    );
  }

  void _copyJson(BuildContext context) {
    Clipboard.setData(ClipboardData(
      text: const JsonEncoder.withIndent('  ').convert(_r.toJson()),
    ));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Result JSON copied')));
  }

  /// Uploads with a progress dialog, then reports the outcome, including
  /// HTTP errors (LivenessUploadException) and timeouts.
  Future<void> _upload(BuildContext context) async {
    final progress = ValueNotifier<double>(0);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, value, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Uploading…'),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: value == 0 ? null : value),
                const SizedBox(height: 8),
                Text('${(value * 100).toStringAsFixed(0)}%'),
              ],
            ),
          ),
        ),
      ),
    );

    String message;
    try {
      var status = 0;
      await HttpLivenessUploader(
        endpoint: Uri.parse(endpoint),
        maxRetries: uploadRetries,
        timeout: const Duration(seconds: 30),
        onProgress: (sent, total) =>
            progress.value = total > 0 ? sent / total : 0,
        onResponse: (r) async => status = r.statusCode,
      ).upload(_r);
      message = 'Uploaded (HTTP $status)';
    } on LivenessUploadException catch (e) {
      message = 'Server said HTTP ${e.statusCode}'
          '${e.body.isEmpty ? '' : ': ${e.body}'}';
    } catch (e) {
      message = 'Upload failed: $e';
    } finally {
      navigator.pop();
      progress.dispose();
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

class _OutcomeCard extends StatelessWidget {
  const _OutcomeCard({required this.record});

  final SessionRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record.result;
    final plan = record.challenge?.actions;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(
                r.success ? Icons.verified : Icons.error_outline,
                color: r.success ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  r.success
                      ? 'Liveness passed'
                      : const LivenessStrings().failureFor(r.failureReason),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            _kv('Confidence', '${(r.confidenceScore * 100).toStringAsFixed(1)} %'),
            _kv('Completed', r.completedActions.map((a) => a.name).join(' → ')),
            if (plan != null)
              _kv('Challenge asked', plan.map((a) => a.name).join(' → ')),
            _kv('Duration', '${r.duration.inMilliseconds} ms'),
            _kv('Session ID', r.sessionId),
            if (r.nonce != null) _kv('Nonce', r.nonce),
            if (r.attestation != null) _kv('Attestation', r.attestation),
            if (r.metadata['cancelledBy'] != null)
              _kv('Cancelled by', r.metadata['cancelledBy']),
            if (r.metadata['timeoutPhase'] != null)
              _kv('Timed out in', r.metadata['timeoutPhase']),
            if (r.metadata['configError'] != null)
              _kv('Config error', r.metadata['configError']),
            _kv('Settings', record.settingsSummary),
          ],
        ),
      ),
    );
  }
}

class _ImageStrip extends StatelessWidget {
  const _ImageStrip({required this.images});

  final List<CapturedImage> images;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final image = images[i];
          final label = image.action == null
              ? 'reference'
              : '${image.action!.name} · ${image.kind.name}';
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ImagePreviewPage(
                  image: image,
                  label: '$label · ${image.timestampMs} ms',
                ),
              ),
            ),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(image.bytes, height: 88, fit: BoxFit.cover),
                ),
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                Text('${image.timestampMs} ms',
                    style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({required this.check});

  final Check check;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (check.passed) {
      true => (Icons.check_circle, Colors.green),
      false => (Icons.cancel, Colors.red),
      null => (Icons.remove_circle_outline, Colors.grey),
    };
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(check.name),
      subtitle: Text(check.detail),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.subtitle,
    this.initiallyExpanded = true,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      initiallyExpanded: initiallyExpanded,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

Widget _kv(String key, Object? value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(key, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(child: SelectableText('$value')),
        ],
      ),
    );
