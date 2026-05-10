// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_one/gg_one.dart' as gg;
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_localize_refs/gg_localize_refs.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;

import '../../backend/status_utils.dart';
import '../../backend/workspace_utils.dart';
import '../../commands/can/review.dart';

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

/// Command to review all repos in the ticket.
class DoReviewCommand extends DirCommand<void> {
  /// Constructor
  DoReviewCommand({
    required super.ggLog,
    super.name = 'review',
    super.description = 'Reviews all repositories in the current ticket.',
    CanReviewCommand? canReviewCommand,
    ChangeRefsToPubDev? unlocalizeRefs,
    ChangeRefsToGitFeatureBranch? localizeRefsToGit,
    SortedProcessingList? sortedProcessingList,
    gg.DoCommit? ggDoCommit,
    gg.DoPush? ggDoPush,
    ProcessRunner? processRunner,
  })  : _canReviewCommand = canReviewCommand ?? CanReviewCommand(ggLog: ggLog),
        _localizeRefsToGit =
            localizeRefsToGit ?? ChangeRefsToGitFeatureBranch(ggLog: ggLog),
        _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog),
        _ggDoCommit = ggDoCommit ?? gg.DoCommit(ggLog: ggLog),
        _ggDoPush = ggDoPush ?? gg.DoPush(ggLog: ggLog),
        _processRunner = processRunner ?? _defaultProcessRunner {
    _addArgs();
  }

  /// Instance of CanReviewCommand
  final CanReviewCommand _canReviewCommand;

  /// Instance of ChangeRefsToGitFeatureBranch
  final ChangeRefsToGitFeatureBranch _localizeRefsToGit;

  /// Instance of SortedProcessingList
  final SortedProcessingList _sortedProcessingList;

  /// Instance of gg DoCommit
  final gg.DoCommit _ggDoCommit;

  /// Instance of gg DoPush
  final gg.DoPush _ggDoPush;

  /// The injected process runner used to execute system processes like
  /// `git merge` and `dart pub upgrade` after localization.
  final ProcessRunner _processRunner;

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

    // Step 1: Detect ticket folder ------------------------------------------
    final String? ticketPath = WorkspaceUtils.detectTicketPath(
      path.absolute(directory.path),
    );
    if (ticketPath == null) {
      ggLog(red('This command must be executed inside a ticket folder.'));
      throw Exception('Not inside a ticket folder');
    }

    final ticketDir = Directory(ticketPath);
    final ticketName = path.basename(ticketDir.path);

    // Step 2: Collect repos in processing order -----------------------------
    final subs = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (subs.isEmpty) {
      ggLog(yellow('⚠️ No repositories found in ticket $ticketName.'));
      return;
    }

    final GgLog taskLog = verbose ? ggLog : <String>[].add;

    // Step 3: Merge origin/main into the current feature branch -------------
    await GgStatusPrinter<void>(
      message: 'Merging origin/main into feature branches',
      ggLog: ggLog,
    ).run(
      () async => _mergeMainIntoRepos(
        ticketName: ticketName,
        subs: subs,
        ggLog: taskLog,
      ),
    );

    // Step 4: Run can review after merging ----------------------------------
    await GgStatusPrinter<void>(
      message: 'Gg Multi can review?',
      ggLog: ggLog,
    ).run(
      () async => _runCanReview(
        ticketDir: ticketDir,
        ggLog: taskLog,
      ),
    );

    // Step 5: Localize, upgrade, commit & push ------------------------------
    await GgStatusPrinter<void>(
      message: 'Setting dependencies to git, committing and pushing',
      ggLog: ggLog,
    ).run(
      () async => _localizeAndCommitAll(
        ticketName: ticketName,
        subs: subs,
        ggLog: taskLog,
      ),
    );
  }

  /// Adds command line arguments for this command.
  void _addArgs() {
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'Show detailed log output.',
      defaultsTo: false,
      negatable: true,
    );
  }

  /// Merges `origin/main` into the current feature branch for all repos.
  Future<void> _mergeMainIntoRepos({
    required String ticketName,
    required List<Node> subs,
    required GgLog ggLog,
  }) async {
    for (final repo in subs) {
      final repoDir = repo.directory;
      final repoName = path.basename(repoDir.path);

      try {
        final result = await _processRunner(
          'git',
          <String>['merge', 'origin/main'],
          workingDirectory: repoDir.path,
        );

        if (result.exitCode != 0) {
          final stderrStr = result.stderr?.toString() ?? '';
          final stdoutStr = result.stdout?.toString() ?? '';
          final errMsg = stderrStr.isNotEmpty ? stderrStr : stdoutStr;
          throw Exception(errMsg);
        }

        ggLog(
          green(
            'Merged main into $repoName for ticket $ticketName.',
          ),
        );
      } catch (e) {
        ggLog(
          red(
            'Failed to merge main into $repoName for ticket '
            '$ticketName: $e',
          ),
        );
        throw Exception(
          'Failed to merge main into some repositories in ticket '
          '$ticketName',
        );
      }
    }
  }

  /// Executes `gg_multi can review` for the given ticket directory.
  Future<void> _runCanReview({
    required Directory ticketDir,
    required GgLog ggLog,
  }) async {
    try {
      await _canReviewCommand.exec(directory: ticketDir, ggLog: ggLog);
    } catch (e) {
      ggLog(red('gg_multi can review failed: $e'));
      throw Exception('gg_multi can review failed');
    }
  }

  /// Performs localization, `dart pub upgrade`, commit
  /// and push for every repository in the ticket.
  Future<void> _localizeAndCommitAll({
    required String ticketName,
    required List<Node> subs,
    required GgLog ggLog,
  }) async {
    for (final repo in subs) {
      final repoDir = repo.directory;
      final repoName = path.basename(repoDir.path);

      // Localize with git feature branch ------------------------------------
      try {
        await _localizeRefsToGit.get(
          directory: repoDir,
          ggLog: ggLog,
          gitRef: ticketName,
        );
        ggLog(green('Localized refs for $repoName'));
        StatusUtils.setStatus(
          repoDir,
          StatusUtils.statusGitLocalized,
          ggLog: ggLog,
        );
      } catch (e) {
        ggLog(
          red(
            'Failed to localize refs to git feature branch for '
            '$repoName: $e',
          ),
        );
        throw Exception(
          'Failed to review some repositories in ticket $ticketName',
        );
      }

      // Refresh dependencies for the detected project type ----------------
      await _refreshDependencies(
        repoDir: repoDir,
        repoName: repoName,
        ticketName: ticketName,
        ggLog: ggLog,
      );

      // Commit ---------------------------------------------------------------
      try {
        await _ggDoCommit.exec(
          directory: repoDir,
          ggLog: ggLog,
          message: 'gg_multi: changed references to git',
          force: true,
        );
        ggLog(green('Committed $repoName'));
      } catch (e) {
        ggLog(red('Failed to commit $repoName: $e'));
        throw Exception(
          'Failed to review some repositories in ticket $ticketName',
        );
      }

      // Push -----------------------------------------------------------------
      try {
        await _ggDoPush.exec(directory: repoDir, ggLog: ggLog);
        ggLog(green('Pushed $repoName'));
      } catch (e) {
        ggLog(red('Failed to push $repoName: $e'));
        throw Exception(
          'Failed to review some repositories in ticket $ticketName',
        );
      }
    }
  }

  /// Refreshes dependencies for [repoDir] based on the detected project
  /// type. Runs `dart pub upgrade` for Dart/Flutter packages and the
  /// equivalent install command for TypeScript packages (npm/yarn/pnpm).
  Future<void> _refreshDependencies({
    required Directory repoDir,
    required String repoName,
    required String ticketName,
    required GgLog ggLog,
  }) async {
    final gg.ProjectType projectType;
    try {
      projectType = gg.detectProjectType(repoDir);
    } catch (_) {
      // Repos without a recognizable manifest are skipped.
      return;
    }

    final String executable;
    final List<String> args;
    switch (projectType) {
      case gg.ProjectType.dart:
      case gg.ProjectType.flutter:
        executable = 'dart';
        args = <String>['pub', 'upgrade'];
      case gg.ProjectType.typescript:
        final pm = gg.detectTypeScriptPackageManager(repoDir);
        executable = pm.executable;
        args = <String>['install'];
    }

    final result = await _processRunner(
      executable,
      args,
      workingDirectory: repoDir.path,
    );
    final cmd = '$executable ${args.join(' ')}';
    if (result.exitCode == 0) {
      ggLog(green('Executed $cmd in $repoName.'));
    } else {
      ggLog(
        red(
          'Failed to execute $cmd in '
          '$repoName: ${result.stderr}',
        ),
      );
      throw Exception(
        'Failed to review some repositories in ticket $ticketName',
      );
    }
  }
}

/// Mock for [DoReviewCommand]
class MockDoReviewCommand extends MockDirCommand<void>
    implements DoReviewCommand {}
