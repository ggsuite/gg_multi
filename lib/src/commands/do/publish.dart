// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_lang/gg_lang.dart' as gg_lang;
// ignore: lines_longer_than_80_chars
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_localize_refs/gg_localize_refs.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;

import '../../backend/ensure_in_registry.dart';
import '../../backend/git_snapshot.dart' as git_snapshot;
import '../../backend/npm_registry_checker.dart';
import '../../backend/pub_dev_checker.dart';
import '../../backend/publish_skip_check.dart';
import '../../backend/trash.dart';
import '../../backend/workspace_utils.dart';
import '../../commands/can/publish.dart';
import 'configure_publish.dart' show DoConfigurePublishCommand;
import 'review.dart';

/// Typedef for running processes (for injection & tests).
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

/// Snapshot of a repository's state taken before its publish starts.
class _RepoPublishSnapshot {
  _RepoPublishSnapshot({
    required this.directory,
    required this.branch,
    required this.head,
    required this.status,
    required this.version,
    required this.mainBranch,
    required this.mainHead,
    required this.remoteMainHead,
    required this.remoteFeatureHead,
    required this.tags,
    this.stash,
  });

  /// The repository directory.
  final Directory directory;

  /// The branch the repository was on (usually the ticket feature branch).
  final String branch;

  /// The commit hash HEAD pointed to.
  final String head;

  /// The `git status --porcelain` output at snapshot time.
  final String status;

  /// The package version at snapshot time (null when unreadable).
  final String? version;

  /// The name of the default branch (`main`/`master`), null when absent.
  final String? mainBranch;

  /// The local commit hash of [mainBranch], null when absent.
  final String? mainHead;

  /// The remote commit hash of [mainBranch], null when unreachable/absent.
  final String? remoteMainHead;

  /// The remote commit hash of the feature branch, null when the snapshot was
  /// taken in detached HEAD or the branch is absent/unreachable. Used to skip
  /// resetting a feature branch whose commit already reached the remote.
  final String? remoteFeatureHead;

  /// All local tags at snapshot time.
  final Set<String> tags;

  /// Commit created via `git stash create` holding uncommitted changes,
  /// or null when there were none to preserve.
  final String? stash;
}

