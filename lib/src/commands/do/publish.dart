// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_one/gg_one.dart' as gg;
import 'package:gg_lang/gg_lang.dart' as gg_lang;
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
// ignore: lines_longer_than_80_chars
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_localize_refs/gg_localize_refs.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:interact/interact.dart';
import 'package:path/path.dart' as path;

import '../../backend/git_snapshot.dart' as git_snapshot;
import '../../backend/npm_registry_checker.dart';
import '../../backend/pub_dev_checker.dart';
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

/// Typedef for asking the user whether the ticket should be deleted.
typedef ConfirmDeleteTicket = bool Function(String ticketName);

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
class DoPublishCommand extends DirCommand<void> {
  /// Constructor
  DoPublishCommand({
    required super.ggLog,
    super.name = 'publish',
    super.description = 'Publishes all repositories in the current ticket.',
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
    DoConfigurePublishCommand? doConfigurePublishCommand,
    gg.EnsurePublishConfigIgnored? ensureIgnored,
    ConfirmDeleteTicket? confirmDeleteTicket,
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
        _doConfigurePublishCommand = doConfigurePublishCommand ??
            DoConfigurePublishCommand(ggLog: ggLog),
        _ensureIgnored =
            ensureIgnored ?? gg.EnsurePublishConfigIgnored(ggLog: ggLog),
        _processRunner = processRunner ?? _defaultProcessRunner,
        _confirmDeleteTicket =
            confirmDeleteTicket ?? _defaultConfirmDeleteTicket {
    _addArgs();
  }

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

  /// Interactively builds the `.gg/.gg-publish.json` config when the publish
  /// is started without one.
  final DoConfigurePublishCommand _doConfigurePublishCommand;

  /// Adds the repo-level `.gg/.gg-publish.json` to each repo's `.gitignore`
  /// before the pre-publish commit, so gg_one's runtime file rides along.
  final gg.EnsurePublishConfigIgnored _ensureIgnored;

  /// Runs shell commands such as branch deletion.
  final ProcessRunner _processRunner;

  /// Asks the user whether the ticket should be deleted.
  final ConfirmDeleteTicket _confirmDeleteTicket;

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
    final continueRun = argResults?['continue'] as bool? ?? false;
    final reconfigure = argResults?['reconfigure'] as bool? ?? false;
    final String? configArg = argResults?['config'] as String?;
    final String? messageArg = argResults?['message'] as String?;

    // Only an explicitly passed --pr/--no-pr is forwarded to the repos; when
    // absent, each repo's persisted .gg/.gg-publish.json (on resume) or the
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
      throw Exception('Not inside a ticket folder');
    }

    final ticketDir = Directory(ticketPath);
    final ticketName = path.basename(ticketDir.path);
    final runtimeFile = DoConfigurePublishCommand.configFileFor(ticketDir);

    // Step 2: Resolve the publish configuration up front so the rest of the
    // run is non-interactive. Precedence: --continue > --config > the runtime
    // .gg/.gg-publish.json > the legacy <ticket>/.gg-publish.json > an
    // interactive `do configure-publish`.
    final resolved = await _resolvePublishConfig(
      ticketDir: ticketDir,
      runtimeFile: runtimeFile,
      configArg: configArg,
      continueRun: continueRun,
      reconfigure: reconfigure,
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
      ggLog(yellow('⚠️ No repos in this ticket'));
      return;
    }

    // --reconfigure discards not only the ticket-level config but also the
    // repo-level step progress gg_one recorded in an earlier run.
    if (reconfigure) {
      for (final repo in subs) {
        final repoRuntime = gg.DoConfigurePublish.configFileFor(
          repo.directory,
        );
        if (repoRuntime.existsSync()) {
          repoRuntime.deleteSync();
        }
      }
    }

    // Step 3: Review + validate. Skipped when genuinely resuming a run that
    // already made irreversible progress: a repo finished ('published'), or
    // a repo's own .gg/.gg-publish.json records completed publish steps —
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
      } catch (e) {
        throw Exception('gg_multi do review failed: $e');
      }

