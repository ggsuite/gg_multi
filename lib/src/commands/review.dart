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

  /// Runs an external command and logs the result.
  /// - On success (exitCode == 0): Log the [successMessage] in green.
  /// - On failure: Log the [failureMessage] and error in red.
  /// - Returns true on success, false otherwise.
  Future<bool> _runCommand(
    String executable,
    List<String> arguments,
    String successMessage,
    String failureMessage, {
    required String workingDirectory,
  }) async {
    try {
      final result = await _runProc(
        executable,
        arguments,
        workingDirectory: workingDirectory,
      );
      if (result.exitCode != 0) {
        throw Exception(result.stderr);
      }
      ggLog(green(successMessage));
      return true;
    } catch (e) {
      ggLog(red('$failureMessage: $e'));
      return false;
    }
  }

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
    // Step 4. Run commands: unlocalize-refs, localize-refs --git,
    // and gh pr create
    for (final repoDir in subs) {
      final name = path.basename(repoDir.path);
      // Unlocalize refs. If failed, skip to next repo.
      final okUnloc = await _runCommand(
        'gg_localize_refs',
        ['unlocalize-refs'],
        'Unlocalized refs for $name',
        'Failed to unlocalize refs for $name',
        workingDirectory: repoDir.path,
      );
      if (!okUnloc) {
        continue;
      }
      // Localize refs with --git. Error logs, but continues.
      await _runCommand(
        'gg_localize_refs',
        ['localize-refs', '--git'],
        'Localized refs for $name',
        'Failed to localize refs with --git for $name',
        workingDirectory: repoDir.path,
      );
      // PR create. Error logs, but continues.
      await _runCommand(
        'gh',
        ['pr', 'create'],
        'Created PR for $name',
        'Failed to create PR for $name',
        workingDirectory: repoDir.path,
      );
    }
  }
}
