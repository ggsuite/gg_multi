// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg/gg.dart' as gg;
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_localize_refs/gg_localize_refs.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:interact/interact.dart';
import 'package:path/path.dart' as path;

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
    EditMessage? editMessage,
    ConfirmDeleteTicket? confirmDeleteTicket,
  })  : _ggDoCommit = ggDoCommit ?? gg.DoCommit(ggLog: ggLog),
        _unlocalizeRefs = unlocalizeRefs ?? ChangeRefsToPubDev(ggLog: ggLog),
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
    bool? force,
    String? message,
    bool? verbose,
  }) =>
      get(
        directory: directory,
        ggLog: ggLog,
        force: force,
        message: message,
        verbose: verbose,
      );

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    bool? force,
    String? message,
    bool? verbose,
  }) async {
    force ??= argResults?['force'] as bool? ?? false;
    message ??= argResults?['message'] as String?;
    verbose ??= argResults?['verbose'] as bool? ?? false;

    final GgLog taskLog = verbose ? ggLog : <String>[].add;

    // Step 1: Detect ticket folder
    final String? ticketPath = WorkspaceUtils.detectTicketPath(
      path.absolute(directory.path),
    );
    if (ticketPath == null) {
      throw Exception('This command must be executed inside a ticket folder.');
    }

    final ticketDir = Directory(ticketPath);
    final ticketName = path.basename(ticketDir.path);
    final ticketDescription = _readTicketDescription(ticketDir);

    // Step 2: Run kidney_core do review
    try {
      await _doReviewCommand.exec(
        directory: ticketDir,
        ggLog: ggLog,
        verbose: verbose,
      );
    } catch (e) {
      throw Exception('kidney_core do review failed: $e');
    }

    // Step 3: Run kidney_core can publish
    try {
      await _canPublishCommand.exec(directory: ticketDir, ggLog: ggLog);
    } catch (e) {
      throw Exception('kidney_core can publish failed: $e');
    }

    // Get sorted repos
    final subs = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (subs.isEmpty) {
      ggLog(yellow('⚠️ No repositories found in ticket $ticketName.'));
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

      // Skip confirmation when --force is set
      if (!force) {
        // coverage:ignore-start
        final answer = Confirm(
          prompt: 'Ready to publish $repoName in ticket $ticketName?',
          defaultValue: false,
          waitForNewLine: true,
        ).interact();
        if (answer == false) {
          return;
        }
        // coverage:ignore-end
      }

      ggLog(yellow('Publishing $repoName ...'));

      try {
        await _unlocalizeRefs.get(directory: repoDir, ggLog: taskLog);
        taskLog(green('$repoName: unlocalized refs.'));
      } catch (e) {
        throw Exception('Failed to unlocalize refs for $repoName: $e');
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

      // Commit
      await _ggDoCommit.exec(
        directory: repoDir,
        ggLog: taskLog,
        message: 'Kidney: changed references to pub.dev',
        force: true,
      );

      // Push
      await _ggDoPush.exec(directory: repoDir, ggLog: taskLog);

      taskLog(green('$repoName: updated with new references.'));

      final initialPublishMessage = message ?? ticketDescription;
      final publishMessage = await _editMessage(initialPublishMessage ?? '');

      // Execute gg do publish
      await _ggDoPublish.exec(
        directory: repoDir,
        ggLog: ggLog,
        message: publishMessage,
      );

      // Capture current repo version and propagate known versions
      try {
        final version = await _getVersion.get(
          directory: repoDir,
        );
        if (version != null && version.isNotEmpty) {
          refVersions[repoName] = version;

          final publishInfo = await _pubDevChecker.getPackagePublishInfo(
            packageName: repoName,
          );
          publishedPackages[repoName] = _PublishedPackageState(
            packageName: repoName,
            version: version,
            waitsForPubDev: publishInfo.waitsForPubDev,
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

    taskLog(
      '✅ All repositories in ticket $ticketName published successfully.',
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

      await GgStatusPrinter<void>(
        message: 'Waiting for ${state.packageName} '
            '^${state.version} to appear on pub.dev',
        ggLog: ggLog,
      ).run(
        () async => _pubDevChecker.waitUntilVersionAvailable(
          packageName: state.packageName,
          version: state.version,
          ggLog: ggLog,
        ),
      );

      confirmedPubDevVersions.add(cacheKey);
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
    return Confirm(
      prompt: 'Delete ticket $ticketName and remove remote feature branches?',
      defaultValue: false,
      waitForNewLine: true,
    ).interact();
  }
  // coverage:ignore-end

  // Adds command line arguments
  void _addArgs() {
    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Skip confirmation prompts and continue without asking.',
      defaultsTo: false,
      negatable: true,
    );
    argParser.addOption(
      'message',
      abbr: 'm',
      help: 'The merge commit message.',
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
  });

  /// The public package name.
  final String packageName;

  /// The published version.
  final String version;

  /// Whether the next packages must wait for pub.dev visibility.
  final bool waitsForPubDev;
}

/// Mock for [DoPublishCommand]
class MockDoPublishCommand extends MockDirCommand<void>
    implements DoPublishCommand {}
