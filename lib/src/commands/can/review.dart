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
import 'package:gg_publish/gg_publish.dart' as gg_publish;
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;

import '../../backend/workspace_utils.dart';

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

/// Command to check if all repos in the ticket can be reviewed.
class CanReviewCommand extends DirCommand<void> {
  /// Constructor
  CanReviewCommand({
    required super.ggLog,
    super.name = 'review',
    super.description =
        'Checks if all repositories in the current ticket can be reviewed.',
    SortedProcessingList? sortedProcessingList,
    ProcessRunner? processRunner,
    gg_publish.IsFeatureBranch? ggIsFeatureBranch,
  })  : _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog),
        _processRunner = processRunner ?? _defaultProcessRunner,
        _ggIsFeatureBranch =
            ggIsFeatureBranch ?? gg_publish.IsFeatureBranch(ggLog: ggLog) {
    _addArgs();
  }

  /// Instance of SortedProcessingList
  final SortedProcessingList _sortedProcessingList;

  /// The process runner
  final ProcessRunner _processRunner;

  /// Instance of gg_publish IsFeatureBranch
  final gg_publish.IsFeatureBranch _ggIsFeatureBranch;

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

    // Step 1: Detect ticket folder
    final String? ticketPath = WorkspaceUtils.detectTicketPath(
      path.absolute(directory.path),
    );
    if (ticketPath == null) {
      ggLog(red('This command must be executed inside a ticket folder.'));
      throw Exception('Not inside a ticket folder');
    }

    final ticketDir = Directory(ticketPath);
    final ticketName = path.basename(ticketDir.path);

    // Get sorted repos
    final subs = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (subs.isEmpty) {
      ggLog(yellow('⚠️ No repositories found in ticket $ticketName.'));
      return;
    }

    // Only show task logs when verbose is enabled
    final GgLog taskLog = verbose ? ggLog : <String>[].add;

    // Step 2: Check that all repos are on a feature branch
    await GgStatusPrinter<void>(
      message: 'On feature branch?',
      ggLog: ggLog,
    ).run(
      () async => _checkFeatureBranches(
        subs: subs,
        ggLog: taskLog,
      ),
    );

    // Step 3: Check for uncommitted changes
    await GgStatusPrinter<void>(
      message: 'Uncommitted changes?',
      ggLog: ggLog,
    ).run(
      () async => _checkUncommittedChanges(
        subs: subs,
        ggLog: taskLog,
      ),
    );

    // All successful
    ggLog('✅ All repositories in ticket $ticketName can be reviewed.');
  }

  /// Checks that all repos are on a feature branch.
  Future<void> _checkFeatureBranches({
    required List<Node> subs,
    required GgLog ggLog,
  }) async {
    final notOnFeatureBranch = <String>[];
    for (final repo in subs) {
      final repoDir = repo.directory;
      final repoName = path.basename(repoDir.path);
      final isFeature = await _ggIsFeatureBranch.get(
        directory: repoDir,
        ggLog: ggLog,
      );
      if (!isFeature) {
        notOnFeatureBranch.add(repoName);
      }
    }
    if (notOnFeatureBranch.isNotEmpty) {
      ggLog(
        yellow('The following repos are not on a feature branch:'),
      );
      for (final name in notOnFeatureBranch) {
        ggLog(yellow(' - $name'));
      }
      throw Exception(
        'The following repositories are not on a feature branch: '
        '${notOnFeatureBranch.join(', ')}',
      );
    }
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
      throw Exception(
        'Uncommitted changes found in the following repositories: '
        '${uncommitted.join(', ')}',
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

/// Mock for [CanReviewCommand]
class MockCanReviewCommand extends MockDirCommand<void>
    implements CanReviewCommand {}
