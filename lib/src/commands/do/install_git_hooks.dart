// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;

import '../../backend/workspace_utils.dart';

/// Installs git hooks for all repositories in the current ticket.
///
/// The command copies the `assets/pre-push` template from the
/// `gg_multi` package into `.git/hooks/pre-push` of each repository
/// and the `assets/verify_push.dart` script into `.gg/verify_push.dart`.
class DoInstallGitHooksCommand extends DirCommand<void> {
  /// Creates a new [DoInstallGitHooksCommand].
  DoInstallGitHooksCommand({
    required super.ggLog,
    super.name = 'install-git-hooks',
    super.description =
        'Installs the pre-push git hook and verify_push.dart in all '
            'repositories of the current ticket.',
    SortedProcessingList? sortedProcessingList,
  }) : _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog);

  /// Helper that returns the repositories in dependency-sorted order.
  final SortedProcessingList _sortedProcessingList;

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
  }) =>
      get(
        directory: directory,
        ggLog: ggLog,
      );

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    // Detect ticket folder ---------------------------------------------------
    final String? ticketPath = WorkspaceUtils.detectTicketPath(
      path.absolute(directory.path),
    );
    if (ticketPath == null) {
      ggLog(red('This command must be executed inside a ticket folder.'));
      throw Exception('Not inside a ticket folder');
    }

    final ticketDir = Directory(ticketPath);
    final ticketName = path.basename(ticketDir.path);

    // Collect all repositories in the ticket --------------------------------
    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (nodes.isEmpty) {
      ggLog(yellow('⚠️ No repos in this ticket'));
      return;
    }

    // Resolve asset templates once ------------------------------------------
    late final String prePushTemplate;
    late final String verifyPushTemplate;

    prePushTemplate = '''#!/bin/sh
set -e

dart run .gg/verify_push.dart''';
    verifyPushTemplate = '''import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  // Only enforce the check on the main or master branch.
  final currentBranch = await _currentGitBranchOrNull();
  if (currentBranch == null) {
    stdout.writeln(
      '[pre-push] INFO: Could not determine current branch, '
      'skipping "gg did commit" check.',
    );
    return;
  }

  if (!_isProtectedBranch(currentBranch)) {
    stdout.writeln(
      '[pre-push] INFO: Branch "\$currentBranch" is not protected '
      '(main/master), skipping "gg did commit" check.',
    );
    return;
  }

  final repoRoot = await _gitTopLevelOrNull();
  if (repoRoot != null) {
    Directory.current = repoRoot;
  }

  final result = await _runPipeAndCapture('gg', ['did', 'commit']);

  final okExit = result.exitCode == 0;
  final okText = result.combinedOutput.contains(
    '✅ All changes are committed',
  );

  if (!okExit || !okText) {
    stderr.writeln(
      '\\n[pre-push] BLOCKED: "gg did commit" '
      'did not confirm "All changes are committed". '
      '(exit code \${result.exitCode})',
    );
    exitCode = okExit ? 1 : result.exitCode;
  } else {
    stdout.writeln('[pre-push] OK');
  }
}

class _RunResult {
  final int exitCode;
  final String combinedOutput;

  _RunResult(this.exitCode, this.combinedOutput);
}

Future<_RunResult> _runPipeAndCapture(
  String executable,
  List<String> arguments,
) async {
  try {
    final process = await Process.start(
      executable,
      arguments,
      runInShell: Platform.isWindows,
    );

    final buffer = StringBuffer();

    // stdout live + capture
    final stdoutSub = process.stdout.listen((chunk) {
      stdout.add(chunk);
      buffer.write(utf8.decode(chunk, allowMalformed: true));
    });

    // stderr live + capture (in case gg writes there)
    final stderrSub = process.stderr.listen((chunk) {
      stderr.add(chunk);
      buffer.write(utf8.decode(chunk, allowMalformed: true));
    });

    final code = await process.exitCode;
    await stdoutSub.cancel();
    await stderrSub.cancel();

    return _RunResult(code, buffer.toString());
  } on ProcessException catch (e) {
    stderr.writeln('[pre-push] Could not run "\$executable": \${e.message}');
    // If gg is not available, block the push.
    return _RunResult(127, '');
  }
}

Future<String?> _gitTopLevelOrNull() async {
  try {
    final res = await Process.run(
      'git',
      ['rev-parse', '--show-toplevel'],
      runInShell: Platform.isWindows,
    );
    if (res.exitCode != 0) {
      return null;
    }
    return (res.stdout as String).trim();
  } catch (_) {
    return null;
  }
}

Future<String?> _currentGitBranchOrNull() async {
  try {
    final res = await Process.run(
      'git',
      ['rev-parse', '--abbrev-ref', 'HEAD'],
      runInShell: Platform.isWindows,
    );
    if (res.exitCode != 0) {
      return null;
    }
    final branch = (res.stdout as String).trim();
    if (branch.isEmpty || branch == 'HEAD') {
      return null;
    }
    return branch;
  } catch (_) {
    return null;
  }
}

bool _isProtectedBranch(String branchName) {
  final normalized = branchName.trim();
  return normalized == 'main' || normalized == 'master';
}
''';

    // Install hooks into each repository ------------------------------------
    for (final node in nodes) {
      final repoDir = node.directory;
      final repoName = path.basename(repoDir.path);

      final gitDir = Directory(path.join(repoDir.path, '.git'));
      if (!gitDir.existsSync()) {
        ggLog(
          yellow(
            'Skipping $repoName because no .git directory was found.',
          ),
        );
        continue;
      }

      // Copy pre-push hook -------------------------------------------------
      final hooksDir = Directory(path.join(gitDir.path, 'hooks'))
        ..createSync(recursive: true);
      final prePushTarget = File(path.join(hooksDir.path, 'pre-push'));

      await prePushTarget.writeAsString(prePushTemplate);

      // Try to make the hook executable on POSIX systems.
      // coverage:ignore-start
      if (!Platform.isWindows) {
        try {
          await Process.run(
            'chmod',
            <String>['+x', prePushTarget.path],
            runInShell: true,
          );
        } catch (_) {
          // Making the file executable is best-effort only.
        }
      }
      // coverage:ignore-end

      // Copy verify_push.dart into .gg ------------------------------------
      final ggDir = Directory(path.join(repoDir.path, '.gg'))
        ..createSync(recursive: true);
      final verifyTarget = File(path.join(ggDir.path, 'verify_push.dart'));

      await verifyTarget.writeAsString(verifyPushTemplate);

      ggLog(
        'Installed git hooks for $repoName in ticket $ticketName.',
      );
    }

    ggLog(
      '✅ Installed git hooks for all repositories in ticket '
      '$ticketName.',
    );
  }
}
