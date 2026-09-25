// Stand-ins for the server side and for platform attestation, so the
// security features can be exercised end to end without a backend.
//
// NONE OF THIS IS SECURE. A real app issues challenges and verifies results
// on its server, uses Play Integrity / App Attest for attestation, and a
// trained model for presentation-attack detection. See
// doc/server_verification.md in the package.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// An in-memory "backend" that issues and checks challenges.
class FakeChallengeServer {
  FakeChallengeServer._();
  static final instance = FakeChallengeServer._();

  final _random = Random.secure();
  final Map<String, _Issued> _issued = {};

  /// Picks [count] actions from [pool] (always including a motion action
  /// when the pool has one) and returns a single-use challenge.
  LivenessChallenge issue({
    required List<LivenessAction> pool,
    int count = 3,
    bool expired = false,
    Duration validFor = const Duration(minutes: 2),
  }) {
    final shuffled = List.of(pool)..shuffle(_random);
    final picked = shuffled.take(count.clamp(1, pool.length)).toList();
    const motion = {
      LivenessAction.blink,
      LivenessAction.nod,
      LivenessAction.openMouth,
      LivenessAction.drawCircleWithNose,
    };
    if (!picked.any(motion.contains)) {
      final m = shuffled.where(motion.contains);
      if (m.isNotEmpty) picked[_random.nextInt(picked.length)] = m.first;
    }
    final nonce = _hex(List.generate(16, (_) => _random.nextInt(256)));
    final expiresAt = expired
        ? DateTime.now().subtract(const Duration(seconds: 1))
        : DateTime.now().add(validFor);
    _issued[nonce] = _Issued(picked, expiresAt);
    return LivenessChallenge(
      nonce: nonce,
      actions: picked,
      expiresAt: expiresAt,
    );
  }

  /// What a real backend would check on upload (see the package's
  /// doc/server_verification.md). Marks the nonce as used.
  List<Check> verify(LivenessResult result) {
    // Round-trip through JSON, as the uploader's `metadata` field would.
    final meta =
        jsonDecode(jsonEncode(result.toJson())) as Map<String, dynamic>;
    final files = [...result.images, ...result.frameSequence]
        .map((i) => i.bytes)
        .toList();
    return [
      ..._checkChallenge(meta),
      _checkMedia(meta, files),
      _checkAttestation(meta),
    ];
  }

  List<Check> _checkChallenge(Map<String, dynamic> meta) {
    final nonce = meta['nonce'] as String?;
    if (nonce == null) {
      return const [
        Check('Server challenge', null, 'Not used for this session'),
      ];
    }
    final issued = _issued[nonce];
    if (issued == null) {
      return const [Check('Nonce', false, 'Never issued by this server')];
    }
    final checks = <Check>[];
    if (issued.used) {
      checks.add(const Check('Nonce', false, 'Already used (replay)'));
    } else if (DateTime.now().isAfter(issued.expiresAt) &&
        meta['success'] == true) {
      checks.add(const Check('Nonce', false, 'Expired by the server clock'));
    } else {
      checks.add(const Check('Nonce', true, 'Issued here, unused'));
    }
    issued.used = true;

    if (meta['success'] == true) {
      final done = (meta['completedActions'] as List).cast<String>();
      final expected = issued.actions.map((a) => a.name).toList();
      final same = done.length == expected.length &&
          List.generate(done.length, (i) => done[i] == expected[i])
              .every((ok) => ok);
      checks.add(Check(
        'Action order',
        same,
        same
            ? expected.join(' → ')
            : 'Expected ${expected.join(' → ')}, got ${done.join(' → ')}',
      ));
    }
    return checks;
  }

  Check _checkMedia(Map<String, dynamic> meta, List<Uint8List> files) {
    final listed = [
      for (final e in [...meta['images'] as List, ...meta['frames'] as List])
        (e as Map)['sha256'] as String,
    ]..sort();
    if (listed.isEmpty && files.isEmpty) {
      return const Check('Media hashes', null, 'No media captured');
    }
    final actual = files.map((b) => sha256.convert(b).toString()).toList()
      ..sort();
    final ok = listed.length == actual.length &&
        List.generate(listed.length, (i) => listed[i] == actual[i])
            .every((same) => same);
    return Check(
      'Media hashes',
      ok,
      ok
          ? '${files.length} file(s) match the metadata'
          : 'Uploaded files differ from the metadata',
    );
  }

  Check _checkAttestation(Map<String, dynamic> meta) {
    final token = meta['attestation'] as String?;
    final error = (meta['metadata'] as Map)['attestationError'] as String?;
    if (token == null) {
      return Check(
        'Attestation',
        error == null ? null : false,
        error ?? 'No attestor configured',
      );
    }
    // Rebuild the payload exactly as the guide describes.
    final hashes = [
      for (final e in [...meta['images'] as List, ...meta['frames'] as List])
        (e as Map)['sha256'] as String,
    ];
    final payload = [
      meta['sessionId'] as String,
      (meta['nonce'] as String?) ?? '',
      meta['success'] == true ? 'true' : 'false',
      (meta['completedActions'] as List).join(','),
      hashes.join(','),
    ].join('|');
    final expected = 'demo:${sha256.convert(utf8.encode(payload))}';
    final ok = token == expected;
    return Check(
      'Attestation (demo)',
      ok,
      ok ? 'Token signs the rebuilt payload' : 'Token does not match payload',
    );
  }
}

class _Issued {
  _Issued(this.actions, this.expiresAt);
  final List<LivenessAction> actions;
  final DateTime expiresAt;
  bool used = false;
}

/// One simulated server-side check: passed, failed, or not applicable.
class Check {
  const Check(this.name, this.passed, this.detail);
  final String name;
  final bool? passed;
  final String detail;
}

/// Fake attestation: "signs" the payload hash by echoing it. A real
/// attestor calls Play Integrity or App Attest.
class DemoAttestor extends LivenessAttestor {
  const DemoAttestor();

  @override
  Future<String> attest(Uint8List payloadHash) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return 'demo:${_hex(payloadHash)}';
  }
}

/// Fake presentation-attack detector with a fixed answer, to see how
/// analyzer scores flow into the metadata and confidence score. A real one
/// would run a model on `frame.jpeg` cropped to `frame.faceBox`.
class DemoPadAnalyzer extends LivenessFrameAnalyzer {
  const DemoPadAnalyzer({required this.score});

  final double score;

  @override
  String get id => 'demo-pad';

  @override
  Future<double?> analyze(LivenessFrame frame) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    // No face on this frame: can't judge it.
    return frame.faceBox == null ? null : score;
  }
}
