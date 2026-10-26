// Keeps the agent skills in skills/ honest: valid SKILL.md front matter,
// working links, Dart examples that pass the analyzer against this
// package, a server test vector that matches LivenessResult, and an
// installer that copies them.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

import '../bin/skills.dart';

final _root = Directory.current;
final _skillsDir = Directory('${_root.path}/skills');

List<Directory> _skills() =>
    _skillsDir
        .listSync()
        .whereType<Directory>()
        .where((d) => File('${d.path}/SKILL.md').existsSync())
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

List<File> _markdown() =>
    _skillsDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

String _name(FileSystemEntity e) =>
    e.uri.pathSegments.lastWhere((s) => s.isNotEmpty);

/// The YAML front matter of a SKILL.md, flattened to `key: value` pairs
/// (nested keys as `parent.child`). Enough for the simple front matter
/// the skills use.
Map<String, String> _frontMatter(String text) {
  final match = RegExp(r'^---\n(.*?)\n---\n', dotAll: true).firstMatch(text);
  if (match == null) return {};
  final fields = <String, String>{};
  String? parent;
  for (final line in match.group(1)!.split('\n')) {
    final nested = RegExp(r'^  ([\w-]+):\s*(.*)$').firstMatch(line);
    final top = RegExp(r'^([\w-]+):\s*(.*)$').firstMatch(line);
    if (nested != null && parent != null) {
      fields['$parent.${nested.group(1)}'] = _unquote(nested.group(2)!);
    } else if (top != null) {
      parent = top.group(1);
      fields[parent!] = _unquote(top.group(2)!);
    }
  }
  return fields;
}

String _unquote(String value) =>
    value.length >= 2 && value.startsWith('"') && value.endsWith('"')
    ? value.substring(1, value.length - 1)
    : value;

/// The release the skills describe: pubspec's version, or the newest
/// CHANGELOG heading while a release is being prepared.
Set<String> _documentedVersions() {
  final pubspec = File('${_root.path}/pubspec.yaml').readAsStringSync();
  final changelog = File('${_root.path}/CHANGELOG.md').readAsStringSync();
  return {
    RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!,
    RegExp(r'^# (\S+)', multiLine: true).firstMatch(changelog)!.group(1)!,
  };
}

