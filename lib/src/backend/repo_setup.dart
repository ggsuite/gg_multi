// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:path/path.dart' as path;

/// Runs a process; the named-argument shape used across gg_multi commands.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  bool runInShell,
});

/// Installs dependencies for every package manager the repo in [dir] uses.
///
/// A cross-language bridge repo carrying both a `pubspec.yaml` and a
/// `package.json` gets both its Dart and its TypeScript dependencies
/// installed. When [upgradeDart] is true, `dart pub upgrade` is used instead
/// of `dart pub get` (used after re-localizing references).
Future<void> installRepoDependencies({
  required Directory dir,
  required String repoName,
  required GgLog ggLog,
  required ProcessRunner processRunner,
  bool upgradeDart = false,
}) async {
  final commands = <List<String>>[];

  if (File(path.join(dir.path, 'pubspec.yaml')).existsSync()) {
    commands.add(<String>['dart', 'pub', upgradeDart ? 'upgrade' : 'get']);
  }
  if (File(path.join(dir.path, 'package.json')).existsSync()) {
    final pm = gg.detectTypeScriptPackageManager(dir).executable;
    commands.add(<String>[pm, 'install']);
  }

  for (final command in commands) {
    final result = await processRunner(
      command.first,
      command.sublist(1),
      workingDirectory: dir.path,
      runInShell: true,
    );
    final cmd = command.join(' ');
    if (result.exitCode == 0) {
      ggLog(darkGray('Executed $cmd in $repoName.'));
    } else {
      ggLog(red('Failed to execute $cmd in $repoName: ${result.stderr}'));
    }
  }
}

/// Writes the VS Code `.code-workspace` file for [ticketDir] with one folder
/// entry per repository in [repoPaths] (deduplicated, insertion order kept).
///
/// Each entry is the path of the repository relative to [ticketDir], i.e.
/// `<org>/<repo>`. It is always written with forward slashes — VS Code
/// understands those on every platform, a Windows separator would end up
/// escaped in the JSON.
///
/// A ticket without repositories — a freshly created one — gets the ticket
/// folder itself as its single entry. An empty folder list would open a
/// window showing nothing at all, and VS Code offers no way to add the first
/// folder from there.
void writeCodeWorkspaceFile(Directory ticketDir, List<String> repoPaths) {
  final folders = (repoPaths.isEmpty ? const <String>['.'] : repoPaths)
      .toSet()
      .map<Map<String, String>>(
        (repoPath) => <String, String>{
          'path': path.posix.joinAll(path.split(repoPath)),
        },
      )
      .toList();
  final ticketName = path.basename(ticketDir.path);
  final file = File(path.join(ticketDir.path, '$ticketName.code-workspace'));
  final content = jsonEncode(<String, Object?>{'folders': folders});
  file.writeAsStringSync('$content\n');
}
