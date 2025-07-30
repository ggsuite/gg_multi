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
import 'package:gg_localize_refs/gg_localize_refs.dart';

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
    UnlocalizeRefs? unlocalizeRefs,
    LocalizeRefs? localizeRefs,
    // coverage:ignore-start
  })  : executionPath = executionPath ?? Directory.current.path,
        _dirFactory = directoryFactory ?? Directory.new,
        _runProc = processRunner ?? _defaultProcessRunner,
        _unlocalizeRefs = unlocalizeRefs ?? UnlocalizeRefs(ggLog: ggLog),
        _localizeRefs = localizeRefs ?? LocalizeRefs(ggLog: ggLog);
  // coverage:ignore-end

  /// Logger function
  final GgLog ggLog;

  /// The path from which the command was executed.
  final String executionPath;

  /// Factory to create Directory instances (for testing).
  final DirectoryFactory _dirFactory;

  /// Function to run processes (for injection & tests).
  final ProcessRunner _runProc;

  /// Instance of UnlocalizeRefs for unlocalizing refs.
  final UnlocalizeRefs _unlocalizeRefs;

  /// Instance of LocalizeRefs for localizing refs.
  final LocalizeRefs _localizeRefs;

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
    // Step 4. Run commands: unlocalize-refs, localize-refs --git,
    // and gh pr create
    for (final repoDir in subs) {
      final name = path.basename(repoDir.path);
      // Unlocalize refs. If failed, skip to next repo.
      bool okUnloc = false;
      try {
        await _unlocalizeRefs.get(directory: repoDir, ggLog: ggLog);
        ggLog(green('Unlocalized refs for $name'));
        okUnloc = true;
      } catch (e) {
        ggLog(red('Failed to unlocalize refs for $name: $e'));
        okUnloc = false;
      }
      if (!okUnloc) {
        continue;
      }
      // Localize refs with --git. Error logs, but continues.
      try {
        await _localizeRefs.get(directory: repoDir, ggLog: ggLog, git: true);
        ggLog(green('Localized refs for $name'));
      } catch (e) {
        ggLog(red('Failed to localize refs with --git for $name: $e'));
      }
    }
  }
}
