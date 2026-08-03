// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_one/gg_one.dart' as gg;
import 'package:gg_publish/gg_publish.dart' as gg_publish;
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;

import '../../backend/workspace_utils.dart';
import '../../commands/did/commit.dart';
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
    super.description = 'Check if all ticket repos can be published',
    gg.CanCommit? ggCanCommit,
    gg.CanMerge? ggCanMerge,
    gg.CanPublish? ggCanPublish,
    gg.NpmLoggedIn? ggNpmLoggedIn,
    gg_publish.MergeMainIntoFeat? ggMergeMainIntoFeat,
    SortedProcessingList? sortedProcessingList,
    ProcessRunner? processRunner,
    DidCommitCommand? didCommitCommand,
    DoPushCommand? doPushCommand,
  })  : _ggCanMerge = ggCanMerge ?? gg.CanMerge(ggLog: ggLog),
        _ggCanPublish = ggCanPublish ?? gg.CanPublish(ggLog: ggLog),
        _ggNpmLoggedIn = ggNpmLoggedIn ?? gg.NpmLoggedIn(ggLog: ggLog),
        _ggMergeMainIntoFeat =
            ggMergeMainIntoFeat ?? gg_publish.MergeMainIntoFeat(ggLog: ggLog),
        _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog),
        _processRunner = processRunner ?? _defaultProcessRunner,
        _didCommitCommand = didCommitCommand ?? DidCommitCommand(ggLog: ggLog),
        _doPushCommand = doPushCommand ?? DoPushCommand(ggLog: ggLog) {
    _addArgs();
  }

  /// Instance of gg CanMerge
  final gg.CanMerge _ggCanMerge;

  /// Instance of gg CanPublish (per-repo publish readiness, incl. npm auth)
  final gg.CanPublish _ggCanPublish;

  /// Instance of gg NpmLoggedIn (ticket wide npm authentication check)
  final gg.NpmLoggedIn _ggNpmLoggedIn;

  /// Instance of gg MergeMainIntoFeat
  final gg_publish.MergeMainIntoFeat _ggMergeMainIntoFeat;

  /// Instance of SortedProcessingList
  final SortedProcessingList _sortedProcessingList;

  /// The process runner
  final ProcessRunner _processRunner;

  /// Instance of DidCommitCommand
  final DidCommitCommand _didCommitCommand;

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
  }) =>
      checkTicket(directory: directory, ggLog: ggLog, verbose: verbose);

  /// Runs the ticket wide publish readiness checks for [directory].
  ///
  /// [includeCanPublish] controls the last step, `gg can publish` per repo.
  /// `gg can publish` runs it — that is the default. `gg do publish` passes
  /// `false` and calls [checkRepo] per repo instead: only there are the refs
  /// unlocalized and the dependencies published earlier in the same run
  /// already on their registry, so pana can resolve them.
  Future<void> checkTicket({
    required Directory directory,
    required GgLog ggLog,
    bool? verbose,
    bool includeCanPublish = true,
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
      ggLog(yellow('⚠️ No repos in this ticket'));
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

    // Step 3: Run gg_multi did commit ------------------------------------
    await GgStatusPrinter<void>(
      message: 'Did commit?',
      ggLog: ggLog,
    ).run(
      () async => _runDidCommit(
        ticketDir: ticketDir,
        ggLog: taskLog,
      ),
    );

    // Step 4: Run gg merge main into feat -----------------------------------
    await GgStatusPrinter<void>(
      message: 'Merge main into feat?',
      ggLog: ggLog,
    ).run(
      () async => _runMergeMainIntoFeat(
        ticketName: ticketName,
        subs: subs,
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

    // Step 6: Run gg_multi do push ---------------------------------------
    await GgStatusPrinter<void>(
      message: 'Running do push',
      ggLog: ggLog,
    ).run(
      () async => _runDoPush(
        ticketDir: ticketDir,
        ggLog: taskLog,
      ),
    );

    // Step 7: Check the npm authentication ----------------------------------
    // This is the one publish blocker that has nothing to do with dependency
    // resolution, so it stays ticket wide even when step 8 is deferred to
    // `do publish`'s per-repo gate: finding out about a missing npm login
    // after the first packages went to a registry is the worst failure mode
    // this command has. Repos not publishing to npm are skipped by gg_one.
    await GgStatusPrinter<void>(
      message: 'Logged in to npm?',
      ggLog: ggLog,
    ).run(
      () async => _checkNpmLoggedIn(
        subs: subs,
        ggLog: taskLog,
      ),
    );

    // Step 8: Run gg can publish per repo -----------------------------------
    // Verifies each repo's publish readiness (feature branch, CHANGELOG,
    // pana, npm authentication).
    if (includeCanPublish) {
      await GgStatusPrinter<void>(
        message: 'Can publish?',
        ggLog: ggLog,
      ).run(
        () async => _checkCanPublish(
          subs: subs,
          ggLog: taskLog,
        ),
      );
    }

    // All successful --------------------------------------------------------
    taskLog('✓ All repos can be published');
  }

  /// Checks whether the single repository [directory] can be published.
  ///
  /// Covers the same ground as the ticket wide `Can publish?` step — feature
  /// branch, no path overrides, CHANGELOG format, committed changes, pana and
  /// npm authentication — for one repo, and throws the same
  /// `Cannot publish: <repo> (<reason>)` exception.
  ///
  /// [directory] is a repository, not a ticket folder. The caller decides how
  /// verbose the output is: `gg do publish` passes its own `ggLog`, because a
  /// rejection here is what makes the run fail.
  Future<void> checkRepo({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    final failure = await _canPublishFailure(repoDir: directory, ggLog: ggLog);
    if (failure != null) {
      throw Exception('Cannot publish: $failure');
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
      ggLog(yellow('Uncommitted changes in:'));
      for (final name in uncommitted) {
        ggLog(yellow(' - $name'));
      }
      throw Exception('Uncommitted changes found');
    }
  }

  /// Executes gg_multi did commit for the ticket.
  Future<void> _runDidCommit({
    required Directory ticketDir,
    required GgLog ggLog,
  }) async {
    try {
      await _didCommitCommand.exec(directory: ticketDir, ggLog: ggLog);
    } catch (e) {
      ggLog(red('gg_multi did commit failed: $e'));
      throw Exception('gg_multi did commit failed');
    }
  }

  /// Executes gg merge main into feat for every repository in the ticket.
  Future<void> _runMergeMainIntoFeat({
    required String ticketName,
    required List<Node> subs,
    required GgLog ggLog,
  }) async {
    for (final repo in subs) {
      final repoDir = repo.directory;
      final repoName = path.basename(repoDir.path);

      try {
        await _ggMergeMainIntoFeat.exec(directory: repoDir, ggLog: ggLog);
      } catch (e) {
        ggLog(
          red(
            'gg merge main into feat failed for $repoName in ticket '
            '$ticketName: $e',
          ),
        );
        throw Exception('gg merge main into feat failed: $e');
      }
    }
  }

  /// Executes gg_multi do push for the ticket.
  Future<void> _runDoPush({
    required Directory ticketDir,
    required GgLog ggLog,
  }) async {
    try {
      await _doPushCommand.exec(directory: ticketDir, ggLog: ggLog);
    } catch (e) {
      ggLog(red('gg_multi do push failed: $e'));
      throw Exception('gg_multi do push failed');
    }
  }

  /// Runs gg can publish for the repository [repoDir].
  ///
  /// Returns `null` when the repo is publish-ready, otherwise the
  /// `<repo> (<error>)` description the failure is reported with. One code
  /// path for the ticket wide check and for [checkRepo], so the two cannot
  /// report the same problem differently.
  Future<String?> _canPublishFailure({
    required Directory repoDir,
    required GgLog ggLog,
  }) async {
    final repoName = path.basename(repoDir.path);
    ggLog('\n${cyan(repoName)}:');
    try {
      await _ggCanPublish.exec(directory: repoDir, ggLog: ggLog);
      return null;
    } catch (e) {
      ggLog(red('✗ Cannot publish $repoName: $e'));
      return '$repoName ($e)';
    }
  }

  /// Runs gg can publish for every repository in the ticket, collecting the
  /// repos that are not publish-ready (e.g. not logged in to npm).
  Future<void> _checkCanPublish({
    required List<Node> subs,
    required GgLog ggLog,
  }) async {
    final failedRepos = <String>[];
    for (final repo in subs) {
      final failure = await _canPublishFailure(
        repoDir: repo.directory,
        ggLog: ggLog,
      );
      if (failure != null) {
        failedRepos.add(failure);
      }
    }
    if (failedRepos.isNotEmpty) {
      throw Exception('Cannot publish: ${failedRepos.join('; ')}');
    }
  }

  /// Checks the npm authentication of every repository in the ticket.
  Future<void> _checkNpmLoggedIn({
    required List<Node> subs,
    required GgLog ggLog,
  }) async {
    final failedRepos = <String>[];
    for (final repo in subs) {
      final repoDir = repo.directory;
      final repoName = path.basename(repoDir.path);
      ggLog('\n${cyan(repoName)}:');
      try {
        await _ggNpmLoggedIn.exec(directory: repoDir, ggLog: ggLog);
      } catch (e) {
        ggLog(red('✗ Not logged in to npm for $repoName: $e'));
        failedRepos.add('$repoName ($e)');
      }
    }
    if (failedRepos.isNotEmpty) {
      throw Exception('Not logged in to npm: ${failedRepos.join('; ')}');
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
      ggLog('\n${cyan(repoName)}:');
      try {
        await _ggCanMerge.exec(directory: repoDir, ggLog: ggLog);
      } catch (e) {
        ggLog(red('✗ Cannot merge $repoName: $e'));
        failedMergeRepos.add(repoName);
      }
    }
    if (failedMergeRepos.isNotEmpty) {
      ggLog(red('✗ Merge check failed in:'));
      for (final repoName in failedMergeRepos) {
        ggLog(red(' - $repoName'));
      }
      throw Exception(
        'Failed to check merge in: ${failedMergeRepos.join(', ')}',
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
