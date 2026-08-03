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

import '../../backend/git_snapshot.dart' as git_snapshot;
import '../../backend/publish_skip_check.dart';
import '../../backend/ticket_json.dart';
import '../../backend/workspace_utils.dart';
import '../../commands/can/review.dart';

/// Typedef for running processes (for injection & tests).
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

/// Default process runner that uses the system's `Process.run`
// coverage:ignore-start
Future<ProcessResult> _defaultProcessRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) =>
    Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: true,
    );
// coverage:ignore-end

/// Thrown when merging `origin/main` into a feature branch ends in conflicts.
///
/// The conflicts are deliberately left in the working tree so the user can
/// resolve them; therefore the review must *not* roll the repositories back
/// when this is thrown.
class MergeConflictException implements Exception {
  /// Constructor
  MergeConflictException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => message;
}

/// Snapshot of a repository's git state taken before the review mutates it.
class _RepoSnapshot {
  _RepoSnapshot({
    required this.directory,
    required this.branch,
    required this.head,
    required this.status,
    this.stash,
  });

  /// The repository directory.
  final Directory directory;

  /// The branch the repository was on.
  final String branch;

  /// The commit hash HEAD pointed to.
  final String head;

  /// The `git status --porcelain` output at snapshot time.
  final String status;

  /// Commit created via `git stash create` holding uncommitted changes,
  /// or null when there were none to preserve.
  final String? stash;
}

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
    ChangeRefsToLocal? localizeRefsToLocal,
    SortedProcessingList? sortedProcessingList,
    gg.DoCommit? ggDoCommit,
    gg.DoPush? ggDoPush,
    gg.CanCommit? ggCanCommit,
    gg.CreatePullRequest? createPullRequest,
    ProcessRunner? processRunner,
  })  : _canReviewCommand = canReviewCommand ?? CanReviewCommand(ggLog: ggLog),
        _localizeRefsToGit =
            localizeRefsToGit ?? ChangeRefsToGitFeatureBranch(ggLog: ggLog),
        _localizeRefsToLocal =
            localizeRefsToLocal ?? ChangeRefsToLocal(ggLog: ggLog),
        _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog),
        _ggDoCommit = ggDoCommit ?? gg.DoCommit(ggLog: ggLog),
        _ggDoPush = ggDoPush ?? gg.DoPush(ggLog: ggLog),
        _ggCanCommit = ggCanCommit ?? gg.CanCommit(ggLog: ggLog),
        _createPullRequest =
            createPullRequest ?? gg.CreatePullRequest(ggLog: ggLog),
        _processRunner = processRunner ?? _defaultProcessRunner {
    _addArgs();
  }

  /// Instance of CanReviewCommand
  final CanReviewCommand _canReviewCommand;

  /// Instance of ChangeRefsToGitFeatureBranch
  final ChangeRefsToGitFeatureBranch _localizeRefsToGit;

  /// Sets refs back to local path dependencies, used by `--abort`.
  final ChangeRefsToLocal _localizeRefsToLocal;

  /// Instance of SortedProcessingList
  final SortedProcessingList _sortedProcessingList;

  /// Instance of gg DoCommit
  final gg.DoCommit _ggDoCommit;

  /// Instance of gg DoPush
  final gg.DoPush _ggDoPush;

  /// Instance of gg CanCommit, used to verify a repository still passes the
  /// commit checks after `origin/main` was merged into it.
  final gg.CanCommit _ggCanCommit;

  /// Opens the pull request of a repository's feature branch — without the
  /// auto-merge flag, which only `do publish` adds.
  final gg.CreatePullRequest _createPullRequest;

  /// The injected process runner used to execute system processes like
  /// `git merge` and `dart pub upgrade` after localization.
  final ProcessRunner _processRunner;

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    bool? verbose,
    bool? abort,
  }) =>
      get(
        directory: directory,
        ggLog: ggLog,
        verbose: verbose,
        abort: abort,
      );

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    bool? verbose,
    bool? abort,
  }) async {
    verbose ??= argResults?['verbose'] as bool? ?? false;
    abort ??= argResults?['abort'] as bool? ?? false;

    // `--abort` undoes what a previous review prepared, so it must branch off
    // before any of the review steps below run.
    if (abort) {
      return _abort(
        directory: directory,
        ggLog: ggLog,
        verbose: verbose,
      );
    }

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
      ggLog(yellow('⚠️ No repos in this ticket'));
      return;
    }

    final GgLog taskLog = verbose ? ggLog : <String>[].add;

    // Routine progress output is silenced unless --verbose is set, but errors
    // are *always* reported through the real log. Otherwise a failure deep in
    // one of the steps below would only surface as a generic
    // "Failed to review in: <repo>" with the actual cause swallowed by the
    // quiet task log.
    final GgLog errorLog = ggLog;

    // Step 3: Save the state of every repo so a failure can restore it ------
    late final List<_RepoSnapshot> snapshots;
    await GgStatusPrinter<void>(
      message: 'Saving the state before the review',
      ggLog: ggLog,
    ).run(
      () async => snapshots = await _saveState(subs: subs, ggLog: taskLog),
    );

    final pushedRepos = <String>[];

    try {
      // Step 4: Merge origin/main into the current feature branch -----------
      await GgStatusPrinter<void>(
        message: 'Merging origin/main into feature branches',
        ggLog: ggLog,
      ).run(
        () async => _mergeMainIntoRepos(
          ticketName: ticketName,
          subs: subs,
          ggLog: taskLog,
          errorLog: errorLog,
        ),
      );

      // Step 5: Run can review after merging ---------------------------------
      await GgStatusPrinter<void>(
        message: 'Gg Multi can review?',
        ggLog: ggLog,
      ).run(
        () async => _runCanReview(
          ticketDir: ticketDir,
          ggLog: taskLog,
          errorLog: errorLog,
        ),
      );

      // Step 6: Localize, upgrade, commit & push -----------------------------
      await GgStatusPrinter<void>(
        message: 'Setting dependencies to git, committing and pushing',
        ggLog: ggLog,
      ).run(
        () async => _localizeAndCommitAll(
          ticketName: ticketName,
          subs: subs,
          pushedRepos: pushedRepos,
          ggLog: taskLog,
          errorLog: errorLog,
        ),
      );
    } on MergeConflictException {
      // The conflicting merge must survive: the user resolves it in the
      // working tree and commits. A rollback would throw that work away.
      rethrow;
    } catch (_) {
      // Bring the repos back to the state saved above, then surface the
      // review failure as the primary error.
      await _restoreStateOnFailure(
        snapshots: snapshots,
        pushedRepos: pushedRepos,
        ggLog: ggLog,
        taskLog: taskLog,
        errorLog: errorLog,
      );
      rethrow;
    }

    // Step 7: Open a pull request per repo and print its url ---------------
    // Everything is on the remote now, so the work can be reviewed right
    // away instead of only when it is published. This is *outside* the
    // rollback: the review itself has succeeded, and a provider that cannot
    // be reached must not undo it.
    await _createPullRequests(
      ticketDir: ticketDir,
      ticketName: ticketName,
      subs: subs,
      ggLog: ggLog,
      taskLog: taskLog,
    );
  }

  /// Opens — or reuses — the pull request of every ticket repo and prints its
  /// url, so a reviewer can be pointed at it immediately.
  ///
  /// The pull requests are created **without** the auto-merge flag: the
  /// ticket is under review, not ready to land. `gg do publish` reuses them
  /// and sets auto-merge when the release is complete.
  ///
  /// A repo whose pull request cannot be opened does **not** fail the review:
  /// merging main, the checks and the push have all succeeded already, and
  /// the branch is on the remote either way. The reason is reported and the
  /// remaining repos are still processed.
  Future<void> _createPullRequests({
    required Directory ticketDir,
    required String ticketName,
    required List<Node> subs,
    required GgLog ggLog,
    required GgLog taskLog,
  }) async {
    // The ticket description is what the ticket is about, so it is the
    // natural pull-request title — the same default `do commit` uses for its
    // commit message. Without one the ticket (and branch) name is left.
    final message = readTicketDescription(ticketDir) ?? ticketName;

    final urls = <String, String>{};
    final failures = <String, String>{};

    // Collected first, printed afterwards: the status printer overwrites its
    // own line, so nothing may be logged while it runs.
    await GgStatusPrinter<void>(
      message: 'Creating pull requests',
      ggLog: ggLog,
    ).run(() async {
      for (final repo in subs) {
        final repoDir = repo.directory;
        final repoName = path.basename(repoDir.path);
        try {
          final url = await _createPullRequest.get(
            directory: repoDir,
            ggLog: taskLog,
            message: message,
          );
          if (url != null) {
            urls[repoName] = url;
          }
        } catch (e) {
          failures[repoName] = e.toString();
        }
      }
    });

    if (urls.isNotEmpty) {
      ggLog(green('Pull requests:'));
      for (final entry in urls.entries) {
        ggLog(' - ${entry.key}: ${blue(entry.value)}');
      }
    }

    for (final entry in failures.entries) {
      ggLog(
        yellow(
          'No pull request for ${entry.key}: ${entry.value}. '
          'Create it manually, or run "gg do review" again.',
        ),
      );
    }
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

    argParser.addFlag(
      'abort',
      help: 'Set dependencies back to local paths and commit.',
      defaultsTo: false,
      negatable: false,
    );
  }

  /// Merges `origin/main` into the current feature branch for all repos.
  Future<void> _mergeMainIntoRepos({
    required String ticketName,
    required List<Node> subs,
    required GgLog ggLog,
    required GgLog errorLog,
  }) async {
    for (final repo in subs) {
      final repoDir = repo.directory;
      final repoName = path.basename(repoDir.path);

      final String headBeforeMerge;
      try {
        headBeforeMerge = await _gitHead(repoDir);

        // Make sure `origin/main` points to the remote's current main. Without
        // this the merge below would silently merge a stale main.
        await _runGit(
          <String>['fetch', 'origin', 'main'],
          repoDir: repoDir,
          allowFailure: true,
        );

        final result = await _processRunner(
          'git',
          <String>['merge', 'origin/main'],
          workingDirectory: repoDir.path,
        );

        if (result.exitCode != 0) {
          final stderrStr = result.stderr?.toString() ?? '';
          final stdoutStr = result.stdout?.toString() ?? '';
          final errMsg = stderrStr.isNotEmpty ? stderrStr : stdoutStr;

          // Conflicts are not an error the review can fix — the merge stays in
          // the working tree and the user resolves it.
          final conflicts = await _conflictingFiles(repoDir);
          if (conflicts.isNotEmpty) {
            _reportMergeConflicts(
              repoName: repoName,
              conflicts: conflicts,
              errorLog: errorLog,
            );
            throw MergeConflictException(
              'Merging origin/main into $repoName produced conflicts. '
              'Resolve them, then run: gg do commit -m"Merge main" --no-log',
            );
          }

          throw Exception(errMsg);
        }

        ggLog(
          green(
            'Merged main into $repoName for ticket $ticketName.',
          ),
        );
      } on MergeConflictException {
        rethrow;
      } catch (e) {
        errorLog(
          red(
            'Failed to merge main into $repoName for ticket '
            '$ticketName: $e',
          ),
        );
        throw Exception('Failed to merge main in: $repoName: $e');
      }

      // If the merge actually moved HEAD (i.e. it was not a no-op), re-verify
      // the merged state with `gg can commit`. A merge can silently corrupt a
      // manifest (e.g. a duplicated `version:` key) without a conflict, and we
      // must not localize/commit/push such a broken state.
      final headAfterMerge = await _gitHead(repoDir);
      if (headAfterMerge != headBeforeMerge) {
        try {
          await _ggCanCommit.exec(
            directory: repoDir,
            ggLog: ggLog,
            saveState: false,
          );
          ggLog(
            green('Verified $repoName still passes "gg can commit" after '
                'merging main.'),
          );
        } catch (e) {
          errorLog(
            red(
              'Merging main into $repoName broke "gg can commit": $e',
            ),
          );
          throw Exception(
            'Failed to merge main in: $repoName (merged state no longer '
            'passes "gg can commit" — the merge likely corrupted a file. '
            'The repo is rolled back to before the review; to fix, merge '
            'origin/main manually ("git merge origin/main"), resolve the '
            'problem, then re-run): $e',
          );
        }
      }
    }
  }

  /// Returns the files [repoDir] currently has merge conflicts in.
  Future<List<String>> _conflictingFiles(Directory repoDir) async {
    final out = await _runGit(
      <String>['diff', '--name-only', '--diff-filter=U'],
      repoDir: repoDir,
      allowFailure: true,
    );
    return out
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  /// Tells the user which files conflict and how to continue.
  void _reportMergeConflicts({
    required String repoName,
    required List<String> conflicts,
    required GgLog errorLog,
  }) {
    errorLog(yellow('Please resolve merge conflicts:'));
    for (final file in conflicts) {
      errorLog(' - ${blue('$repoName/$file')}');
    }
    errorLog(
      yellow('After merging execute: ') +
          blue('gg do commit -m"Merge main" --no-log'),
    );
  }

  /// Returns the current `HEAD` commit hash of [repoDir].
  Future<String> _gitHead(Directory repoDir) =>
      _runGit(<String>['rev-parse', 'HEAD'], repoDir: repoDir);

  /// Runs git with [args] in [repoDir] and returns the trimmed stdout.
  /// Delegates to the shared [git_snapshot.runGit] so `do review` and
  /// `do publish` use one git runner. See there for [allowFailure].
  Future<String> _runGit(
    List<String> args, {
    required Directory repoDir,
    bool allowFailure = false,
  }) =>
      git_snapshot.runGit(
        _processRunner,
        args,
        repoDir: repoDir,
        allowFailure: allowFailure,
      );

  /// Records branch, HEAD and working-tree state of every repository so
  /// [_restoreState] can bring the repos back when the review fails.
  Future<List<_RepoSnapshot>> _saveState({
    required List<Node> subs,
    required GgLog ggLog,
  }) async {
    final snapshots = <_RepoSnapshot>[];
    for (final repo in subs) {
      final repoDir = repo.directory;
      final repoName = path.basename(repoDir.path);
      try {
        final head = await _gitHead(repoDir);
        var branch = await _runGit(
          <String>['rev-parse', '--abbrev-ref', 'HEAD'],
          repoDir: repoDir,
        );
        if (branch == 'HEAD') {
          // Detached HEAD: `rev-parse --abbrev-ref` prints the literal string
          // "HEAD". Store the commit so restore re-detaches at it instead of
          // running the no-op `git checkout HEAD`.
          branch = head;
        }
        final status = await _runGit(
          <String>['status', '--porcelain'],
          repoDir: repoDir,
        );
        final stash =
            await _captureUncommitted(repoDir: repoDir, status: status);
        snapshots.add(
          _RepoSnapshot(
            directory: repoDir,
            branch: branch,
            head: head,
            status: status,
            stash: stash,
          ),
        );
        ggLog(green('Saved state of $repoName'));
      } catch (e) {
        throw Exception(
          'Failed to save the state of $repoName before the review — '
          'nothing was changed: $e',
        );
      }
    }
    return snapshots;
  }

  /// Captures the uncommitted changes of [repoDir] in a dangling stash commit,
  /// leaving the working tree unchanged. Delegates to the shared
  /// [git_snapshot.captureUncommitted]; returns the stash hash or null.
  Future<String?> _captureUncommitted({
    required Directory repoDir,
    required String status,
  }) =>
      git_snapshot.captureUncommitted(
        _processRunner,
        repoDir: repoDir,
        status: status,
      );

  /// Restores the pre-review state after a failure and reports repos whose
  /// pushes cannot be rolled back. Never throws — the review failure that
  /// triggered the restore must stay the primary error.
  Future<void> _restoreStateOnFailure({
    required List<_RepoSnapshot> snapshots,
    required List<String> pushedRepos,
    required GgLog ggLog,
    required GgLog taskLog,
    required GgLog errorLog,
  }) async {
    try {
      await GgStatusPrinter<void>(
        message: 'Restoring the state before the review',
        ggLog: ggLog,
      ).run(
        () async => _restoreState(
          snapshots: snapshots,
          pushedRepos: pushedRepos,
          ggLog: taskLog,
        ),
      );
    } catch (e) {
      errorLog(
        red(
          'Restoring the state before the review failed — '
          'restore it manually: $e',
        ),
      );
    }
    if (pushedRepos.isNotEmpty) {
      errorLog(
        yellow(
          'Already pushed and not rolled back: ${pushedRepos.join(', ')}. '
          'The next "gg do review" integrates these pushes automatically.',
        ),
      );
    }
  }

  /// Brings every changed repository back to its snapshot: ends a possibly
  /// running merge/rebase, checks out the original branch, resets to the
  /// original HEAD and re-applies stashed uncommitted changes.
  ///
  /// Repos in [pushedRepos] are left untouched: their review commit already
  /// reached the remote, so resetting the local branch behind it would desync
  /// the two and make the next run rebase a fresh commit onto the pushed one.
  /// Leaving them keeps local and remote in sync; the push warning covers them
  /// and the next run's integrate step builds on top.
  Future<void> _restoreState({
    required List<_RepoSnapshot> snapshots,
    required List<String> pushedRepos,
    required GgLog ggLog,
  }) async {
    final failures = <String>[];
    for (final s in snapshots) {
      final repoName = path.basename(s.directory.path);
      if (pushedRepos.contains(repoName)) {
        ggLog('Kept already-pushed repo: $repoName');
        continue;
      }
      try {
        final headNow = await _gitHead(s.directory);
        final statusNow = await _runGit(
          <String>['status', '--porcelain'],
          repoDir: s.directory,
        );
        if (headNow == s.head && statusNow == s.status) {
          ggLog('Unchanged: $repoName');
          continue;
        }
        // A failed `git merge`/`git pull --rebase` may have left a merge or
        // rebase in progress; ending them is a no-op otherwise.
        await _runGit(
          <String>['merge', '--abort'],
          repoDir: s.directory,
          allowFailure: true,
        );
        await _runGit(
          <String>['rebase', '--abort'],
          repoDir: s.directory,
          allowFailure: true,
        );
        final branchNow = await _runGit(
          <String>['rev-parse', '--abbrev-ref', 'HEAD'],
          repoDir: s.directory,
        );
        if (branchNow != s.branch) {
          await _runGit(
            <String>['checkout', s.branch],
            repoDir: s.directory,
          );
        }
        await _runGit(
          <String>['reset', '--hard', s.head],
          repoDir: s.directory,
        );
        if (s.stash != null) {
          await _runGit(
            <String>['stash', 'apply', '--index', s.stash!],
            repoDir: s.directory,
          );
        }
        ggLog(green('Restored the state before the review in $repoName'));
      } catch (e) {
        final manual = StringBuffer(
          'git checkout ${s.branch} && git reset --hard ${s.head}',
        );
        if (s.stash != null) {
          manual.write(' && git stash apply --index ${s.stash}');
        }
        failures.add('$repoName (restore with: $manual): $e');
      }
    }
    if (failures.isNotEmpty) {
      throw Exception(
        'Could not restore the state before the review in:\n'
        '${failures.map((f) => ' - $f').join('\n')}',
      );
    }
  }

  /// Executes `gg_multi can review` for the given ticket directory.
  Future<void> _runCanReview({
    required Directory ticketDir,
    required GgLog ggLog,
    required GgLog errorLog,
  }) async {
    try {
      await _canReviewCommand.exec(directory: ticketDir, ggLog: ggLog);
    } catch (e) {
      errorLog(red('gg_multi can review failed: $e'));
      throw Exception('gg_multi can review failed: $e');
    }
  }

  /// Performs localization, `dart pub upgrade`, commit
  /// and push for every repository in the ticket.
  ///
  /// Successfully pushed repos are appended to [pushedRepos] so a later
  /// rollback can report the pushes it cannot undo.
  Future<void> _localizeAndCommitAll({
    required String ticketName,
    required List<Node> subs,
    required List<String> pushedRepos,
    required GgLog ggLog,
    required GgLog errorLog,
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
      } catch (e) {
        errorLog(
          red(
            'Failed to localize refs to git feature branch for '
            '$repoName: $e',
          ),
        );
        throw Exception(
          'Failed to review in: $repoName '
          '(localize refs to git failed: $e)',
        );
      }

      // Refresh dependencies for the detected project type ----------------
      await _refreshDependencies(
        repoDir: repoDir,
        repoName: repoName,
        ticketName: ticketName,
        ggLog: ggLog,
        errorLog: errorLog,
      );

      // Commit ---------------------------------------------------------------
      try {
        await _ggDoCommit.exec(
          directory: repoDir,
          ggLog: ggLog,
          message: '#gg: changed references to git',
          force: true,
          // Bookkeeping, not a change of the package — keep it out of
          // CHANGELOG.md (»gg do commit --no-log«).
          updateChangeLog: false,
        );
        ggLog(green('Committed $repoName'));
      } catch (e) {
        errorLog(red('Failed to commit $repoName: $e'));
        throw Exception('Failed to review in: $repoName (commit failed: $e)');
      }

      // Integrate remote feature-branch commits before pushing --------------
      await _integrateRemoteBranch(
        repoDir: repoDir,
        repoName: repoName,
        branch: ticketName,
        ggLog: ggLog,
        errorLog: errorLog,
      );

      // Push -----------------------------------------------------------------
      try {
        await _ggDoPush.exec(directory: repoDir, ggLog: ggLog);
        pushedRepos.add(repoName);
        ggLog(green('Pushed $repoName'));
      } catch (e) {
        errorLog(red('Failed to push $repoName: $e'));
        throw Exception('Failed to review in: $repoName (push failed: $e)');
      }
    }
  }

  /// Integrates commits that already exist on the remote feature branch into
  /// the local branch before pushing.
  ///
  /// A feature branch can advance on the remote (e.g. from an earlier
  /// `gg do review` run) while the local branch's history was rewritten by the
  /// forced review commit. Without this, the subsequent push fails with a
  /// non-fast-forward rejection. We integrate via `git pull --rebase` so the
  /// local review commit is replayed on top of the remote state. On a genuine
  /// rebase conflict we abort and throw an actionable error — we never
  /// force-push.
  ///
  /// The one exception is an **obsolete** remote branch — see
  /// [_remoteBranchIsObsolete]: rebasing onto it would replay the whole main
  /// branch onto a tip that predates it and conflict on commits that are long
  /// merged. Such a branch is overwritten with `--force-with-lease` instead.
  Future<void> _integrateRemoteBranch({
    required Directory repoDir,
    required String repoName,
    required String branch,
    required GgLog ggLog,
    required GgLog errorLog,
  }) async {
    // Nothing to integrate if the branch does not exist on the remote yet —
    // the push will simply create it.
    final remoteBranch = await _processRunner(
      'git',
      <String>['ls-remote', '--heads', 'origin', branch],
      workingDirectory: repoDir.path,
    );
    final remoteHasBranch = remoteBranch.exitCode == 0 &&
        (remoteBranch.stdout?.toString().trim().isNotEmpty ?? false);
    if (!remoteHasBranch) {
      return;
    }

    // The hash the remote branch points to right now. It is both the input of
    // the obsolete-branch analysis and the lease of the force push below, so
    // a branch somebody moved in between is never overwritten.
    final remoteHead =
        remoteBranch.stdout!.toString().trim().split(RegExp(r'\s')).first;

    // Make the remote commits available locally — the analysis walks them.
    await _runGit(
      <String>['fetch', 'origin', branch],
      repoDir: repoDir,
      allowFailure: true,
    );

    // Already contained in the local history — nothing to integrate. Checked
    // first because it is the cheap and by far most common case.
    if (await _isAncestor(remoteHead, 'HEAD', repoDir: repoDir)) {
      return;
    }

    if (await _remoteBranchIsObsolete(
      repoDir: repoDir,
      remoteHead: remoteHead,
    )) {
      await _replaceObsoleteRemoteBranch(
        repoDir: repoDir,
        repoName: repoName,
        branch: branch,
        remoteHead: remoteHead,
        ggLog: ggLog,
        errorLog: errorLog,
      );
      return;
    }

    final pull = await _processRunner(
      'git',
      <String>['pull', '--rebase', 'origin', branch],
      workingDirectory: repoDir.path,
    );
    if (pull.exitCode != 0) {
      // Leave the repository in a clean (non-rebasing) state for the user.
      await _processRunner(
        'git',
        <String>['rebase', '--abort'],
        workingDirectory: repoDir.path,
      );
      final stderrStr = pull.stderr?.toString() ?? '';
      errorLog(
        red(
          'Failed to integrate origin/$branch into $repoName before '
          'push: $stderrStr',
        ),
      );
      throw Exception(
        'Failed to review in: $repoName (could not rebase onto '
        'origin/$branch before pushing — resolve the divergence manually, '
        'e.g. "git pull --rebase origin $branch", then re-run): $stderrStr',
      );
    }
    ggLog(green('Integrated origin/$branch into $repoName before push'));
  }

  /// Whether `origin/<branch>` is a leftover of a ticket that was **already
  /// merged**, and therefore must not be rebased onto.
  ///
  /// A ticket branch that was squash-merged into `main` keeps existing on the
  /// remote when the provider did not delete it. Re-using the ticket (a fresh
  /// `gg do add`/`do checkout`) recreates
  /// the branch locally *from the current main* — which now contains the
  /// squashed ticket plus everything merged after it. `git pull --rebase`
  /// then replays all of those commits onto a tip that predates them and dies
  /// in conflicts on foreign, long-merged work.
  ///
  /// The branch counts as obsolete when every commit it holds on top of the
  /// local history is either
  ///
  /// * already contained in `origin/main` **by content** (`git cherry`
  ///   compares patch ids, so a squash merge is recognized), or
  /// * one of gg's own bookkeeping commits (`#gg: …`, or a legacy subject) —
  ///   the ref-flipping commits of an earlier review carry no work.
  ///
  /// Anything else — a real commit somebody pushed to the branch and that is
  /// not on main — makes this return false, so the regular rebase runs and
  /// no work can be lost.
  Future<bool> _remoteBranchIsObsolete({
    required Directory repoDir,
    required String remoteHead,
  }) async {
    // The local branch must be up to date with main — otherwise this is an
    // ordinary divergence and not the "branch rebuilt from main" situation.
    // `origin/main` is current: the review fetched and merged it in step 4.
    // A repository without it fails this check and is never treated as
    // obsolete.
    if (!await _isAncestor('origin/main', 'HEAD', repoDir: repoDir)) {
      return false;
    }

    // Commits of the remote branch that are already on main by content.
    final cherry = await _runGit(
      <String>['cherry', 'origin/main', remoteHead],
      repoDir: repoDir,
      allowFailure: true,
    );
    final onMainByContent = <String>{
      for (final line in cherry.split('\n'))
        if (line.trim().startsWith('- ')) line.trim().substring(2).trim(),
    };

    // Everything the remote branch adds to the local history.
    final extra = await _runGit(
      <String>['log', '--format=%H%x09%s', remoteHead, '--not', 'HEAD'],
      repoDir: repoDir,
      allowFailure: true,
    );
    if (extra.isEmpty) {
      return false; // Nothing to explain — the rebase is a no-op anyway.
    }

    for (final line in extra.split('\n')) {
      final entry = line.trim();
      if (entry.isEmpty) {
        continue;
      }
      final tab = entry.indexOf('\t');
      final hash = tab < 0 ? entry : entry.substring(0, tab);
      final subject = tab < 0 ? '' : entry.substring(tab + 1).trim();

      if (onMainByContent.contains(hash)) {
        continue;
      }
      if (subject.startsWith(PublishSkipCheck.ggCommitPrefix) ||
          PublishSkipCheck.legacyGgCommitMessages.contains(subject)) {
        continue;
      }
      return false;
    }

    return true;
  }

  /// Overwrites an obsolete `origin/<branch>` (see [_remoteBranchIsObsolete])
  /// with the local state, so the following push is a fast-forward.
  ///
  /// The lease pins [remoteHead] — the hash the obsolete-branch analysis was
  /// made from — so a branch that moved on the remote in the meantime is
  /// rejected instead of overwritten.
  Future<void> _replaceObsoleteRemoteBranch({
    required Directory repoDir,
    required String repoName,
    required String branch,
    required String remoteHead,
    required GgLog ggLog,
    required GgLog errorLog,
  }) async {
    final push = await _processRunner(
      'git',
      <String>[
        'push',
        '--force-with-lease=$branch:$remoteHead',
        '--set-upstream',
        'origin',
        'HEAD:refs/heads/$branch',
      ],
      workingDirectory: repoDir.path,
    );

    if (push.exitCode != 0) {
      final stderrStr = push.stderr?.toString() ?? '';
      errorLog(
        red(
          'Failed to replace the obsolete branch origin/$branch of '
          '$repoName: $stderrStr',
        ),
      );
      throw Exception(
        'Failed to review in: $repoName (origin/$branch is a leftover of an '
        'already merged ticket, but replacing it failed — delete it manually '
        'with "git push origin --delete $branch", then re-run): $stderrStr',
      );
    }

    ggLog(
      yellow(
        'origin/$branch of $repoName was a leftover of an already merged '
        'ticket — replaced it with the current branch instead of rebasing '
        'onto it.',
      ),
    );
  }

  /// Whether [ancestor] is an ancestor of [descendant] in [repoDir].
  Future<bool> _isAncestor(
    String ancestor,
    String descendant, {
    required Directory repoDir,
  }) async {
    final result = await _processRunner(
      'git',
      <String>['merge-base', '--is-ancestor', ancestor, descendant],
      workingDirectory: repoDir.path,
    );
    return result.exitCode == 0;
  }

  /// Refreshes dependencies for [repoDir] based on the detected project
  /// type. Runs `dart pub upgrade` for Dart/Flutter packages and the
  /// equivalent install command for TypeScript packages (npm/yarn/pnpm).
  /// Reverts the review preparation: sets the refs of every ticket repo back
  /// to local paths and commits the change.
  Future<void> _abort({
    required Directory directory,
    required GgLog ggLog,
    required bool verbose,
  }) async {
    final String? ticketPath = WorkspaceUtils.detectTicketPath(
      path.absolute(directory.path),
    );
    if (ticketPath == null) {
      ggLog(red('This command must be executed inside a ticket folder.'));
      throw Exception('Not inside a ticket folder');
    }

    final ticketDir = Directory(ticketPath);
    final ticketName = path.basename(ticketDir.path);

    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (nodes.isEmpty) {
      ggLog(yellow('⚠️ No repos in this ticket'));
      return;
    }

    final GgLog taskLog = verbose ? ggLog : <String>[].add;

    await GgStatusPrinter<void>(
      message: 'Setting dependencies back to local paths and committing',
      ggLog: ggLog,
    ).run(
      () async => _relocalizeAndCommitAll(
        ticketName: ticketName,
        nodes: nodes,
        ggLog: taskLog,
      ),
    );
  }

  /// Re-localizes all repos and commits the changes without pushing.
  Future<void> _relocalizeAndCommitAll({
    required String ticketName,
    required List<Node> nodes,
    required GgLog ggLog,
  }) async {
    for (final node in nodes) {
      final repoDir = node.directory;
      final repoName = path.basename(repoDir.path);

      try {
        await _localizeRefsToLocal.get(directory: repoDir, ggLog: ggLog);
        ggLog(green('Localized refs to local paths for $repoName'));
      } catch (e) {
        ggLog(
          red(
            'Failed to localize refs to local paths for $repoName: $e',
          ),
        );
        throw Exception('Failed to cancel review in: $repoName');
      }

      // node_modules will be stale after rewriting package.json — refresh.
      await _refreshTypeScriptDependencies(
        repoDir: repoDir,
        repoName: repoName,
        ticketName: ticketName,
        ggLog: ggLog,
      );

      try {
        await _ggDoCommit.exec(
          directory: repoDir,
          ggLog: ggLog,
          message: '#gg: changed references to local',
          force: true,
          // Bookkeeping, not a change of the package — keep it out of
          // CHANGELOG.md (»gg do commit --no-log«).
          updateChangeLog: false,
        );
        ggLog(green('Committed $repoName'));
      } catch (e) {
        ggLog(red('Failed to commit $repoName: $e'));
        throw Exception('Failed to cancel review in: $repoName');
      }
    }

    ggLog('✅ All repos re-localized and committed');
  }

  /// Runs the package manager's install command for TypeScript projects so
  /// that node_modules reflects the freshly-rewritten local path
  /// dependencies. Dart packages are skipped because pub resolves lazily.
  Future<void> _refreshTypeScriptDependencies({
    required Directory repoDir,
    required String repoName,
    required String ticketName,
    required GgLog ggLog,
  }) async {
    final gg.ProjectType projectType;
    try {
      // Cross-language bridge repos are refreshed via their TypeScript package
      // manager here, symmetrically to the review's _refreshDependencies, so an
      // aborted review leaves node_modules consistent.
      projectType = gg.checkProjectType(repoDir);
    } catch (_) {
      return;
    }
    if (projectType != gg.ProjectType.typescript) return;

    final pm = gg.detectTypeScriptPackageManager(repoDir);
    final result = await _processRunner(
      pm.executable,
      <String>['install'],
      workingDirectory: repoDir.path,
    );
    final cmd = '${pm.executable} install';
    if (result.exitCode == 0) {
      ggLog(green('Executed $cmd in $repoName.'));
    } else {
      ggLog(
        red(
          'Failed to execute $cmd in $repoName: ${result.stderr}',
        ),
      );
      throw Exception('Failed to cancel review in: $repoName');
    }
  }

  Future<void> _refreshDependencies({
    required Directory repoDir,
    required String repoName,
    required String ticketName,
    required GgLog ggLog,
    required GgLog errorLog,
  }) async {
    // Cross-language bridge repos (pubspec.yaml + package.json + tsconfig)
    // are refreshed via their TypeScript package manager, like a pure
    // TypeScript repo. `checkProjectType` encodes that bridge → TypeScript
    // rule in one place.
    final projectType = gg.checkProjectType(repoDir);

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
      case gg.ProjectType.none:
        // Repos without a manifest have no dependencies to refresh.
        return;
    }

    // Localizing to git feature branches turns dependencies between ticket
    // repos into git references, so a git repo ends up depending on another
    // git repo. pnpm 11's blockExoticSubdeps rejects such exotic
    // subdependencies, and it can only be disabled via env var (not a CLI
    // flag) — so mirror do/publish and force it off for the TypeScript install.
    final Map<String, String>? envOverride =
        projectType == gg.ProjectType.typescript
            ? <String, String>{
                ...Platform.environment,
                'PNPM_CONFIG_BLOCK_EXOTIC_SUBDEPS': 'false',
              }
            : null;

    Future<void> runStep(
      String exe,
      List<String> stepArgs,
      Map<String, String>? env,
    ) async {
      final result = await _processRunner(
        exe,
        stepArgs,
        workingDirectory: repoDir.path,
        environment: env,
      );
      final cmd = '$exe ${stepArgs.join(' ')}';
      if (result.exitCode == 0) {
        ggLog(green('Executed $cmd in $repoName.'));
      } else {
        // pnpm prints its errors to stdout, so fall back to stdout when stderr
        // is empty — otherwise the real cause is swallowed ("... failed: ").
        final err = result.stderr?.toString().trim() ?? '';
        final out = result.stdout?.toString().trim() ?? '';
        final detail = err.isNotEmpty ? err : out;
        errorLog(
          red(
            'Failed to execute $cmd in '
            '$repoName: $detail',
          ),
        );
        throw Exception(
          'Failed to review in: $repoName ($cmd failed: $detail)',
        );
      }
    }

    await runStep(executable, args, envOverride);

    // A cross-language bridge also carries a Dart manifest. checkProjectType
    // reports it as TypeScript, so the switch above only refreshed the
    // TypeScript package manager — refresh the Dart side too, so the rewritten
    // references are reflected in pubspec.lock as well. (The pnpm env override
    // is irrelevant to `dart pub upgrade`.)
    if (gg.isBridgeProject(repoDir)) {
      await runStep('dart', <String>['pub', 'upgrade'], null);
    }
  }
}

/// Mock for [DoReviewCommand]
class MockDoReviewCommand extends MockDirCommand<void>
    implements DoReviewCommand {}
