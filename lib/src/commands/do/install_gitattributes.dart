// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;

import '../../backend/workspace_utils.dart';

/// Function used to spawn child processes (e.g. `git`). Injected for tests.
///
/// Signature matches the `ProcessRunner` typedef used by `add.dart` so the
/// same runner can be plumbed through.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  bool runInShell,
});

/// The lines `gg` and the ticket workflow require in every repository's
/// `.gitattributes` file.
///
/// - `* text=auto eol=lf` enables automatic EOL conversion to LF (required
///   by `gg`).
/// - The `merge=ours` rules ensure that generated/state files are not
///   merged textually but kept from the current branch.
const String gitattributesRequiredLines = '* text=auto eol=lf\n'
    '.gg/.gg.json merge=ours\n'
    'pubspec.lock merge=ours';

/// Ensures a `.gitattributes` file containing all
/// [gitattributesRequiredLines] exists in every repository of the current
/// ticket and that the `merge=ours` driver is configured locally.
///
/// `gg` refuses to operate (e.g. `gg do commit`) when automatic EOL
/// conversion is not configured via `.gitattributes`. In addition, the
/// ticket workflow relies on `merge=ours` rules for state files so that
/// merges do not produce textual conflicts in generated content. The
/// referenced `ours` driver only works once
/// `git config merge.ours.driver true` has been set in each repository.
///
/// Behaviour per repository:
/// - If `.gitattributes` does not exist, it is created containing all
///   required lines.
/// - If `.gitattributes` exists, every required line that is missing is
///   appended individually.
/// - If all required lines are already present, the file is left
///   untouched.
/// - If a `.git` directory exists, `git config merge.ours.driver true` is
///   executed with the repository as the working directory so the
///   `merge=ours` rules can be honored by git.
class DoInstallGitattributesCommand extends DirCommand<void> {
  /// Creates a new [DoInstallGitattributesCommand].
  DoInstallGitattributesCommand({
    required super.ggLog,
    super.name = 'install-gitattributes',
    super.description = 'Ensures a .gitattributes file with the required '
        'lines exists in all repositories of the current ticket and that '
        'the merge=ours driver is configured.',
    SortedProcessingList? sortedProcessingList,
    ProcessRunner? processRunner,
  })  : _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog),
        _processRunner = processRunner ?? Process.run;

  /// Helper that returns the repositories in dependency-sorted order.
  final SortedProcessingList _sortedProcessingList;

  /// Process runner used to invoke `git`.
  final ProcessRunner _processRunner;

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

    final requiredLines = const LineSplitter()
        .convert(gitattributesRequiredLines)
        .where((l) => l.isNotEmpty)
        .toList();

    // Ensure .gitattributes and merge.ours driver in each repository --------
    for (final node in nodes) {
      final repoDir = node.directory;
      final repoName = path.basename(repoDir.path);

      final attributesFile = File(
        path.join(repoDir.path, '.gitattributes'),
      );

      if (!attributesFile.existsSync()) {
        await attributesFile.writeAsString(
          '${requiredLines.join('\n')}\n',
        );
        ggLog('Created .gitattributes in $repoName.');
      } else {
        final existing = await attributesFile.readAsString();
        final existingLines =
            const LineSplitter().convert(existing).map((l) => l.trim()).toSet();

        final missingLines =
            requiredLines.where((l) => !existingLines.contains(l)).toList();

        if (missingLines.isNotEmpty) {
          final needsLeadingNewline =
              existing.isNotEmpty && !existing.endsWith('\n');
          final prefix = needsLeadingNewline ? '\n' : '';
          await attributesFile.writeAsString(
            '$prefix${missingLines.join('\n')}\n',
            mode: FileMode.append,
          );
          ggLog('Updated .gitattributes in $repoName.');
        }
      }

      // Configure the `ours` merge driver locally so the `merge=ours`
      // rules in .gitattributes resolve to a real git driver.
      final gitDir = Directory(path.join(repoDir.path, '.git'));
      if (!gitDir.existsSync()) {
        ggLog(
          yellow(
            'Skipping merge.ours driver config for $repoName because no '
            '.git directory was found.',
          ),
        );
        continue;
      }

      final result = await _processRunner(
        'git',
        <String>['config', 'merge.ours.driver', 'true'],
        workingDirectory: repoDir.path,
        runInShell: Platform.isWindows,
      );

      if (result.exitCode != 0) {
        ggLog(
          red(
            'Failed to configure merge.ours driver in $repoName: '
            '${result.stderr}',
          ),
        );
        throw Exception(
          'git config merge.ours.driver true failed in $repoName',
        );
      }

      ggLog('Configured merge.ours driver in $repoName.');
    }

    ggLog(
      '✅ Ensured .gitattributes for all repositories in ticket '
      '$ticketName.',
    );
  }
}
