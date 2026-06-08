// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_one/gg_one.dart' as gg;
import 'package:gg_lang/gg_lang.dart' as gg_lang;
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_localize_refs/gg_localize_refs.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:interact/interact.dart';
import 'package:path/path.dart' as path;

import '../../backend/npm_registry_checker.dart';
import '../../backend/pub_dev_checker.dart';
import '../../backend/workspace_utils.dart';
import '../../commands/can/publish.dart';
import 'review.dart';

/// Typedef for running processes (for injection & tests).
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

/// Typedef for launching an interactive editor.
typedef EditMessage = Future<String?> Function(String initialMessage);

/// Typedef for asking the user whether the ticket should be deleted.
typedef ConfirmDeleteTicket = bool Function(String ticketName);

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
    EditMessage? editMessage,
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
        _editMessage = editMessage ?? _defaultEditMessage,
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

  /// Opens an interactive editor for the publish message.
  final EditMessage _editMessage;

  /// Runs shell commands such as branch deletion.
  final ProcessRunner _processRunner;

  /// Asks the user whether the ticket should be deleted.
  final ConfirmDeleteTicket _confirmDeleteTicket;

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    String? message,
    bool? verbose,
  }) =>
      get(
        directory: directory,
        ggLog: ggLog,
        message: message,
        verbose: verbose,
      );

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    String? message,
    bool? verbose,
  }) async {
    message ??= argResults?['message'] as String?;
    verbose ??= argResults?['verbose'] as bool? ?? false;

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
    final ticketDescription = _readTicketDescription(ticketDir);

    // --config <path>: load .gg-publish.json once for the whole ticket. Per
    // repo, fall back to top-level defaults when no override is provided.
    final String? configArg = argResults?['config'] as String?;
    final gg.PublishConfig? publishConfig = configArg == null
        ? null
        : gg.PublishConfig.load(
            configArg: configArg,
            fallbackDir: ticketDir.path,
          );

    // Step 2: Run gg_multi do review
    try {
      await _doReviewCommand.exec(
        directory: ticketDir,
        ggLog: ggLog,
        verbose: verbose,
      );
    } catch (e) {
      throw Exception('gg_multi do review failed: $e');
    }

    // Step 3: Run gg_multi can publish
    try {
      await _canPublishCommand.exec(directory: ticketDir, ggLog: ggLog);
    } catch (e) {
      throw Exception('gg_multi can publish failed: $e');
    }

    // Get sorted repos
    final subs = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (subs.isEmpty) {
      ggLog(yellow('⚠️ No repos in this ticket'));
      return;
    }

    final publishedPackages = <String, _PublishedPackageState>{};
    final confirmedPubDevVersions = <String>{};

    // Map of reference name to version captured from repos processed so far.
    final refVersions = <String, String>{};

    // Step 3-4: Iterate over each repository and perform publish
    for (final repo in subs) {
      final repoDir = repo.directory;
      final repoName = path.basename(repoDir.path);

      await _waitForPublishedDependenciesIfNeeded(
        currentRepo: repo,
        publishedPackages: publishedPackages,
        confirmedPubDevVersions: confirmedPubDevVersions,
        ggLog: ggLog,
      );

      ggLog('${cyan(repoName)}:');

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
            await _setRefVersion.get(
              directory: repoDir,
              ref: refName,
              version: '^$refVersion',
            );
          }
        } catch (e) {
          throw Exception('Failed to update version of $refName '
              'in $repoName: $e');
        }
      }

      // Refresh dependencies for the detected project type after the
      // pubspec.yaml / package.json changes above (unlocalize refs,
      // restore publish_to, updated dependency versions).
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

      // Resolve merge message + version increment from --config when present,
      // otherwise fall back to the CLI `--message` flag or .ticket description
      // and ask the user via _editMessage (existing behaviour).
      final String publishMessage;
      final String? publishVersionIncrement;
      if (publishConfig != null) {
        final resolved = publishConfig.forRepo(
          repoName: repoName,
          configPath: configArg!,
        );
        publishMessage = resolved.mergeMessage;
        publishVersionIncrement = resolved.versionIncrement;
      } else {
        final initialPublishMessage = message ?? ticketDescription;
        publishMessage = await _editMessage(initialPublishMessage ?? '') ?? '';
        publishVersionIncrement = null;
      }

      // Execute gg do publish. The multi-publish flow is inherently
      // non-interactive (it loops across many repos in dependency order),
      // so we never prompt before pushing to pub.dev / npm here — callers
      // who want a confirmation should run `gg one do publish` per repo.
      await _ggDoPublish.exec(
        directory: repoDir,
        ggLog: ggLog,
        message: publishMessage,
        deleteFeatureBranch: false,
        verbose: verbose,
        versionIncrement: publishVersionIncrement,
        askBeforePublishing: false,
      );

      // Capture current repo version and propagate known versions
      try {
        final version = await _getVersion.get(
          directory: repoDir,
        );
        if (version != null && version.isNotEmpty) {
          // Use the published package name from the manifest (e.g. the
          // scoped »@org/pkg« for npm) rather than the repository directory
          // name, so dependency keys and registry lookups resolve correctly.
          final packageName = await _readManifestName(repoDir, repoName);
          refVersions[packageName] = version;

          final projectType = _detectProjectType(repoDir);
          final publishInfo = projectType == gg.ProjectType.typescript
              ? await _npmChecker.getPackagePublishInfo(
                  packageName: packageName,
                )
              : await _pubDevChecker.getPackagePublishInfo(
                  packageName: packageName,
                );
          publishedPackages[packageName] = _PublishedPackageState(
            packageName: packageName,
            version: version,
            waitsForPubDev: publishInfo.waitsForPubDev,
            projectType: projectType,
          );
        }
      } catch (e) {
        throw Exception('Failed to get version of $repoName: $e');
      }

      taskLog(green('$repoName: published successfully.'));
    }

    final shouldDeleteTicket = _confirmDeleteTicket(ticketName);
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

      final registryName =
          state.projectType == gg.ProjectType.typescript ? 'npm' : 'pub.dev';
      await GgStatusPrinter<void>(
        message: 'Waiting for ${state.packageName} '
            '^${state.version} to appear on $registryName',
        ggLog: ggLog,
      ).run(
        () async => state.projectType == gg.ProjectType.typescript
            ? _npmChecker.waitUntilVersionAvailable(
                packageName: state.packageName,
                version: state.version,
                ggLog: ggLog,
              )
            : _pubDevChecker.waitUntilVersionAvailable(
                packageName: state.packageName,
                version: state.version,
                ggLog: ggLog,
              ),
      );

      confirmedPubDevVersions.add(cacheKey);
    }
  }

  /// Detects the project type of [repoDir], defaulting to Dart for repos
  /// without a recognizable manifest (so they use the pub.dev checker).
  gg.ProjectType _detectProjectType(Directory repoDir) {
    try {
      return gg.detectProjectType(repoDir);
    } catch (_) {
      // Defensive: a repo being published always has a manifest.
      return gg.ProjectType.dart; // coverage:ignore-line
    }
  }

  /// Reads the published package name from the manifest of [repoDir]
  /// (e.g. the scoped »@org/pkg« for npm). Falls back to [fallback] (the
  /// repository directory name) when the manifest cannot be read.
  Future<String> _readManifestName(Directory repoDir, String fallback) async {
    try {
      final catalog = await gg_lang.LanguageCatalog.load();
      return await gg_lang.Manifest.detect(repoDir, catalog).readName();
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
      throw Exception(
        'Failed to execute $cmd in $repoName: ${result.stderr}',
      );
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

  /// Reads the optional description from the ticket configuration file.
  String? _readTicketDescription(Directory ticketDir) {
    final ticketFile = File(path.join(ticketDir.path, '.ticket'));
    if (!ticketFile.existsSync()) {
      return null;
    }

    final decoded = jsonDecode(ticketFile.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final description = decoded['description']?.toString().trim();
    if (description == null || description.isEmpty) {
      return null;
    }

    return description;
  }

  /// Opens the default editor with [initialMessage] and returns the result.
  // coverage:ignore-start
  static Future<String?> _defaultEditMessage(String initialMessage) async {
    return Input(
      prompt: 'Edit merge message',
      defaultValue: initialMessage,
      initialText: initialMessage,
    ).interact();
  }

  /// Runs system processes with shell support.
  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: true,
    );
  }

  /// Asks the user whether the ticket repositories should be deleted.
  static bool _defaultConfirmDeleteTicket(String ticketName) {
    final selected = Select(
      prompt: 'Delete ticket $ticketName and remove remote feature branches?',
      options: ['No', 'Yes'],
      initialIndex: 0,
    ).interact();
    return selected == 1;
  }
  // coverage:ignore-end

  // Adds command line arguments
  void _addArgs() {
    argParser.addOption(
      'message',
      abbr: 'm',
      help: 'The merge commit message.',
    );
    argParser.addOption(
      'config',
      help: 'Path to a .gg-publish.json file with per-repo merge_message + '
          'version_increment. Resolved as-given (CWD), then under the ticket '
          'directory.',
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
  });

  /// The public package name.
  final String packageName;

  /// The published version.
  final String version;

  /// Whether the next packages must wait for registry visibility.
  final bool waitsForPubDev;

  /// The project type — selects the registry (pub.dev vs npm) to wait on.
  final gg.ProjectType projectType;
}

/// Mock for [DoPublishCommand]
class MockDoPublishCommand extends MockDirCommand<void>
    implements DoPublishCommand {}
