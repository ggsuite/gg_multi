// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;
import '../backend/workspace_utils.dart';

/// Typedef for creating Directory instances (for testing).
typedef DirectoryFactory = Directory Function(String path);

/// Typedef for running processes (for injection & tests).
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

/// Default process runner that uses the system's `Process.run`
// coverage:ignore-start
Future<ProcessResult> _defaultProcessRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) =>
    Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: true,
    );
// coverage:ignore-end

/// Command to review a ticket: check uncommitted changes,
/// unlocalize refs, localize refs, and create pull requests.
class ReviewCommand extends Command<void> {
  /// Constructor
  ReviewCommand({
    required this.ggLog,
    String? executionPath,
    DirectoryFactory? directoryFactory,
    ProcessRunner? processRunner,
    // coverage:ignore-start
  })  : executionPath = executionPath ?? Directory.current.path,
        _dirFactory = directoryFactory ?? Directory.new,
        _runProc = processRunner ?? _defaultProcessRunner;
  // coverage:ignore-end

  /// Logger function
  final GgLog ggLog;

  /// The path from which the command was executed.
  final String executionPath;

  /// Factory to create Directory instances (for testing).
  final DirectoryFactory _dirFactory;

  /// Function to run processes (for injection & tests).
  final ProcessRunner _runProc;

  @override
  String get name => 'review';

  @override
  String get description => 'Starts the review workflow for a ticket.';

  @override
  Future<void> run() async {
    // Step 1. Locate the ticket directory (must be inside ticket)
    final String? ticketPath = WorkspaceUtils.detectTicketPath(executionPath);
    if (ticketPath == null) {
      ggLog(red('Review must be executed inside a ticket folder.'));
      return;
    }
    Directory ticketDir = _dirFactory(ticketPath);
    // Step 2. Collect all repo directories in ticket
    final subs = ticketDir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));
    if (subs.isEmpty) {
      ggLog(
        yellow(
          'No repositories found in ticket ${path.basename(ticketDir.path)}.',
        ),
      );
      return;
    }
    // Step 3. Check for uncommitted changes in any repo
    final uncommitted = <String>[];
    for (final repoDir in subs) {
      final result = await _runProc(
        'git',
        ['status', '--porcelain'],
        workingDirectory: repoDir.path,
      );
      if (result.stdout.toString().trim().isNotEmpty) {
        uncommitted.add(path.basename(repoDir.path));
      }
    }
    if (uncommitted.isNotEmpty) {
      ggLog(yellow('Uncommitted changes found in the following repos:'));
      for (final name in uncommitted) {
        ggLog(yellow(' - $name'));
      }
      ggLog(red('Please commit or stash your changes before reviewing.'));
      return;
    }
    // Step 4. Run unlocalize-refs, localize-refs --git, and gh pr create
    for (final repoDir in subs) {
      // Unlocalize refs
      try {
        final unlocalizeResult = await _runProc(
          'gg_localize_refs',
          ['unlocalize-refs'],
          workingDirectory: repoDir.path,
        );
        if (unlocalizeResult.exitCode != 0) {
          throw Exception(unlocalizeResult.stderr);
        }
        ggLog(
          green('Unlocalized refs for ${path.basename(repoDir.path)}'),
        );
      } catch (e) {
        ggLog(
          red(
            'Failed to unlocalize refs for ${path.basename(repoDir.path)}: $e',
          ),
        );
        continue;
      }
      // Localize refs with --git
      try {
        final localizeResult = await _runProc(
          'gg_localize_refs',
          ['localize-refs', '--git'],
          workingDirectory: repoDir.path,
        );
        if (localizeResult.exitCode != 0) {
          throw Exception(localizeResult.stderr);
        }
        ggLog(
          green('Localized refs for ${path.basename(repoDir.path)}'),
        );
      } catch (e) {
        ggLog(
          red('Failed to localize refs with --git for '
              '${path.basename(repoDir.path)}: $e'),
        );
        // Still continue to PR creation
      }
      // PR create
      try {
        final prResult = await _runProc(
          'gh',
          ['pr', 'create'],
          workingDirectory: repoDir.path,
        );
        if (prResult.exitCode != 0) {
          throw Exception(prResult.stderr);
        }
        ggLog(
          green('Created PR for ${path.basename(repoDir.path)}'),
        );
      } catch (e) {
        ggLog(
          red('Failed to create PR for ${path.basename(repoDir.path)}: $e'),
        );
      }
    }
  }
}