      try {
        await _canPublishCommand.exec(directory: ticketDir, ggLog: ggLog);
      } catch (e) {
        throw Exception('gg_multi can publish failed: $e');
      }
    }

    final publishedPackages = <String, _PublishedPackageState>{};
    final confirmedPubDevVersions = <String>{};

    // Map of reference name to version captured from repos processed so far.
    final refVersions = <String, String>{};

    // Step 4: Iterate over each repository and publish (or resume).
    for (final repo in subs) {
      final repoDir = repo.directory;
      final repoName = path.basename(repoDir.path);

      final alreadyPublished =
          continueRun && publishConfig.statusForRepo(repoName) == 'published';

      if (!alreadyPublished) {
        await _waitForPublishedDependenciesIfNeeded(
          currentRepo: repo,
          publishedPackages: publishedPackages,
          confirmedPubDevVersions: confirmedPubDevVersions,
          ggLog: ggLog,
        );

        ggLog('${cyan(repoName)}:');

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
            verbose: verbose,
            ggLog: ggLog,
            taskLog: taskLog,
          );
        } catch (_) {
          // Record the failure so `--continue` resumes here, restore the repo
          // towards its pre-publish state, then surface the failure.
          publishConfig = publishConfig.withRepoStatus(repoName, 'failed');
          await publishConfig.save(file: runtimeFile);
          await _restoreRepoStateOnFailure(
            snapshot: snapshot,
            ggLog: ggLog,
            taskLog: taskLog,
          );
          rethrow;
        }

        // Record success *now*, before the network-dependent version capture
        // below — so a transient failure there cannot lose the marker and
        // re-run this already-published repo on a later `--continue`.
        publishConfig = publishConfig.withRepoStatus(repoName, 'published');
        await publishConfig.save(file: runtimeFile);
        taskLog(green('$repoName: published successfully.'));
      } else {
        ggLog('${cyan(repoName)}: already published — skipping.');
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
            // Git-only repos (no manifest) have no registry to wait for.
            if (projectType != gg.ProjectType.none) {
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
              yellow(
                'Could not check registry visibility of $packageName ($e); '
                'dependent repos will not wait for it. Publish is unaffected.',
              ),
            );
          }
        }
      } catch (e) {
        throw Exception('Failed to get version of $repoName: $e');
      }
    }

    // Step 5: All repos published — the resume anchor is no longer needed.
    if (runtimeFile.existsSync()) {
      runtimeFile.deleteSync();
      taskLog(
        green('Removed ${path.basename(runtimeFile.path)} after publish.'),
      );
    }

    // delete_ticket from .gg-publish.json wins; else interactive prompt.
    final bool shouldDeleteTicket =
        publishConfig.deleteTicket ?? _confirmDeleteTicket(ticketName);
    if (!shouldDeleteTicket) {
      taskLog(
        yellow(
          'Skipped deleting repositories in ticket $ticketName.',
        ),
      );
      taskLog(
        '✅ All repositories in ticket $ticketName published successfully.',
      );
      return;
    }

    for (final repo in subs) {
      final repoDir = repo.directory;
      final repoName = path.basename(repoDir.path);

      try {
        await _deleteRemoteBranch(
          repoDir: repoDir,
          branchName: ticketName,
          ggLog: taskLog,
        );

        if (repoDir.existsSync()) {
          repoDir.deleteSync(recursive: true);
          taskLog(
            green(
              'Deleted repository $repoName from ticket $ticketName after '
              'successful publish.',
            ),
          );
        }
      } catch (e) {
        ggLog(
          red(
            'Failed to delete repository $repoName from ticket $ticketName: '
            '$e',
          ),
        );
      }
    }

    taskLog('✅ All repos published');
  }

  /// Resolves the publish configuration for the ticket in [ticketDir] and
  /// makes sure a runtime copy lives at [runtimeFile] (the resume anchor).
  ///
  /// Precedence: on `--continue` the runtime file must already exist; else an
  /// explicit `--config` file, then the runtime file, then the legacy
  /// `<ticket>/.gg-publish.json`, and finally an interactive
  /// `do configure-publish`. `--reconfigure` skips the two implicit files so
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
    required bool reconfigure,
    required String? messageArg,
    required GgLog ggLog,
  }) async {
    if (continueRun && (configArg != null || reconfigure)) {
      throw Exception(
        '--continue cannot be combined with --config or --reconfigure. '
        'Resume with "--continue" alone, or start a fresh run without it.',
      );
    }

    if (continueRun) {
      if (!runtimeFile.existsSync()) {
        throw Exception(
          'Nothing to continue: ${runtimeFile.path} does not exist. Start a '
          'normal "gg do publish" first.',
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

    if (reconfigure && runtimeFile.existsSync()) {
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

    if (!reconfigure && runtimeFile.existsSync()) {
      final config = gg.PublishConfig.load(
        configArg: runtimeFile.path,
        fallbackDir: ticketDir.path,
      );
      // A runtime file carrying progress markers is the leftover of an
      // unfinished run — do not silently reuse it as plain config.
      if (config.repos.values.any((r) => r.status != null)) {
        throw Exception(
          'An unfinished publish left progress in ${runtimeFile.path}. '
          'Resume it with "gg do publish --continue", or discard it with '
          '"gg do publish --reconfigure".',
        );
      }
      return (config: config, sourcePath: runtimeFile.path);
    }

    final legacyFile = File(path.join(ticketDir.path, '.gg-publish.json'));
    if (!reconfigure && legacyFile.existsSync()) {
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
        'An unfinished publish left progress in ${runtimeFile.path}. '
        'Resume it with "gg do publish --continue", or discard it with '
        '"gg do publish --reconfigure".',
      );
    }
  }

  /// Whether [repoDir]'s own `.gg/.gg-publish.json` records completed publish
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
  /// push and finally `gg do publish`.
  Future<void> _publishRepo({
    required Directory repoDir,
    required String repoName,
    required Map<String, String> refVersions,
    required gg.PublishConfig publishConfig,
    required String configPath,
    required bool resume,
    required bool? pr,
    required bool verbose,
    required GgLog ggLog,
    required GgLog taskLog,
  }) async {
    // Make sure the repo-level runtime file gg_one writes is gitignored —
    // the entry rides along the force-commit below, no extra commit needed.
    await _ensureIgnored.ensure(directory: repoDir, commit: false);

    try {
      await _unlocalizeRefs.get(directory: repoDir, ggLog: taskLog);
      taskLog(green('$repoName: unlocalized refs.'));
    } catch (e) {
      throw Exception('Failed to unlocalize refs for $repoName: $e');
    }

    try {
      await _restorePublishTo.exec(directory: repoDir, ggLog: taskLog);
    } catch (e) {
      throw Exception('Failed to restore publish_to for $repoName: $e');
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
        throw Exception('Failed to update version of $refName '
            'in $repoName: $e');
      }
    }

    // Refresh deps after manifest edits (refs, publish_to, versions).
    await _refreshDependencies(
      repoDir: repoDir,
      repoName: repoName,
      ggLog: taskLog,
    );

    // Commit
    await _ggDoCommit.exec(
      directory: repoDir,
      ggLog: taskLog,
      message: 'Gg Multi: changed references to pub.dev',
      force: true,
    );

    // Push
    await _ggDoPush.exec(directory: repoDir, ggLog: taskLog);

    taskLog(green('$repoName: updated with new references.'));

    // The publish configuration is always resolved up front, so every repo
    // has an explicit merge message and version increment here.
    final resolved = publishConfig.forRepo(
      repoName: repoName,
      configPath: configPath,
    );
    final publishMessage = resolved.mergeMessage;
    final publishVersionIncrement = resolved.versionIncrement;
    final publishChannel = publishConfig.channelForRepo(repoName);

    // gg do publish; multi flow is non-interactive (no confirm prompt).
    // On --continue, gg_one resumes at the first step its repo-level
    // .gg/.gg-publish.json marks as not done yet.
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
      ggLog(green('Saved state of $repoName'));
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
        'Failed to save the state of $repoName before publishing — $repoName '
        'was not changed (repositories published earlier in this run stay '
        'published): $e',
      );
    }
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
        red(
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
        yellow(
          '$repoName: back on ${s.branch}, but all commits were kept '
          'because $reason. Re-running "gg do publish" resumes the publish.',
        ),
      );
      return;
    }

    // Nothing irreversible happened — restore the full snapshot.
    await _runGit(<String>['reset', '--hard', s.head], repoDir: repoDir);

    // gg_one's runtime .gg/.gg-publish.json is gitignored and survives the
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

    taskLog(green('Restored the state before the publish in $repoName'));
    ggLog(
      yellow(
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
        ggLog(green('Executed $cmd in $repoName.'));
      } else {
        throw Exception(
          'Failed to execute $cmd in $repoName: ${result.stderr}',
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
      throw Exception(
        'Failed to delete remote branch $branchName for $repoName: '
        '${result.stderr}',
      );
    }

    ggLog(
      green(
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

  /// Asks the user whether the ticket repositories should be deleted.
  static bool _defaultConfirmDeleteTicket(String ticketName) {
    gg.throwWhenNotATerminal(
      'the delete-ticket prompt',
      'set delete_ticket in .gg/.gg-publish.json (or --config)',
    );
    final selected = Select(
      prompt: 'Delete ticket $ticketName and remove remote feature branches?',
      options: ['No', 'Yes'],
      initialIndex: 1,
    ).interact();
    return selected == 1;
  }
  // coverage:ignore-end

  // Adds command line arguments
  void _addArgs() {
    argParser.addOption(
      'message',
      abbr: 'm',
      help: 'Default merge message used only when the .gg/.gg-publish.json is '
          'written interactively (a fresh run or --reconfigure). It seeds '
          'every repo\'s merge-message prompt. Ignored when a config already '
          'exists or is supplied via --config.',
    );
    argParser.addOption(
      'config',
      help: 'Path to a .gg-publish.json file with per-repo merge_message + '
          'version_increment, plus the optional ticket-wide '
          '`delete_ticket` flag. Resolved as-given (CWD), then under the '
          'ticket directory. Copied to .gg/.gg-publish.json for the run.',
    );
    argParser.addFlag(
      'pr',
      help: 'Merge each repo through an auto-merge pull request and wait '
          'until the provider merged it (default). --no-pr performs local '
          'merges followed by direct pushes to main instead.',
      defaultsTo: true,
      negatable: true,
    );
    argParser.addFlag(
      'continue',
      help: 'Resume a previously failed publish from where it stopped, '
          'reusing .gg/.gg-publish.json and skipping already-published repos.',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'reconfigure',
      help: 'Ignore an existing .gg/.gg-publish.json and configure the '
          'publish again via do configure-publish.',
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