/// Command to publish all repos in the ticket.
///
/// With `--merge-only` ([mergeOnly]) the exact same flow runs, minus the two
/// steps that release the packages: nothing is uploaded to a package registry
/// and no version tags are created. Because the merged state is therefore
/// never resolvable against a registry, that mode refuses to run while any
/// repository of the ticket still redirects a dependency to a local working
/// copy (a `pubspec_overrides.yaml` with a `path:` override); such a ticket
/// has to be published. `--force` merges anyway.
///
/// Since a merge leaves no tag behind, the work it puts on the main branch is
/// unreleased. `PublishSkipCheck` therefore compares against the last **tag**,
/// not against the main branch — so the next `gg do publish` still sees those
/// commits instead of mistaking the repository for unchanged.
///
/// There is no `gg do merge` command anymore — it was folded into this one, so
/// there is exactly one flow.
/// Flags, in more detail than their one-line help texts carry:
/// - `--message` is the default merge message and only takes effect when the
///   configuration is written interactively (a fresh run or `--restart`); it
///   takes precedence over the ticket description and is ignored once a
///   configuration exists or was supplied via `--config`.
/// - `--config` is resolved as given (relative to the CWD), then below the
///   ticket folder. The file is only read — progress is written to the
///   runtime `.gg/gg-publish.json`.
/// - `--no-delete-remote-branch` keeps the remote feature branches; the local
///   folders are moved to the trash either way, because the ticket folder is
///   removed regardless.
/// - `--no-pr` performs a local merge instead of waiting for the provider.
/// - `--continue` reuses `.gg/gg-publish.json` and skips the repos already
///   published.
/// - `--publish-unchanged` releases every repo; by default a repo without
///   manual changes and without an out-of-range dependency bump is skipped.
/// - `--restart` discards the saved configuration *and* the recorded
///   progress, so the publish starts from the beginning.
class DoPublishCommand extends DirCommand<void> {
  /// Constructor
  DoPublishCommand({
    required super.ggLog,
    super.name = 'publish',
    super.description = 'Publish all repos of the current ticket',
    this.mergeOnly = false,
    gg.DoCommit? ggDoCommit,
    ChangeRefsToPubDev? unlocalizeRefs,
    RestorePublishTo? restorePublishTo,
    gg.DoPush? ggDoPush,
    gg.DoPublish? ggDoPublish,
    SortedProcessingList? sortedProcessingList,
    ProcessRunner? processRunner,
    CanPublishCommand? canPublishCommand,
    DoReviewCommand? doReviewCommand,
    GetVersion? getVersionCommand,
    SetRefVersion? setRefVersionCommand,
    GetRefVersion? getRefVersionCommand,
    PubDevChecker? pubDevChecker,
    NpmRegistryChecker? npmChecker,
    PublishSkipCheck? publishSkipCheck,
    DoConfigurePublishCommand? doConfigurePublishCommand,
    gg.EnsurePublishConfigIgnored? ensureIgnored,
    EnsureInRegistry? ensureInRegistry,
  })  : _ggDoCommit = ggDoCommit ?? gg.DoCommit(ggLog: ggLog),
        _unlocalizeRefs = unlocalizeRefs ?? ChangeRefsToPubDev(ggLog: ggLog),
        _restorePublishTo = restorePublishTo ?? RestorePublishTo(ggLog: ggLog),
        _ggDoPush = ggDoPush ?? gg.DoPush(ggLog: ggLog),
        _ggDoPublish = ggDoPublish ?? gg.DoPublish(ggLog: ggLog),
        _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog),
        _canPublishCommand =
            canPublishCommand ?? CanPublishCommand(ggLog: ggLog),
        _doReviewCommand = doReviewCommand ?? DoReviewCommand(ggLog: ggLog),
        _getVersion = getVersionCommand ?? GetVersion(ggLog: ggLog),
        _setRefVersion = setRefVersionCommand ?? SetRefVersion(ggLog: ggLog),
        _getRefVersion = getRefVersionCommand ?? GetRefVersion(ggLog: ggLog),
        _pubDevChecker = pubDevChecker ?? PubDevChecker(),
        _npmChecker = npmChecker ?? NpmRegistryChecker(),
        _publishSkipCheck = publishSkipCheck ?? PublishSkipCheck(),
        _doConfigurePublishCommand = doConfigurePublishCommand ??
            DoConfigurePublishCommand(ggLog: ggLog),
        _ensureIgnored =
            ensureIgnored ?? gg.EnsurePublishConfigIgnored(ggLog: ggLog),
        _ensureInRegistry = ensureInRegistry ?? EnsureInRegistry(ggLog: ggLog),
        _processRunner = processRunner ?? _defaultProcessRunner {
    _addArgs();
  }

  /// Whether the run merges without releasing: no registry upload, no tags.
  ///
  /// Set by `--merge-only` (resolved in [get] before the flow starts) or by
  /// the constructor for programmatic callers; false for a regular publish.
  bool mergeOnly;

  /// The command name used in user-facing hints (`gg do publish` /
  /// `gg do publish --merge-only`).
  String get _command =>
      mergeOnly ? 'gg do publish --merge-only' : 'gg do publish';

  /// The past participle used in user-facing messages.
  String get _done => mergeOnly ? 'merged' : 'published';

  /// The noun used in user-facing messages.
  String get _action => mergeOnly ? 'merge' : 'publish';

  /// Instance of gg DoCommit
  final gg.DoCommit _ggDoCommit;

  /// Instance of UnlocalizeRefs
  final ChangeRefsToPubDev _unlocalizeRefs;

  /// Restores the original `publish_to` value captured by `do add`.
  final RestorePublishTo _restorePublishTo;

  /// Instance of gg DoPush
  final gg.DoPush _ggDoPush;

  /// Instance of gg DoPublish
  final gg.DoPublish _ggDoPublish;

  /// Instance of SortedProcessingList
  final SortedProcessingList _sortedProcessingList;

  /// Instance of CanPublishCommand
  final CanPublishCommand _canPublishCommand;

  /// Reviews all repositories in the ticket before validation starts.
  final DoReviewCommand _doReviewCommand;

  /// Reads the current package version from pubspec.yaml
  final GetVersion _getVersion;

  /// Sets the version/spec of a dependency in pubspec.yaml
  final SetRefVersion _setRefVersion;

  /// Reads the version/spec of a dependency from pubspec.yaml
  final GetRefVersion _getRefVersion;

  /// Checks whether versions are visible on pub.dev.
  final PubDevChecker _pubDevChecker;

  /// Checks whether versions are visible on npm (TypeScript packages).
  final NpmRegistryChecker _npmChecker;

  /// Decides whether an unchanged repo needs to be published at all.
  final PublishSkipCheck _publishSkipCheck;

  /// Interactively builds the `.gg/gg-publish.json` config when the publish
  /// is started without one.
  final DoConfigurePublishCommand _doConfigurePublishCommand;

  /// Adds the repo-level `.gg/gg-publish.json` to each repo's `.gitignore`
  /// before the pre-publish commit, so gg_one's runtime file rides along.
  final gg.EnsurePublishConfigIgnored _ensureIgnored;

  /// Makes sure a repo has at least one version on its registry before it
  /// is published — a first-time publish is done manually by the user.
  final EnsureInRegistry _ensureInRegistry;

  /// Runs shell commands such as branch deletion.
  final ProcessRunner _processRunner;

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    bool? verbose,
    bool? deleteRemoteBranch,
    bool? mergeOnly,
  }) =>
      get(
        directory: directory,
        ggLog: ggLog,
        verbose: verbose,
        deleteRemoteBranch: deleteRemoteBranch,
        mergeOnly: mergeOnly,
      );

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    bool? verbose,
    bool? deleteRemoteBranch,
    bool? mergeOnly,
  }) async {
    ggLog(cH1('Publishing ...'));

    // »--merge-only« replaces the former »gg do merge« command. The resolved
    // value drives every merge-only branch of the flow below, so it is
    // settled before anything else runs.
    this.mergeOnly = mergeOnly ??
        (this.mergeOnly || (argResults?['merge-only'] as bool? ?? false));
    final bool isMergeOnly = this.mergeOnly;
    verbose ??= argResults?['verbose'] as bool? ?? false;
    final continueRun = argResults?['continue'] as bool? ?? false;
    final restart = argResults?['restart'] as bool? ?? false;
    final publishUnchanged = argResults?['publish-unchanged'] as bool? ?? false;
    final force = this.mergeOnly && (argResults?['force'] as bool? ?? false);
    final String? configArg = argResults?['config'] as String?;
    final String? messageArg = argResults?['message'] as String?;
    deleteRemoteBranch ??= argResults?['delete-remote-branch'] as bool? ?? true;

    // Only an explicitly passed --pr/--no-pr is forwarded to the repos; when
    // absent, each repo's persisted .gg/gg-publish.json (on resume) or the
    // default (pr = true) decides.
    final bool? prArg = (argResults?.wasParsed('pr') ?? false)
        ? (argResults?['pr'] as bool?)
        : null;

    final GgLog taskLog = verbose ? ggLog : <String>[].add;

    // Step 1: Detect ticket folder
    final String? ticketPath = WorkspaceUtils.detectTicketPath(
      path.absolute(directory.path),
    );
    if (ticketPath == null) {
      throw Exception(cError('Not inside a ticket folder'));
    }

    final ticketDir = Directory(ticketPath);
    final runtimeFile = DoConfigurePublishCommand.configFileFor(ticketDir);

    // Step 2: Resolve the publish configuration up front so the rest of the
    // run is non-interactive. Precedence: --continue > --config > the runtime
    // .gg/gg-publish.json > the legacy <ticket>/.gg-publish.json > an
    // interactive `do configure-publish`.
    final resolved = await _resolvePublishConfig(
      ticketDir: ticketDir,
      runtimeFile: runtimeFile,
      configArg: configArg,
      continueRun: continueRun,
      restart: restart,
      messageArg: messageArg,
      ggLog: ggLog,
    );
    gg.PublishConfig publishConfig = resolved.config;
    final String configSourcePath = resolved.sourcePath;

    // Get sorted repos (needed before the review gate: the resume decision
    // below inspects each repo's own step progress).
    final subs = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (subs.isEmpty) {
      ggLog(cWarn('⚠️ No repos in this ticket'));
      return;
    }

    // A merge brings the ticket onto the main branches without releasing it.
    // A repository that still redirects a dependency to a local working copy
    // would therefore land on main referencing something nobody can resolve —
    // that ticket has to be published, not merged. Checked before `do review`
    // runs, because reviewing replaces the path overrides with git refs.
    if (isMergeOnly && !force) {
      _throwOnLocalizedRefs(subs);
    }

    // --restart discards not only the ticket-level config but also the
    // repo-level step progress gg_one recorded in an earlier run.
    if (restart) {
      for (final repo in subs) {
        final repoRuntime = gg.DoConfigurePublish.configFileFor(
          repo.directory,
        );
        if (repoRuntime.existsSync()) {
          repoRuntime.deleteSync();
        }
      }
    }

    // Step 3: Review + the ticket wide validation. The per-repo
    // `gg can publish` gate is NOT part of this — it runs inside
    // _publishRepo, right before the repo is published (see there).
    // Skipped when genuinely resuming a run that
    // already made irreversible progress: a repo finished ('published'), or
    // a repo's own .gg/gg-publish.json records completed publish steps —
    // e.g. the FIRST repo failed after its registry publish or merge.
    // Re-reviewing such a partially merged ticket would fail ("nothing to
    // merge") and permanently block the resume. A `--continue` after a
    // *review* failure — no progress anywhere — still reviews, so unreviewed
    // code is never published. gg_one re-checks `did commit` per repo on
    // resume, so raw commits added after the failure are still caught.
    final resumingMidPublish = continueRun &&
        (publishConfig.repos.values.any((r) => r.status == 'published') ||
            subs.any((repo) => _repoHasStepProgress(repo.directory)));
    if (!resumingMidPublish) {
      try {
        await _doReviewCommand.exec(
          directory: ticketDir,
          ggLog: ggLog,
          verbose: verbose,
        );
      } on MergeConflictException {
        // Conflicts are resolved by the user; the message the review printed
        // is the actionable one, so do not bury it in a publish error.
        rethrow;
      } catch (e) {
        // The reason was printed by the review itself — re-wrapping it would
        // print it a second time behind a nested prefix.
        ggLog(
          [cError('\n${(e as dynamic).message}\n')].join('\n'),
        );
        ggLog(cAction('\nPlease fix the issues above.\n'));
        throw Exception(cDetail('Review failed.'));
      }

      try {
        await _canPublishCommand.checkTicket(
          directory: ticketDir,
          ggLog: ggLog,
          includeCanPublish: false,
        );
      } catch (e) {
        ggLog(
          [cError(rmControls('$e'))].join('\n'),
        );
        ggLog(cAction('\nPlease fix the issues above.\n'));

        throw Exception(cDetail('Cannot publish.'));
      }
    }

    final publishedPackages = <String, _PublishedPackageState>{};
    final confirmedPubDevVersions = <String>{};
    final skippedRepos = <String>[];

    // The repos that went through _publishRepo in this run — the only ones
    // whose references were already pointed back at the registry.
    final refsChangedRepos = <String>{};

    // Map of reference name to version captured from repos processed so far.
    final refVersions = <String, String>{};

    // Step 4: Iterate over each repository and publish (or resume).
    for (final repo in subs) {
      final repoDir = repo.directory;
      final repoName = path.basename(repoDir.path);

      final alreadyPublished =
          continueRun && publishConfig.statusForRepo(repoName) == 'published';

      // A repo without manual changes whose dependencies all stay inside
      // their published constraints needs no release. The decision is made
      // fresh on every run — also on --continue, where a repo marked
      // 'skipped' earlier is re-evaluated instead of trusted, so commits
      // added after a failed run are never lost to a stale marker.
      final skipDecision = (!alreadyPublished && !publishUnchanged)
          ? await _publishSkipCheck.get(repo: repo, refVersions: refVersions)
          : null;

      if (alreadyPublished) {
        ggLog('\n${cH1(repoName)} already $_done — skipping.');
      } else if (skipDecision?.skip ?? false) {
        ggLog(
          [
            '\n${cH1(repoName)}',
            '${cDetail('✓ Not $_done.')} ${skipDecision!.reason}',
          ].join('\n'),
        );
        publishConfig = publishConfig.withRepoStatus(repoName, 'skipped');
        await publishConfig.save(file: runtimeFile);
        skippedRepos.add(repoName);
      } else {
        if (skipDecision != null) {
          taskLog(
            '$repoName: ${isMergeOnly ? 'merging' : 'publishing'} — '
            '${skipDecision.reason}.',
          );
        }

        await _waitForPublishedDependenciesIfNeeded(
          currentRepo: repo,
          publishedPackages: publishedPackages,
          confirmedPubDevVersions: confirmedPubDevVersions,
          ggLog: ggLog,
        );

        ggLog('\n${cH1(repoName)}');

        // Save the repo state so a failed publish can restore it.
        final snapshot = await _saveRepoState(repoDir: repoDir, ggLog: taskLog);

        try {
          await _publishRepo(
            repoDir: repoDir,
            repoName: repoName,
            refVersions: refVersions,
            publishConfig: publishConfig,
            configPath: configSourcePath,
            resume: continueRun,
            pr: prArg,
            force: force,
            verbose: verbose,
            ggLog: ggLog,
            taskLog: taskLog,
          );
        } catch (e) {
          // Record the failure so `--continue` resumes here, report why,
          // restore the repo towards its pre-publish state, then surface the
          // failure.
          publishConfig = publishConfig.withRepoStatus(repoName, 'failed');
          await publishConfig.save(file: runtimeFile);
          _logPublishFailure(repoName: repoName, error: e, ggLog: ggLog);
          await _restoreRepoStateOnFailure(
            snapshot: snapshot,
            ggLog: ggLog,
            taskLog: taskLog,
          );
          rethrow;
        }

        refsChangedRepos.add(repoName);

        // Record success *now*, before the network-dependent version capture
        // below — so a transient failure there cannot lose the marker and
        // re-run this already-published repo on a later `--continue`.
        publishConfig = publishConfig.withRepoStatus(repoName, 'published');
        await publishConfig.save(file: runtimeFile);
        taskLog(cDetail('✓ $repoName: $_done successfully.'));
      }

      // Capture the published version + registry visibility so later repos
      // that depend on this one get the right ref and wait for pub.dev/npm.
      // Runs for skipped repos too. The registry lookup is best-effort: it
      // must not abort a run whose repo already published irreversibly.
      try {
        final version = await _getVersion.get(
          directory: repoDir,
        );
        if (version != null && version.isNotEmpty) {
          // Use manifest name (e.g. scoped »@org/pkg« for npm), not dir.
          final packageName = await _readManifestName(repoDir, repoName);
          refVersions[packageName] = version;

          final projectType = _detectProjectType(repoDir);
          try {
            // Git-only repos (no manifest) have no registry to wait for. A
            // merge uploads nothing either, so the fresh version never becomes
            // visible on a registry — recording it here would make every
            // dependent repo wait for a release that is not coming.
            if (!isMergeOnly && projectType != gg.ProjectType.none) {
              final publishInfo = projectType == gg.ProjectType.typescript
                  ? await _npmChecker.getPackagePublishInfo(
                      packageName: packageName,
                      workingDirectory: repoDir.path,
                    )
                  : await _pubDevChecker.getPackagePublishInfo(
                      packageName: packageName,
                    );
              publishedPackages[packageName] = _PublishedPackageState(
                packageName: packageName,
                version: version,
                waitsForPubDev: publishInfo.waitsForPubDev,
                projectType: projectType,
                repoDirPath: repoDir.path,
              );
            }
          } catch (e) {
            ggLog(
              cWarn(
                'Could not check registry visibility of $packageName ($e); '
                'dependent repos will not wait for it. Publish is unaffected.',
              ),
            );
          }
        }
      } catch (e) {
        throw Exception(cError('Failed to get version of $repoName: $e'));
      }
    }

    // Report the repos the run left unpublished on purpose, so a shorter
    // publish never looks like repos were forgotten.
    if (skippedRepos.isNotEmpty) {
      ggLog(
        cWarn(
          '✓ Not $_done. Nothing changed.}',
        ),
      );
    }

    // Step 5: Every repo that was not published still carries the git refs of
    // the review. The cleanup below deletes the very branch they point at, so
    // they are pointed at the freshly published versions first — all versions
    // of the ticket are known now that the loop is through.
    await _changeRemainingRefsToPubDev(
      subs: subs,
      publishedRepos: refsChangedRepos,
      refVersions: refVersions,
      ggLog: ggLog,
      taskLog: taskLog,
    );

    // Step 6: All repos published — the resume anchor is no longer needed.
    if (runtimeFile.existsSync()) {
      runtimeFile.deleteSync();
      taskLog(
        cDetail(
          '✓ Removed ${path.basename(runtimeFile.path)} after the $_action.',
        ),
      );
    }

    // Step 7: Clean the ticket up. The repos are never deleted outright —
    // they move to <root>/.trash/<ticket>, so uncommitted leftovers stay
    // recoverable. The remote feature branch is deleted unless
    // --no-delete-remote-branch was passed.
    await _cleanUpTicket(
      ticketDir: ticketDir,
      subs: subs,
      deleteRemoteBranch: deleteRemoteBranch,
      ggLog: ggLog,
      taskLog: taskLog,
    );

    ggLog('\nAll repos $_done\n');
  }

  /// Moves everything the published ticket leaves behind into
  /// `<root>/.trash/<ticket>` and removes the ticket folder afterwards.
  ///
  /// Every repository of the ticket is moved — also when its remote feature
  /// branch is kept ([deleteRemoteBranch] is false), because the ticket
  /// folder goes away either way and a repo left inside it would be lost.
  /// The `<ticket>.code-workspace` file travels along, so reopening the
  /// published ticket in VS Code is still possible from the trash.
  ///
  /// A failure while trashing a single repo is reported and the remaining
  /// ones are still processed; the ticket folder is only removed when
  /// nothing was left behind.
  Future<void> _cleanUpTicket({
    required Directory ticketDir,
    required List<Node> subs,
    required bool deleteRemoteBranch,
    required GgLog ggLog,
    required GgLog taskLog,
  }) async {
    final ticketName = path.basename(ticketDir.path);
    var allMoved = true;

    for (final repo in subs) {
      final repoDir = repo.directory;
      final repoName = path.basename(repoDir.path);

      try {
        if (deleteRemoteBranch) {
          await _deleteRemoteBranch(
            repoDir: repoDir,
            branchName: ticketName,
            ggLog: taskLog,
          );
        } else {
          taskLog(
            cDetail('✓ Kept remote branch $ticketName for $repoName.'),
          );
        }

        if (repoDir.existsSync()) {
          final target = await Trash.moveFromTicket(
            source: repoDir,
            ticketDir: ticketDir,
          );
          taskLog(
            cDetail(
              'Moved repository $repoName of ticket $ticketName to $target.',
            ),
          );
        }
      } catch (e) {
        allMoved = false;
        ggLog(
          cError(
            'Failed to move repository $repoName of ticket $ticketName to '
            'the trash: $e',
          ),
        );
      }
    }

    // The VS Code workspace describes a ticket that no longer exists — it
    // belongs to the trashed repos, so it follows them.
    final workspaceFile = File(
      path.join(ticketDir.path, '$ticketName.code-workspace'),
    );
    if (workspaceFile.existsSync()) {
      try {
        final target = await Trash.moveFromTicket(
          source: workspaceFile,
          ticketDir: ticketDir,
        );
        taskLog(cDetail('✓ Moved ${path.basename(target)} to $target.'));
      } catch (e) {
        allMoved = false;
        ggLog(
          cError('Failed to move the VS Code workspace of $ticketName: $e'),
        );
      }
    }

    if (!allMoved) {
      ggLog(
        cWarn(
          'Ticket $ticketName was not deleted because not everything could '
          'be moved to the trash.',
        ),
      );
      return;
    }

    if (ticketDir.existsSync()) {
      ticketDir.deleteSync(recursive: true);
      taskLog(cDetail('✓ Deleted ticket folder ${ticketDir.path}.'));
    }
  }

  /// Resolves the publish configuration for the ticket in [ticketDir] and
  /// makes sure a runtime copy lives at [runtimeFile] (the resume anchor).
  ///
  /// Precedence: on `--continue` the runtime file must already exist; else an
  /// explicit `--config` file, then the runtime file, then the legacy
  /// `<ticket>/.gg-publish.json`, and finally an interactive
  /// `do configure-publish`. `--restart` skips the two implicit files so
  /// the user is asked again. User-supplied `--config` / legacy files are only
  /// read — the mutable runtime copy is what receives the progress markers.
  /// [messageArg] (from `-m`) is forwarded to `do configure-publish` as the
  /// default merge message and only matters when the config is written
  /// interactively — it is ignored for `--config`, legacy and runtime files.
  /// [config] is the resolved configuration; [sourcePath] is the file it came
  /// from (the user's `--config`/legacy file, or the runtime copy) — used so a
  /// missing-field error points at the file the user actually authored.
  Future<({gg.PublishConfig config, String sourcePath})> _resolvePublishConfig({
    required Directory ticketDir,
    required File runtimeFile,
    required String? configArg,
    required bool continueRun,
    required bool restart,
    required String? messageArg,
    required GgLog ggLog,
  }) async {
    if (continueRun && (configArg != null || restart)) {
      throw Exception(
        cError(gg.continueConflictMessage),
      );
    }

    if (continueRun) {
      if (!runtimeFile.existsSync()) {
        throw Exception(
          cError(
            'Nothing to continue: ${runtimeFile.path} does not exist. Start a '
            'normal "$_command" first.',
          ),
        );
      }
      return (
        config: gg.PublishConfig.load(
          configArg: runtimeFile.path,
          fallbackDir: ticketDir.path,
        ),
        sourcePath: runtimeFile.path,
      );
    }

    if (restart && runtimeFile.existsSync()) {
      // Explicit user choice: discard the previous config and progress.
      runtimeFile.deleteSync();
    }

    if (configArg != null) {
      // A fresh --config run must not clobber the progress markers of an
      // unfinished publish (same guard as the implicit runtime-file path).
      _throwOnLeftoverTicketProgress(
        runtimeFile: runtimeFile,
        ticketDir: ticketDir,
      );
      final config = gg.PublishConfig.load(
        configArg: configArg,
        fallbackDir: ticketDir.path,
      );
      await config.save(file: runtimeFile);
      return (config: config, sourcePath: configArg);
    }

    if (!restart && runtimeFile.existsSync()) {
      final config = gg.PublishConfig.load(
        configArg: runtimeFile.path,
        fallbackDir: ticketDir.path,
      );
      // A runtime file carrying progress markers is the leftover of an
      // unfinished run — do not silently reuse it as plain config.
      if (config.repos.values.any((r) => r.status != null)) {
        throw Exception(
          cError(
            gg.unfinishedPublishMessage(
              path: runtimeFile.path,
              command: _command,
            ),
          ),
        );
      }
      return (config: config, sourcePath: runtimeFile.path);
    }

    final legacyFile = File(path.join(ticketDir.path, '.gg-publish.json'));
    if (!restart && legacyFile.existsSync()) {
      final config = gg.PublishConfig.load(
        configArg: legacyFile.path,
        fallbackDir: ticketDir.path,
      );
      await config.save(file: runtimeFile);
      return (config: config, sourcePath: legacyFile.path);
    }

    final config = await _doConfigurePublishCommand.configure(
      directory: ticketDir,
      ggLog: ggLog,
      defaultMergeMessage: messageArg,
      mergeOnly: mergeOnly,
    );
    return (config: config, sourcePath: runtimeFile.path);
  }

  /// Throws when [runtimeFile] still carries per-repo progress markers of an
  /// unfinished run — a fresh config source must not clobber them.
  void _throwOnLeftoverTicketProgress({
    required File runtimeFile,
    required Directory ticketDir,
  }) {
    if (!runtimeFile.existsSync()) {
      return;
    }
    final existing = gg.PublishConfig.load(
      configArg: runtimeFile.path,
      fallbackDir: ticketDir.path,
    );
    if (existing.repos.values.any((r) => r.status != null)) {
      throw Exception(
        cError(
          gg.unfinishedPublishMessage(
            path: runtimeFile.path,
            command: _command,
          ),
        ),
      );
    }
  }

  /// Whether [repoDir]'s own `.gg/gg-publish.json` records completed publish
  /// steps — i.e. gg_one already did irreversible work in that repo.
  bool _repoHasStepProgress(Directory repoDir) {
    final file = gg.DoConfigurePublish.configFileFor(repoDir);
    if (!file.existsSync()) {
      return false;
    }
    try {
      return gg.PublishConfig.load(
        configArg: file.path,
        fallbackDir: repoDir.path,
      ).hasStepProgress;
    } catch (_) {
      // An unreadable file cannot prove progress.
      return false;
    }
  }

  /// Performs the per-repo publish steps: unlocalize refs, restore
  /// publish_to, propagate reference versions, refresh dependencies, commit,
  /// check that this repo can be published, push and finally `gg do publish`.
  Future<void> _publishRepo({
    required Directory repoDir,
    required String repoName,
    required Map<String, String> refVersions,
    required gg.PublishConfig publishConfig,
    required String configPath,
    required bool resume,
    required bool? pr,
    required bool force,
    required bool verbose,
    required GgLog ggLog,
    required GgLog taskLog,
  }) async {
    // Make sure the repo-level runtime file gg_one writes is gitignored —
    // the entry rides along the force-commit below, no extra commit needed.
    await _ensureIgnored.ensure(directory: repoDir, commit: false);

    await _changeRefsToPubDev(
      repoDir: repoDir,
      repoName: repoName,
      refVersions: refVersions,
      taskLog: taskLog,
    );

    // Commit
    await _ggDoCommit.exec(
      directory: repoDir,
      ggLog: taskLog,
      message: '#gg: changed references to pub.dev',
      force: true,
      // Bookkeeping, not a change of the package — keep it out of
      // CHANGELOG.md (»gg do commit --no-log«).
      updateChangeLog: false,
    );

    // Can this repo be published? Only NOW is the question answerable: the
    // refs point at the registry again and every dependency published
    // earlier in this run is already there, so pana — which analyses the
    // package exactly as it would be published — can resolve it. Asking this
    // ticket wide up front fails for every repo that depends on a sibling
    // version this run has not uploaded yet.
    //
    // Two invariants hold the position:
    //   * AFTER the force-commit — gg can publish contains `did commit`, and
    //     _changeRefsToPubDev leaves the manifests dirty.
    //   * BEFORE the push — nothing irreversible has happened yet, so a
    //     rejected repo takes the full-restore path in _restoreRepoState and
    //     ends up exactly as it started. Moving this below the push would
    //     downgrade a fully recoverable failure to a cleanup restore.
    //
    // A repo that already carries gg_one step progress is past the point
    // where the gate is meaningful — its version is bumped and possibly
    // uploaded, which is precisely what pana and `is feature branch` would
    // now trip over — so a resume skips it and gg_one continues at its own
    // first open step.
    if (!(resume && _repoHasStepProgress(repoDir))) {
      await _canPublishCommand.checkRepo(directory: repoDir, ggLog: ggLog);
    }

    // Push
    await _ggDoPush.exec(directory: repoDir, ggLog: taskLog);

    taskLog(cDetail('✓ $repoName: updated with new references.'));

    // At least one version must already be on the registry. A package that
    // was never published is published manually by the user first — right
    // now, while the refs are unlocalized and the publish target is
    // restored, so the current folder is publishable as-is. A merge-only
    // run releases nothing to a registry, so there is nothing to ensure.
    if (!mergeOnly) {
      await _ensureInRegistry.ensure(directory: repoDir, ggLog: ggLog);
    }

    // The publish configuration is always resolved up front, so every repo
    // has an explicit merge message and version increment here.
    final resolved = publishConfig.forRepo(
      repoName: repoName,
      configPath: configPath,
      // A merge-only run bumps no version, so a config written for it carries
      // no increment — demanding one would reject the very file it wrote.
      requireVersionIncrement: !mergeOnly,
    );
    final publishMessage = resolved.mergeMessage;
    final publishVersionIncrement = resolved.versionIncrement;
    final publishChannel = publishConfig.channelForRepo(repoName);

    // gg do publish; multi flow is non-interactive (no confirm prompt).
    // On --continue, gg_one resumes at the first step its repo-level
    // .gg/gg-publish.json marks as not done yet.
    await _ggDoPublish.exec(
      directory: repoDir,
      ggLog: ggLog,
      message: publishMessage,
      deleteFeatureBranch: false,
      verbose: verbose,
      versionIncrement: publishVersionIncrement,
      channel: publishChannel,
      askBeforePublishing: false,
      resume: resume,
      pr: pr,
      mergeOnly: mergeOnly,
      force: force,
    );
  }

  /// Points every reference of [repoDir] at the registry again: the localized
  /// refs are unlocalized, the original `publish_to` is restored, every known
  /// [refVersions] entry is written as the dependency's version and the
  /// dependencies are refreshed so the lock file follows.
  ///
  /// While the ticket is under review, `gg_localize_refs` redirects the
  /// workspace dependencies through `pubspec_overrides.yaml` — first to the
  /// sibling checkouts, then to the ticket's feature branch. Both are gone
  /// after the publish: the checkouts move to the trash and the feature branch
  /// is deleted on the remote (by `_cleanUpTicket`, and often by the provider
  /// itself the moment the pull request is merged). A repo left pointing at
  /// either fails its next `dart pub get` with an unresolvable reference,
  /// which is why this runs for **every** repo of the ticket — see
  /// [_changeRemainingRefsToPubDev] for the ones that are not published.
  Future<void> _changeRefsToPubDev({
    required Directory repoDir,
    required String repoName,
    required Map<String, String> refVersions,
    required GgLog taskLog,
  }) async {
    try {
      await _unlocalizeRefs.get(directory: repoDir, ggLog: taskLog);
      taskLog(cDetail('✓ $repoName: unlocalized refs.'));
    } catch (e) {
      throw Exception(cError('Failed to unlocalize refs for $repoName: $e'));
    }

    try {
      await _restorePublishTo.exec(directory: repoDir, ggLog: taskLog);
    } catch (e) {
      throw Exception(cError('Failed to restore publish_to for $repoName: $e'));
    }

    // Apply all known reference versions to this repo if it depends on them
    for (final entry in refVersions.entries) {
      final refName = entry.key;
      final refVersion = entry.value;
      try {
        final spec = await _getRefVersion.get(
          directory: repoDir,
          ref: refName,
        );
        if (spec != null) {
          // Pass the bare published version. set-ref-version preserves the
          // operator (`^`, `~`, or none/exact) the dependency is currently
          // declared with — the refs were just unlocalized back to their
          // original spec — so the user's chosen constraint style survives.
          await _setRefVersion.get(
            directory: repoDir,
            ref: refName,
            version: refVersion,
          );
        }
      } catch (e) {
        throw Exception(
          cError('Failed to update version of $refName '
              'in $repoName: $e'),
        );
      }
    }

    // Refresh deps after manifest edits (refs, publish_to, versions).
    await _refreshDependencies(
      repoDir: repoDir,
      repoName: repoName,
      ggLog: taskLog,
    );
  }

  /// Runs [_changeRefsToPubDev] for the repos of [subs] that never went
  /// through [_publishRepo] — the ones the unchanged-repo check skipped and,
  /// on `--continue`, the ones an earlier run already published.
  ///
  /// Without it exactly those repos keep the refs of the review: a
  /// `pubspec_overrides.yaml` pinning the ticket's feature branch, which the
  /// ticket cleanup deletes right after. The repos are moved to the trash
  /// rather than deleted, so they stay usable — but only when their references
  /// point at the versions that were just published.
  ///
  /// [publishedRepos] are the repos that already did this inside their
  /// publish. Failures are reported and the remaining repos are still
  /// processed: everything irreversible has happened at this point, and
  /// aborting here would leave the ticket half cleaned up.
  Future<void> _changeRemainingRefsToPubDev({
    required List<Node> subs,
    required Set<String> publishedRepos,
    required Map<String, String> refVersions,
    required GgLog ggLog,
    required GgLog taskLog,
  }) async {
    for (final repo in subs) {
      final repoName = path.basename(repo.directory.path);
      if (publishedRepos.contains(repoName)) {
        continue;
      }

      try {
        // Unlike inside the publish loop — where a repo's own version is only
        // recorded after its turn — refVersions holds every repo of the ticket
        // by now, this one included. A package never depends on itself, so its
        // own entry is dropped instead of looked up.
        final ownName = await _readManifestName(repo.directory, repoName);
        await _changeRefsToPubDev(
          repoDir: repo.directory,
          repoName: repoName,
          refVersions: <String, String>{
            for (final entry in refVersions.entries)
              if (entry.key != ownName && entry.key != repoName)
                entry.key: entry.value,
          },
          taskLog: taskLog,
        );
      } catch (e) {
        ggLog(
          cWarn(
            'Could not point the references of $repoName at the published '
            'versions ($e). Its ${gg.NoPubspecOverrides.fileName} may still '
            'refer to the deleted feature branch.',
          ),
        );
      }
    }
  }

  /// Throws when one of [repos] still redirects a dependency to a local
  /// working copy (`pubspec_overrides.yaml`).
  ///
  /// Only a `--merge-only` run calls this: it brings the ticket onto the main
  /// branches *without* releasing anything, so a reference that exists only as
  /// a working copy on this machine would never become resolvable for anybody
  /// else. Such a ticket has to be published. `--force` skips the check.
  void _throwOnLocalizedRefs(List<Node> repos) {
    final localized = repos
        .where((repo) => gg.NoPubspecOverrides.hasLocalizedRefs(repo.directory))
        .map((repo) => path.basename(repo.directory.path))
        .toList();

    if (localized.isEmpty) {
      return;
    }

    throw Exception(
      cError(
        [
          'These projects depend on other local projects: '
              '${localized.join(', ')}.',
          'Just merging is not possible.',
          '  - Either run ${cCmd('gg do publish')} ',
          '  - Or merge anyway adding ${cCmd('--force')} option.',
        ].join('\n'),
      ),
    );
  }

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

  /// Returns the commit hash of the local branch [branch] in [repoDir],
  /// or null when the branch does not exist.
  Future<String?> _localBranchHead(Directory repoDir, String branch) async {
    final out = await _runGit(
      <String>['rev-parse', '--verify', '--quiet', 'refs/heads/$branch'],
      repoDir: repoDir,
      allowFailure: true,
    );
    return out.isEmpty ? null : out;
  }

  /// Returns the commit hash of `origin/<branch>` for [repoDir], or null
  /// when the remote branch does not exist or cannot be queried.
  Future<String?> _remoteBranchHead(Directory repoDir, String branch) async {
    final result = await _processRunner(
      'git',
      <String>['ls-remote', 'origin', 'refs/heads/$branch'],
      workingDirectory: repoDir.path,
    );
    if (result.exitCode != 0) {
      return null;
    }
    final out = (result.stdout?.toString() ?? '').trim();
    if (out.isEmpty) {
      return null;
    }
    return out.split(RegExp(r'\s+')).first;
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

  /// Whether [status] (a `git status --porcelain` output) shows an uncommitted
  /// change to the version-bearing manifest. Used to tell a *committed* version
  /// bump apart from an uncommitted half-written one left by a failed publish.
  bool _manifestDirty(String status) =>
      status.contains('pubspec.yaml') || status.contains('package.json');

  /// Records branch, HEAD, working tree, package version, default-branch
  /// position (local + remote), feature-branch remote head and tags of
  /// [repoDir], so a failed publish can be rolled back by [_restoreRepoState].
  Future<_RepoPublishSnapshot> _saveRepoState({
    required Directory repoDir,
    required GgLog ggLog,
  }) async {
    final repoName = path.basename(repoDir.path);
    try {
      final head = await _runGit(
        <String>['rev-parse', 'HEAD'],
        repoDir: repoDir,
      );
      final rawBranch = await _runGit(
        <String>['rev-parse', '--abbrev-ref', 'HEAD'],
        repoDir: repoDir,
      );
      final detached = rawBranch == 'HEAD';
      // Detached HEAD: `rev-parse --abbrev-ref` prints the literal "HEAD".
      // Store the commit so restore re-detaches at it instead of running the
      // no-op `git checkout HEAD`.
      final branch = detached ? head : rawBranch;
      final status = await _runGit(
        <String>['status', '--porcelain'],
        repoDir: repoDir,
      );
      final stash = await _captureUncommitted(repoDir: repoDir, status: status);
      // The version is compared again on restore to detect a committed
      // version bump. Not every repo has a readable version — tolerate that.
      String? version;
      try {
        version = await _getVersion.get(directory: repoDir);
      } catch (_) {
        version = null;
      }
      String? mainBranch = 'main';
      String? mainHead = await _localBranchHead(repoDir, 'main');
      if (mainHead == null) {
        mainBranch = 'master';
        mainHead = await _localBranchHead(repoDir, 'master');
        if (mainHead == null) {
          mainBranch = null;
        }
      }
      final remoteMainHead = mainBranch == null
          ? null
          : await _remoteBranchHead(repoDir, mainBranch);
      final remoteFeatureHead =
          detached ? null : await _remoteBranchHead(repoDir, rawBranch);
      final tags = (await _runGit(<String>['tag', '--list'], repoDir: repoDir))
          .split('\n')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toSet();
      ggLog(cDetail('✓ Saved state of $repoName'));
      return _RepoPublishSnapshot(
        directory: repoDir,
        branch: branch,
        head: head,
        status: status,
        version: version,
        mainBranch: mainBranch,
        mainHead: mainHead,
        remoteMainHead: remoteMainHead,
        remoteFeatureHead: remoteFeatureHead,
        tags: tags,
        stash: stash,
      );
    } catch (e) {
      throw Exception(
        cError(
          'Failed to save the state of $repoName before publishing — $repoName '
          'was not changed (repositories published earlier in this run stay '
          'published): $e',
        ),
      );
    }
  }

  /// Prints why publishing [repoName] failed, right where `failed` is recorded
  /// in the ticket's `.gg/gg-publish.json`. Without it the reason only shows
  /// up at the very end of the run, below the rollback output — and the
  /// per-repo detail gg_one logs is swallowed entirely without `--verbose`.
  void _logPublishFailure({
    required String repoName,
    required Object error,
    required GgLog ggLog,
  }) {
    final reason = rmControls(
      (error as dynamic).message.toString(),
    ).trim();
    ggLog(
      [
        cDetail('✗ ${mergeOnly ? 'Merging' : 'Publishing'} $repoName failed'),
        if (reason.isNotEmpty) cError(reason),
      ].join('\n'),
    );
    ggLog(
      cAction(
        [
          'Fix the problem and resume with:',
          '  ${cCmd('$_command --continue')}',
          '  ${cCmd('$_command --resetart')}',
        ].join('\n'),
      ),
    );
  }

  /// Restores the repository after a failed publish. Never throws — the
  /// publish failure that triggered the restore must stay the primary error.
  Future<void> _restoreRepoStateOnFailure({
    required _RepoPublishSnapshot snapshot,
    required GgLog ggLog,
    required GgLog taskLog,
  }) async {
    final repoName = path.basename(snapshot.directory.path);
    try {
      await GgStatusPrinter<void>(
        message: 'Restoring $repoName after the failed publish',
        ggLog: ggLog,
      ).run(
        () async => _restoreRepoState(
          snapshot: snapshot,
          ggLog: ggLog,
          taskLog: taskLog,
        ),
      );
    } catch (e) {
      final manual = StringBuffer(
        '"git checkout ${snapshot.branch}" + '
        '"git reset --hard ${snapshot.head}"',
      );
      if (snapshot.stash != null) {
        manual.write(' + "git stash apply --index ${snapshot.stash}"');
      }
      ggLog(
        cError(
          'Restoring $repoName after the failed publish failed — restore it '
          'manually ($manual): $e',
        ),
      );
    }
  }

  /// Brings the repository back to its snapshot after a failed publish.
  ///
  /// Two modes, because a publish has effects that must not be undone: when the
  /// failed run already *committed* a version bump (the registry release may
  /// exist — pub.dev/npm cannot be unpublished), already moved `origin/main`,
  /// or already pushed the feature branch, only half-done merges/rebases are
  /// ended and the original branch is checked out again; all commits are kept
  /// so a re-run of `gg do publish` resumes. Otherwise nothing irreversible
  /// happened and the full snapshot is restored: HEAD, default-branch
  /// position, tags and stashed changes (with the original staged/unstaged
  /// split).
  Future<void> _restoreRepoState({
    required _RepoPublishSnapshot snapshot,
    required GgLog ggLog,
    required GgLog taskLog,
  }) async {
    final s = snapshot;
    final repoDir = s.directory;
    final repoName = path.basename(repoDir.path);

    final headNow = await _runGit(
      <String>['rev-parse', 'HEAD'],
      repoDir: repoDir,
    );
    final statusNow = await _runGit(
      <String>['status', '--porcelain'],
      repoDir: repoDir,
    );
    final branchNowFirst = await _runGit(
      <String>['rev-parse', '--abbrev-ref', 'HEAD'],
      repoDir: repoDir,
    );
    if (headNow == s.head &&
        statusNow == s.status &&
        branchNowFirst == s.branch) {
      taskLog('Unchanged: $repoName');
      return;
    }

    // End half-done merges/rebases the failed publish may have left behind.
    await _runGit(
      <String>['merge', '--abort'],
      repoDir: repoDir,
      allowFailure: true,
    );
    await _runGit(
      <String>['rebase', '--abort'],
      repoDir: repoDir,
      allowFailure: true,
    );

    // Back to the original (feature) branch.
    final branchNow = await _runGit(
      <String>['rev-parse', '--abbrev-ref', 'HEAD'],
      repoDir: repoDir,
    );
    if (branchNow != s.branch) {
      await _runGit(<String>['checkout', s.branch], repoDir: repoDir);
    }

    // Detect irreversible effects of the failed run. Read the state *after*
    // checking out the feature branch so the manifest-dirty check reflects it.
    final statusForDecision = await _runGit(
      <String>['status', '--porcelain'],
      repoDir: repoDir,
    );
    String? versionNow;
    try {
      versionNow = await _getVersion.get(directory: repoDir);
    } catch (_) {
      versionNow = null;
    }
    final remoteMainNow = s.mainBranch == null
        ? null
        : await _remoteBranchHead(repoDir, s.mainBranch!);
    // Detached snapshots store the commit hash in `branch`; there is no
    // feature branch name to query then.
    final remoteFeatureNow =
        s.branch == s.head ? null : await _remoteBranchHead(repoDir, s.branch);

    // A version bump only counts as irreversible when it was *committed*
    // (gg_one commits the bump before touching the registry). An uncommitted
    // half-written bump left by a failed commit still shows in the working
    // tree — that is recoverable, so restore fully.
    final versionBumped =
        versionNow != s.version && !_manifestDirty(statusForDecision);
    // Only conclude the remote moved when we actually read a differing hash.
    // A failed/unreachable `git ls-remote` (often the very cause of the
    // rollback) returns null and must not masquerade as "already released".
    final remoteMainMoved =
        remoteMainNow != null && remoteMainNow != s.remoteMainHead;
    // The feature-branch commit already reached the remote; resetting local
    // behind it would desync the two and make the next run rebase onto it.
    final featurePushed =
        remoteFeatureNow != null && remoteFeatureNow != s.remoteFeatureHead;

    if (versionBumped || remoteMainMoved || featurePushed) {
      final String reason;
      if (versionBumped) {
        reason = 'version ${versionNow ?? '?'} is already prepared and may '
            'already be published to the registry';
      } else if (remoteMainMoved) {
        reason = 'origin/${s.mainBranch} already received the release';
      } else {
        reason = 'the feature branch was already pushed to origin';
      }
      ggLog(
        cWarn(
          '$repoName: back on ${s.branch}, but all commits were kept '
          'because $reason. Re-running "$_command" resumes the $_action.',
        ),
      );
      return;
    }

    // Nothing irreversible happened — restore the full snapshot.
    await _runGit(<String>['reset', '--hard', s.head], repoDir: repoDir);

    // gg_one's runtime .gg/gg-publish.json is gitignored and survives the
    // reset — but its step markers describe commits that were just rolled
    // back, so they must not seed a later resume. Drop the file; the
    // keep-commits path above keeps it because there the steps stay real.
    final repoRuntimeFile = gg.DoConfigurePublish.configFileFor(repoDir);
    if (repoRuntimeFile.existsSync()) {
      repoRuntimeFile.deleteSync();
    }

    if (s.mainBranch != null &&
        s.mainBranch != s.branch &&
        s.mainHead != null) {
      final mainHeadNow = await _localBranchHead(repoDir, s.mainBranch!);
      if (mainHeadNow != null && mainHeadNow != s.mainHead) {
        await _runGit(
          <String>['branch', '-f', s.mainBranch!, s.mainHead!],
          repoDir: repoDir,
        );
      }
    }

    // Remove tags the failed run created.
    final tagsNow = (await _runGit(<String>['tag', '--list'], repoDir: repoDir))
        .split('\n')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty);
    for (final tag in tagsNow) {
      if (!s.tags.contains(tag)) {
        await _runGit(<String>['tag', '-d', tag], repoDir: repoDir);
      }
    }

    if (s.stash != null) {
      await _runGit(
        <String>['stash', 'apply', '--index', s.stash!],
        repoDir: repoDir,
      );
    }

    taskLog(cDetail('✓ Restored the state before the publish in $repoName'));
    ggLog(
      cWarn(
        '$repoName: pushes to origin are not rolled back; the next run '
        'integrates them.',
      ),
    );
  }

  /// Waits for already published dependencies of [currentRepo] on pub.dev.
  Future<void> _waitForPublishedDependenciesIfNeeded({
    required Node currentRepo,
    required Map<String, _PublishedPackageState> publishedPackages,
    required Set<String> confirmedPubDevVersions,
    required GgLog ggLog,
  }) async {
    if (publishedPackages.isEmpty) {
      return;
    }

    final waitingStates =
        publishedPackages.values.where((state) => state.waitsForPubDev);

    for (final state in waitingStates) {
      final cacheKey = '${state.packageName}@${state.version}';
      if (confirmedPubDevVersions.contains(cacheKey)) {
        continue;
      }

      // The checkers announce the wait themselves (incl. the registry's
      // status page url), report progress while polling and fail with a
      // bounded timeout instead of hanging.
      await (state.projectType == gg.ProjectType.typescript
          ? _npmChecker.waitUntilVersionAvailable(
              packageName: state.packageName,
              version: state.version,
              ggLog: ggLog,
              workingDirectory: state.repoDirPath,
            )
          : _pubDevChecker.waitUntilVersionAvailable(
              packageName: state.packageName,
              version: state.version,
              ggLog: ggLog,
            ));

      confirmedPubDevVersions.add(cacheKey);
    }
  }

  /// Detects the project type of [repoDir]. Repos without a recognizable
  /// manifest resolve to [gg.ProjectType.none] — they publish to git only,
  /// so no registry is waited for.
  ///
  /// Bridges (pubspec + package.json) resolve to TypeScript via
  /// [gg.checkProjectType] so they are published to — and waited for on — npm.
  gg.ProjectType _detectProjectType(Directory repoDir) =>
      gg.checkProjectType(repoDir);

  /// Reads the published package name from the manifest of [repoDir]
  /// (e.g. the scoped »@org/pkg« for npm). Falls back to [fallback] (the
  /// repository directory name) when the manifest cannot be read.
  Future<String> _readManifestName(Directory repoDir, String fallback) async {
    try {
      final catalog = await gg_lang.LanguageCatalog.load();
      // Bridges expose their scoped npm name from package.json (TypeScript).
      return await gg_lang.Manifest.detect(
        repoDir,
        catalog,
        treatBridgeAsTypeScript: true,
      ).readName();
    } catch (_) {
      return fallback; // coverage:ignore-line
    }
  }

  /// Refreshes dependencies for [repoDir] based on the detected project
  /// type. Runs `dart pub upgrade` for Dart/Flutter packages and the
  /// equivalent install command for TypeScript packages (npm/yarn/pnpm).
  Future<void> _refreshDependencies({
    required Directory repoDir,
    required String repoName,
    required GgLog ggLog,
  }) async {
    // Bridge repos refresh via their TypeScript package manager, like
    // do/review and do/cancel_review (checkProjectType: bridge → TS).
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

    // pnpm 11 blockExoticSubdeps must be off (env-var-only) for git chains.
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
        ggLog(cDetail('✓ Executed $cmd in $repoName.'));
      } else {
        throw Exception(
          cError(
            'Failed to execute $cmd in $repoName: ${result.stderr}',
          ),
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

  /// Deletes the remote feature branch [branchName] for [repoDir].
  Future<void> _deleteRemoteBranch({
    required Directory repoDir,
    required String branchName,
    required GgLog ggLog,
  }) async {
    final repoName = path.basename(repoDir.path);
    final result = await _processRunner(
      'git',
      <String>['push', 'origin', '--delete', branchName],
      workingDirectory: repoDir.path,
    );

    if (result.exitCode != 0) {
      // The branch might have been deleted already, e.g. directly on GitHub.
      // Then there is nothing left to do and nothing to complain about.
      final stderr = '${result.stderr}';
      if (stderr.contains('remote ref does not exist')) {
        ggLog(
          cWarn(
            'Remote branch $branchName for $repoName is already deleted.',
          ),
        );
        return;
      }

      throw Exception(
        cError(
          'Failed to delete remote branch $branchName for $repoName: '
          '$stderr',
        ),
      );
    }

    ggLog(
      cDetail(
        'Deleted remote branch $branchName for $repoName.',
      ),
    );
  }

  /// Runs system processes with shell support.
  // coverage:ignore-start
  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: true,
    );
  }

  // coverage:ignore-end

  // Adds command line arguments
  void _addArgs() {
    argParser.addOption(
      'message',
      abbr: 'm',
      help: 'Default merge message of an interactive config',
    );
    argParser.addOption(
      'config',
      help: 'Path to a .gg-publish.json to publish with',
    );
    argParser.addFlag(
      'delete-remote-branch',
      help: 'Delete the remote feature branches (default)',
      defaultsTo: true,
      negatable: true,
    );
    argParser.addFlag(
      'pr',
      help: 'Merge via auto-merge pull request (default)',
      defaultsTo: true,
      negatable: true,
    );
    argParser.addFlag(
      'continue',
      help: 'Resume a failed publish where it stopped',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'publish-unchanged',
      help: 'Publish every repo, even an unchanged one',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'merge-only',
      help: 'Merge the ticket without releasing it',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'force',
      help: 'With --merge-only: merge despite local refs',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'restart',
      help: 'Discard the saved config and configure again',
      defaultsTo: false,
      negatable: true,
    );
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'Show detailed log output.',
      defaultsTo: false,
      negatable: true,
    );
  }
}

/// Stores publish state for already processed repositories.
class _PublishedPackageState {
  /// Creates a new published package state.
  const _PublishedPackageState({
    required this.packageName,
    required this.version,
    required this.waitsForPubDev,
    required this.projectType,
    required this.repoDirPath,
  });

  /// The public package name.
  final String packageName;

  /// The published version.
  final String version;

  /// Whether the next packages must wait for registry visibility.
  final bool waitsForPubDev;

  /// The project type — selects the registry (pub.dev vs npm) to wait on.
  final gg.ProjectType projectType;

  /// The repo directory — npm lookups run there so the project-level
  /// `.npmrc` (scoped/private registries) is honored.
  final String repoDirPath;
}

/// Mock for [DoPublishCommand]
class MockDoPublishCommand extends MockDirCommand<void>
    implements DoPublishCommand {}
