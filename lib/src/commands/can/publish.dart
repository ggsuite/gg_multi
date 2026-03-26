// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg/gg.dart' as gg;
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;

import '../../backend/workspace_utils.dart';
import '../../commands/can/commit.dart';
import '../../commands/do/push.dart';

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

/// Command to check if all repos in the ticket can be published.
class CanPublishCommand extends DirCommand<void> {
  /// Constructor
  CanPublishCommand({
    required super.ggLog,
    super.name = 'publish',
    super.description =
        'Checks if all repositories in the current ticket can be published.',
    gg.CanCommit? ggCanCommit,
    gg.CanMerge? ggCanMerge,
    SortedProcessingList? sortedProcessingList,
    ProcessRunner? processRunner,
    CanCommitCommand? canCommitCommand,
    DoPushCommand? doPushCommand,
  })  : _ggCanMerge = ggCanMerge ?? gg.CanMerge(ggLog: ggLog),
        _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog),
        _processRunner = processRunner ?? _defaultProcessRunner,
        _canCommitCommand = canCommitCommand ?? CanCommitCommand(ggLog: ggLog),
        _doPushCommand = doPushCommand ?? DoPushCommand(ggLog: ggLog) {
    _addArgs();
  }

  /// Instance of gg CanMerge
  final gg.CanMerge _ggCanMerge;

  /// Instance of SortedProcessingList
  final SortedProcessingList _sortedProcessingList;

  /// The process runner
  final ProcessRunner _processRunner;

  /// Instance of CanCommitCommand
  final CanCommitCommand _canCommitCommand;

  /// Instance of DoPushCommand
  final DoPushCommand _doPushCommand;

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    bool? verbose,
  }) =>
      get(
        directory: directory,
        ggLog: ggLog,
        verbose: verbose,
      );

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    bool? verbose,
  }) async {
    verbose ??= argResults?['verbose'] as bool? ?? false;

    // Step 1: Detect ticket folder -----------------------------------------
    final String? ticketPath = WorkspaceUtils.detectTicketPath(
      path.absolute(directory.path),
    );
    if (ticketPath == null) {
      ggLog(red('This command must be executed inside a ticket folder.'));
      throw Exception('Not inside a ticket folder');
    }

    final ticketDir = Directory(ticketPath);
    final ticketName = path.basename(ticketDir.path);

    // Get sorted repos ------------------------------------------------------
    final subs = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (subs.isEmpty) {
      ggLog(yellow('⚠️ No repositories found in ticket $ticketName.'));
      return;
    }

    // Only show task logs when verbose is enabled ---------------------------
    final GgLog taskLog = verbose ? ggLog : <String>[].add;

    // Step 2: Check for uncommitted changes ---------------------------------
    await GgStatusPrinter<void>(
      message: 'Uncommitted changes?',
      ggLog: ggLog,
    ).run(
      () async => _checkUncommittedChanges(
        subs: subs,
        ggLog: taskLog,
      ),
    );

    // Step 3: Run kidney_core can commit ------------------------------------
    await GgStatusPrinter<void>(
      message: 'Can commit?',
      ggLog: ggLog,
    ).run(
      () async => _runCanCommit(
        ticketDir: ticketDir,
        ggLog: taskLog,
      ),
    );

    // Step 4: Run kidney_core do push ---------------------------------------
    await GgStatusPrinter<void>(
      message: 'Running do push',
      ggLog: ggLog,
    ).run(
      () async => _runDoPush(
        ticketDir: ticketDir,
        ggLog: taskLog,
      ),
    );

    // Step 5: Run gg can merge per repo -------------------------------------
    await GgStatusPrinter<void>(
      message: 'Can merge?',
      ggLog: ggLog,
    ).run(
      () async => _checkCanMerge(
        ticketName: ticketName,
        subs: subs,
        ggLog: taskLog,
      ),
    );

    // All successful --------------------------------------------------------
    taskLog(
      '✅ All repositories in ticket $ticketName can be published.',
    );
  }

  /// Checks for uncommitted changes in all repos.
  Future<void> _checkUncommittedChanges({
    required List<Node> subs,
    required GgLog ggLog,
  }) async {
    final uncommitted = <String>[];
    for (final repo in subs) {
      final repoDir = repo.directory;
      final result = await _processRunner(
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
      throw Exception('Uncommitted changes found');
    }
  }

  /// Executes kidney_core can commit for the ticket.
  Future<void> _runCanCommit({
    required Directory ticketDir,
    required GgLog ggLog,
  }) async {
    try {
      await _canCommitCommand.exec(directory: ticketDir, ggLog: ggLog);
    } catch (e) {
      ggLog(red('kidney_core can commit failed: $e'));
      throw Exception('kidney_core can commit failed');
    }
  }

  /// Executes kidney_core do push for the ticket.
  Future<void> _runDoPush({
    required Directory ticketDir,
    required GgLog ggLog,
  }) async {
    try {
      await _doPushCommand.exec(directory: ticketDir, ggLog: ggLog);
    } catch (e) {
      ggLog(red('kidney_core do push failed: $e'));
      throw Exception('kidney_core do push failed');
    }
  }

  /// Runs gg can merge for every repository in the ticket.
  Future<void> _checkCanMerge({
    required String ticketName,
    required List<Node> subs,
    required GgLog ggLog,
  }) async {
    final failedMergeRepos = <String>[];
    for (final repo in subs) {
      final repoDir = repo.directory;
      final repoName = path.basename(repoDir.path);
      ggLog(
        yellow('Checking if $repoName in ticket '
            '$ticketName can be merged...'),
      );
      try {
        await _ggCanMerge.exec(directory: repoDir, ggLog: ggLog);
      } catch (e) {
        ggLog(red('❌ Cannot merge $repoName: $e'));
        failedMergeRepos.add(repoName);
      }
    }
    if (failedMergeRepos.isNotEmpty) {
      ggLog(
        red('❌ Failed to check merge for the '
            'following repositories in ticket $ticketName:'),
      );
      for (final repoName in failedMergeRepos) {
        ggLog(red(' - $repoName'));
      }
      throw Exception(
        'Failed to check merge for '
        'some repositories in ticket $ticketName',
      );
    }
  }

  // Adds command line arguments
  void _addArgs() {
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'Show detailed log output.',
      defaultsTo: false,
      negatable: true,
    );
  }
}

/// Mock for [CanPublishCommand]
class MockCanPublishCommand extends MockDirCommand<void>
    implements CanPublishCommand {}