void main() {
  test('there are skills to check', () {
    expect(_skills().map(_name), contains('liveness-flutter'));
    expect(_skills().map(_name), contains('liveness-flutter-server'));
  });

  group('SKILL.md front matter', () {
    for (final skill in _skills()) {
      test(_name(skill), () {
        final text = File('${skill.path}/SKILL.md').readAsStringSync();
        final fields = _frontMatter(text);
        final name = fields['name'] ?? '';
        final description = fields['description'] ?? '';

        expect(name, _name(skill), reason: 'name must match the folder');
        expect(name, matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')));
        expect(name.length, lessThanOrEqualTo(64));
        expect(description, isNotEmpty);
        expect(description.length, lessThanOrEqualTo(1024));
        expect(description, isNot(matches(RegExp('[<>]'))));
        expect(
          _documentedVersions(),
          contains(fields['metadata.written-for']),
          reason:
              'metadata.written-for should be the version the skill '
              'describes',
        );
        expect(
          text.split('\n').length,
          lessThan(500),
          reason: 'keep SKILL.md short; move detail to references/',
        );
      });
    }
  });

  test('relative links point at files inside the same skill', () {
    final broken = <String>[];
    for (final file in _markdown()) {
      final text = file.readAsStringSync();
      for (final match in RegExp(r'\]\(([^)\s]+)\)').allMatches(text)) {
        final target = match.group(1)!.split('#').first;
        if (target.isEmpty || target.contains('://')) continue;
        final resolved = File.fromUri(file.uri.resolve(target));
        final skill = _skills().firstWhere((s) => file.path.startsWith(s.path));
        if (!resolved.existsSync() ||
            !resolved.absolute.path.startsWith(skill.absolute.path)) {
          broken.add('${file.path}: $target');
        }
      }
    }
    expect(broken, isEmpty);
  });

  test('Dart examples pass the analyzer', () async {
    final temp = Directory.systemTemp.createTempSync('skill_snippets_');
    addTearDown(() => temp.deleteSync(recursive: true));

    // Resolve packages exactly as this package does, without a pub get.
    final config = File(
      '${_root.path}/.dart_tool/package_config.json',
    ).absolute;
    final json = jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
    for (final package in json['packages'] as List<Object?>) {
      package as Map<String, Object?>;
      package['rootUri'] = config.uri
          .resolve(package['rootUri'] as String)
          .toString();
    }
    Directory('${temp.path}/.dart_tool').createSync();
    File(
      '${temp.path}/.dart_tool/package_config.json',
    ).writeAsStringSync(jsonEncode(json));
    File('${temp.path}/pubspec.yaml').writeAsStringSync('''
name: skill_snippets
publish_to: none
environment:
  sdk: ">=3.10.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
  http: any
  liveness_flutter: any
''');
    File(
      '${temp.path}/analysis_options.yaml',
    ).writeAsStringSync('include: package:flutter_lints/flutter.yaml\n');

    // Snippet file name -> (markdown file, line of the snippet's first line).
    final sources = <String, (String, int)>{};
    for (final file in _markdown()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trim() != '```dart') continue;
        final start = i + 1;
        final body = <String>[];
        while (++i < lines.length && lines[i].trim() != '```') {
          body.add(lines[i]);
        }
        final id = 'snippet_${sources.length}';
        sources[id] = (file.path.substring(_root.path.length + 1), start + 1);
        File('${temp.path}/lib/$id.dart')
          ..createSync(recursive: true)
          ..writeAsStringSync('${body.join('\n')}\n');
      }
    }
    expect(sources, isNotEmpty);

    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    final dart = flutterRoot == null ? 'dart' : '$flutterRoot/bin/dart';
    final result = await Process.run(dart, [
      'analyze',
      '--fatal-infos',
      '.',
    ], workingDirectory: temp.path);
    // Point each issue at the markdown line it comes from.
    final output = '${result.stdout}${result.stderr}'.replaceAllMapped(
      RegExp(r'lib/(snippet_\d+)\.dart:(\d+)'),
      (m) {
        final (file, line) = sources[m[1]]!;
        return '$file:${line + int.parse(m[2]!) - 1}';
      },
    );
    expect(result.exitCode, 0, reason: output);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('the reference verifier passes its self-test', () async {
    final python = Platform.isWindows ? 'python' : 'python3';
    final ProcessResult result;
    try {
      result = await Process.run(python, [
        '-I', '-B', // isolated, and no __pycache__ in the skill folder
        '${_skillsDir.path}/liveness-flutter-server/references/verifier.py',
      ]);
    } on ProcessException {
      markTestSkipped('$python is not installed');
      return;
    }
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  });

  test('the server test vector matches LivenessResult', () {
    Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));
    final result = LivenessResult(
      success: true,
      completedActions: const [LivenessAction.blink, LivenessAction.lookLeft],
      images: [
        CapturedImage(
          bytes: bytes('reference-photo'),
          action: null,
          timestampMs: 420,
          kind: CaptureKind.reference,
        ),
        CapturedImage(
          bytes: bytes('blink-peak-photo'),
          action: LivenessAction.blink,
          timestampMs: 1310,
          kind: CaptureKind.peak,
        ),
        CapturedImage(
          bytes: bytes('lookLeft-peak-photo'),
          action: LivenessAction.lookLeft,
          timestampMs: 2875,
          kind: CaptureKind.peak,
        ),
      ],
      frameSequence: [
        CapturedImage(
          bytes: bytes('frame-0'),
          action: null,
          timestampMs: 125,
          kind: CaptureKind.sequence,
        ),
      ],
      startedAt: DateTime.utc(2026, 10, 26, 12),
      finishedAt: DateTime.utc(2026, 10, 26, 12, 0, 4, 250),
      confidenceScore: 0.97,
      sessionId: 'LV-0192C3D4E5F6-0A1B2C3D',
      nonce: '9f2c4e6a8b0d1f3e5a7c9e1b3d5f7a9c',
      metadata: const {
        'blink_ms': 890,
        'lookLeft_ms': 1240,
        'cameraMode': 'selfService',
      },
    );
    final hash = result.attestationPayloadHash
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    final server = '${_skillsDir.path}/liveness-flutter-server';
    final skill = File('$server/SKILL.md').readAsStringSync();
    expect(skill, contains(result.attestationPayload));
    expect(skill, contains(hash));
    expect(
      File('$server/references/verifier.py').readAsStringSync(),
      contains(hash),
    );

    final protocol = File('$server/references/protocol.md').readAsStringSync();
    final sample = RegExp(
      r'```json\n(.*?)```',
      dotAll: true,
    ).firstMatch(protocol)!.group(1)!;
    expect(jsonDecode(sample), jsonDecode(result.evidenceJson));
    // The exact bytes a server hashes, so they have to match to the byte.
    expect(protocol, contains(result.evidenceJson));
  });

  group('installer', () {
    late Directory project;
    late StringBuffer out;
    late StringBuffer err;

    setUp(() {
      project = Directory.systemTemp.createTempSync('skills_install_');
      out = StringBuffer();
      err = StringBuffer();
    });
    tearDown(() => project.deleteSync(recursive: true));

    Future<int> run(List<String> args) => runSkills(
      args,
      project: project,
      packageRoot: _root,
      out: out,
      err: err,
    );

    test('installs into .agents/skills when no agent is detected', () async {
      expect(await run([]), 0, reason: '$err');
      for (final skill in _skills()) {
        final copy = File(
          '${project.path}/.agents/skills/${_name(skill)}/'
          'SKILL.md',
        );
        expect(
          copy.readAsStringSync(),
          File('${skill.path}/SKILL.md').readAsStringSync(),
        );
      }
    });

    test(
      'installs where detected agents look, and replaces old copies',
      () async {
        Directory('${project.path}/.cursor').createSync();
        File('${project.path}/AGENTS.md').writeAsStringSync('');
        final stale = File(
          '${project.path}/.cursor/skills/liveness-flutter/'
          'old.md',
        )..createSync(recursive: true);

        expect(await run([]), 0, reason: '$err');
        expect(stale.existsSync(), isFalse);
        expect(
          File(
            '${project.path}/.cursor/skills/liveness-flutter/SKILL.md',
          ).existsSync(),
          isTrue,
        );
        expect(
          File(
            '${project.path}/.agents/skills/liveness-flutter/references/'
            'setup.md',
          ).existsSync(),
          isTrue,
        );
        expect('$out', contains('Updated liveness-flutter in .cursor/skills'));
        expect('$out', contains('Installed into 2 folders'));
      },
    );

    test('--agent, --dir and --skill choose what goes where', () async {
      expect(
        await run([
          '--agent', 'gemini', //
          '--dir', 'tools/skills',
          '--skill', 'liveness-flutter-server',
        ]),
        0,
        reason: '$err',
      );
      for (final dir in ['.gemini/skills', 'tools/skills']) {
        expect(
          Directory(
            '${project.path}/$dir/liveness-flutter-server',
          ).existsSync(),
          isTrue,
        );
        expect(
          Directory('${project.path}/$dir/liveness-flutter').existsSync(),
          isFalse,
        );
      }
    });

    test('leaves out OS and tool leftovers', () async {
      final package = Directory.systemTemp.createTempSync('skills_package_');
      addTearDown(() => package.deleteSync(recursive: true));
      final skill = '${package.path}/skills/demo';
      for (final file in ['SKILL.md', 'references/a.md', '.DS_Store']) {
        File('$skill/$file').createSync(recursive: true);
      }
      File('$skill/references/__pycache__/a.pyc').createSync(recursive: true);

      final code = await runSkills(
        [],
        project: project,
        packageRoot: package,
        out: out,
        err: err,
      );
      expect(code, 0, reason: '$err');
      final installed =
          Directory('${project.path}/.agents/skills/demo')
              .listSync(recursive: true)
              .map((e) => e.path.substring(project.path.length))
              .toList()
            ..sort();
      expect(installed, [
        '/.agents/skills/demo/SKILL.md',
        '/.agents/skills/demo/references',
        '/.agents/skills/demo/references/a.md',
      ]);
    });

    test('--list prints the skills', () async {
      expect(await run(['--list']), 0);
      expect('$out'.trim().split('\n'), [
        'liveness-flutter',
        'liveness-flutter-server',
      ]);
    });

    test('rejects unknown options, agents and skills', () async {
      expect(await run(['--nope']), 64);
      expect(await run(['--agent', 'nope']), 64);
      expect(await run(['--skill', 'nope']), 64);
      expect(await run(['--dir']), 64);
      expect(project.listSync(), isEmpty);
    });
  });
}
