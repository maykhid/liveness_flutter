// Copies the agent skills that ship with liveness_flutter into the current
// project, where AI coding agents that read SKILL.md files will find them.
//
//   dart run liveness_flutter:skills [options]
//
// Run it from the app's root. Re-run it after upgrading liveness_flutter so
// the skills match the installed version.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// Where each agent looks for project skills, relative to the project root.
const agentSkillDirs = <String, String>{
  'agents': '.agents/skills',
  'claude': '.claude/skills',
  'copilot': '.github/skills',
  'cursor': '.cursor/skills',
  'gemini': '.gemini/skills',
};

/// Files or folders whose presence suggests the project uses an agent.
const _agentMarkers = <String, List<String>>{
  'agents': ['.agents', 'AGENTS.md'],
  'claude': ['.claude', 'CLAUDE.md'],
  'copilot': ['.github/skills', '.github/copilot-instructions.md'],
  'cursor': ['.cursor'],
  'gemini': ['.gemini', 'GEMINI.md'],
};

const _usage = '''
Copies the liveness_flutter agent skills into this project.

Usage: dart run liveness_flutter:skills [options]

Options:
  --agent <name>   Install where this agent looks. One of: agents, claude,
                   copilot, cursor, gemini, all. Repeatable.
  --dir <path>     Install into this skills folder instead. Repeatable.
  --skill <name>   Install only this skill. Repeatable.
  --list           List the skills in the installed package and exit.
  -h, --help       Show this help.

With no --agent or --dir, the skills go wherever an agent's files already
exist in the project (.claude, .cursor, .gemini, .agents, AGENTS.md, ...),
or into .agents/skills if there are none. Existing copies of these skills
are replaced.''';

Future<void> main(List<String> args) async {
  exitCode = await runSkills(args, project: Directory.current);
}

/// The installer, minus process concerns, so tests can drive it.
///
/// [packageRoot] defaults to the installed liveness_flutter package.
/// Returns the exit code.
Future<int> runSkills(
  List<String> args, {
  required Directory project,
  Directory? packageRoot,
  StringSink? out,
  StringSink? err,
}) async {
  out ??= stdout;
  err ??= stderr;

  final agents = <String>[];
  final dirs = <String>[];
  final only = <String>[];
  var list = false;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    String value() {
      if (i + 1 >= args.length) throw FormatException('$arg needs a value');
      return args[++i];
    }

    try {
      switch (arg) {
        case '-h' || '--help':
          out.writeln(_usage);
          return 0;
        case '--list':
          list = true;
        case '--agent':
          agents.addAll(value().split(','));
        case '--dir':
          dirs.add(value());
        case '--skill':
          only.add(value());
        default:
          throw FormatException('Unknown option: $arg');
      }
    } on FormatException catch (e) {
      err
        ..writeln(e.message)
        ..writeln()
        ..writeln(_usage);
      return 64;
    }
  }

  for (final agent in agents) {
    if (agent != 'all' && !agentSkillDirs.containsKey(agent)) {
      err.writeln(
        'Unknown agent "$agent". '
        'Use one of: ${[...agentSkillDirs.keys, 'all'].join(', ')}.',
      );
      return 64;
    }
  }

  final root = packageRoot ?? await findPackageRoot(project);
  if (root == null) {
    err.writeln(
      'Could not find the liveness_flutter package. Run this from '
      'the root of a project that depends on it, after `flutter pub get`.',
    );
    return 1;
  }
  final available = listSkills(root);
  if (available.isEmpty) {
    err.writeln('No skills found in ${root.path}/skills.');
    return 1;
  }

  if (list) {
    for (final skill in available.keys) {
      out.writeln(skill);
    }
    return 0;
  }

  for (final name in only) {
    if (!available.containsKey(name)) {
      err.writeln(
        'Unknown skill "$name". '
        'Available: ${available.keys.join(', ')}.',
      );
      return 64;
    }
  }
  final skills = only.isEmpty ? available.keys.toList() : only;

  if (!File('${project.path}/pubspec.yaml').existsSync()) {
    out.writeln(
      'Note: no pubspec.yaml here. The skills are installed '
      'relative to ${project.path}.',
    );
  }

  final targets = <String>{
    ...dirs,
    for (final agent in agents.contains('all') ? agentSkillDirs.keys : agents)
      agentSkillDirs[agent]!,
  };
  if (targets.isEmpty) targets.addAll(detectSkillDirs(project));

  for (final target in targets) {
    final base = Directory(
      _isAbsolute(target) ? target : '${project.path}/$target',
    );
    for (final skill in skills) {
      final destination = Directory('${base.path}/$skill');
      final replaced = destination.existsSync();
      if (replaced) destination.deleteSync(recursive: true);
      _copyDirectory(available[skill]!, destination);
      out.writeln('${replaced ? 'Updated' : 'Installed'} $skill in $target');
    }
  }

  out
    ..writeln()
    ..writeln(
      'Re-run this after upgrading liveness_flutter to keep the '
      'skills in step with the package.',
    );
  if (skills.contains('liveness-flutter-server')) {
    out.writeln(
      'If your backend lives in another repository, copy '
      'liveness-flutter-server there too.',
    );
  }
  return 0;
}

/// The skills folders to use when none were asked for: one per agent that
/// the project already has files for, or the shared `.agents/skills`.
List<String> detectSkillDirs(Directory project) {
  final found = [
    for (final MapEntry(key: agent, value: markers) in _agentMarkers.entries)
      if (markers.any(
        (m) =>
            FileSystemEntity.typeSync('${project.path}/$m') !=
            FileSystemEntityType.notFound,
      ))
        agentSkillDirs[agent]!,
  ];
  return found.isEmpty ? [agentSkillDirs['agents']!] : found;
}

/// Each folder in `<packageRoot>/skills` that has a SKILL.md, by name.
Map<String, Directory> listSkills(Directory packageRoot) {
  final skillsDir = Directory('${packageRoot.path}/skills');
  if (!skillsDir.existsSync()) return {};
  final skills = <String, Directory>{};
  for (final entity in skillsDir.listSync()) {
    if (entity is Directory && File('${entity.path}/SKILL.md').existsSync()) {
      skills[entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty)] = entity;
    }
  }
  return Map.fromEntries(
    skills.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

/// The root of the liveness_flutter package this script belongs to.
Future<Directory?> findPackageRoot(Directory project) async {
  final library = await Isolate.resolvePackageUri(
    Uri.parse('package:liveness_flutter/liveness_flutter.dart'),
  );
  if (library != null && library.isScheme('file')) {
    return File.fromUri(library).parent.parent;
  }

  // Fallback for runtimes without package resolution: read the project's
  // package config.
  final config = File('${project.path}/.dart_tool/package_config.json');
  if (!config.existsSync()) return null;
  final json = jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
  for (final package in json['packages'] as List<Object?>) {
    package as Map<String, Object?>;
    if (package['name'] == 'liveness_flutter') {
      final root = config.uri.resolve(package['rootUri'] as String);
      return Directory.fromUri(root);
    }
  }
  return null;
}

bool _isAbsolute(String path) =>
    path.startsWith('/') || RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path);

void _copyDirectory(Directory source, Directory destination) {
  destination.createSync(recursive: true);
  for (final entity in source.listSync()) {
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (name == '.DS_Store') continue;
    if (entity is Directory) {
      _copyDirectory(entity, Directory('${destination.path}/$name'));
    } else if (entity is File) {
      entity.copySync('${destination.path}/$name');
    }
  }
}
