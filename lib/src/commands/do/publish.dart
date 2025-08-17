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
import 'package:gg_localize_refs/gg_localize_refs.dart';
import 'package:gg_log/gg_log.dart';
import 'package:interact/interact.dart';
import 'package:path/path.dart' as path;

import '../../backend/workspace_utils.dart';
import '../../backend/status_utils.dart';
import '../../commands/can/publish.dart';

/// Typedef for running processes (for injection & tests).
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

/// Command to publish all repos in the ticket.
class DoPublishCommand extends DirCommand<void> {
  /// Constructor
  DoPublishCommand({
    required super.ggLog,
    super.name = 'publish',
    super.description = 'Publishes all repositories in the current ticket.',
    gg.DoCommit? ggDoCommit,
    UnlocalizeRefs? unlocalizeRefs,
    gg.DoPush? ggDoPush,
    gg.DoMerge? ggDoMerge,
    gg.DoPublish? ggDoPublish,
    SortedProcessingList? sortedProcessingList,
    ProcessRunner? processRunner,
    CanPublishCommand? canPublishCommand,
    GetVersion? getVersionCommand,
    SetRefVersion? setRefVersionCommand,
    GetRefVersion? getRefVersionCommand,
  })  : _ggDoCommit = ggDoCommit ?? gg.DoCommit(ggLog: ggLog),
        _unlocalizeRefs = unlocalizeRefs ?? UnlocalizeRefs(ggLog: ggLog),
        _ggDoPush = ggDoPush ?? gg.DoPush(ggLog: ggLog),
        _ggDoMerge = ggDoMerge ?? gg.DoMerge(ggLog: ggLog),
        _ggDoPublish = ggDoPublish ?? gg.DoPublish(ggLog: ggLog),
        _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog),
        _canPublishCommand =
            canPublishCommand ?? CanPublishCommand(ggLog: ggLog),
        _getVersion = getVersionCommand ?? GetVersion(ggLog: ggLog),
        _setRefVersion = setRefVersionCommand ?? SetRefVersion(ggLog: ggLog),
        _getRefVersion = getRefVersionCommand ?? GetRefVersion(ggLog: ggLog) {
    _addArgs();
  }

  /// Instance of gg DoCommit
  final gg.DoCommit _ggDoCommit;

  /// Instance of UnlocalizeRefs
  final UnlocalizeRefs _unlocalizeRefs;

  /// Instance of gg DoPush
  final gg.DoPush _ggDoPush;

  /// Instance of gg DoMerge
  final gg.DoMerge _ggDoMerge;

  /// Instance of gg DoPublish
  final gg.DoPublish _ggDoPublish;

  /// Instance of SortedProcessingList
  final SortedProcessingList _sortedProcessingList;

  /// Instance of CanPublishCommand
  final CanPublishCommand _canPublishCommand;

  /// Reads the current package version from pubspec.yaml
  final GetVersion _getVersion;

  /// Sets the version/spec of a dependency in pubspec.yaml
  final SetRefVersion _setRefVersion;

  /// Reads the version/spec of a dependency from pubspec.yaml
  final GetRefVersion _getRefVersion;

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    bool? force,
    String? message,
  }) =>
      get(
        directory: directory,
        ggLog: ggLog,
        force: force,
        message: message,
      );

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    bool? force,
    String? message,
  }) async {
    force ??= argResults?['force'] as bool? ?? false;
    message ??= argResults?['message'] as String?;

    // Step 1: Detect ticket folder
    final String? ticketPath = WorkspaceUtils.detectTicketPath(
      path.absolute(directory.path),
    );
    if (ticketPath == null) {
      throw Exception('This command must be executed inside a ticket folder.');
    }

    final ticketDir = Directory(ticketPath);
    final ticketName = path.basename(ticketDir.path);

    // Step 2: Run kidney_core can publish
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

    // Map of reference name to version captured from repos processed so far.
    final refVersions = <String, String>{};

    // Step 3-4: Iterate over each repository and perform merge and publish
    for (final repo in subs) {
      final repoDir = repo.directory;
      final repoName = path.basename(repoDir.path);

      if (StatusUtils.readStatus(repoDir, ggLog: ggLog) ==
          StatusUtils.statusMerged) {
        ggLog(
          yellow('Repository $repoName in ticket '
              '$ticketName is already merged.'),
        );
        continue;
      }

      // Skip confirmation when --force is set
      if (!force) {
        // coverage:ignore-start
        final answer = Confirm(
          prompt: 'Ready to publish $repoName in ticket $ticketName?',
          defaultValue: false, // this is optional
          waitForNewLine: true, // optional and will be false by default
        ).interact();
        if (answer == false) {
          return;
        }
        // coverage:ignore-end
      }

      ggLog(yellow('Publishing $repoName in ticket $ticketName...'));

      try {
        await _unlocalizeRefs.get(directory: repoDir, ggLog: ggLog);
        ggLog(green('$repoName: unlocalized refs.'));
      } catch (e) {
        throw Exception('Failed to unlocalize refs for $repoName: $e');
      }

      // Capture current repo version and propagate known versions
      try {
        final version = await _getVersion.get(
          directory: repoDir,
        );
        if (version != null && version.isNotEmpty) {
          refVersions[repoName] = version;
        }
      } catch (e) {
        throw Exception('Failed to get version of $repoName: $e');
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
      try {
        await _ggDoCommit.exec(
          directory: repoDir,
          ggLog: ggLog,
          message: 'kidney: changed references to pub.dev',
          force: true,
        );
      } catch (e) {
        throw Exception('Failed to commit $repoName: $e');
      }

      // Push
      await _ggDoPush.exec(directory: repoDir, ggLog: ggLog);

      ggLog(green('$repoName: updated with new references.'));

      // Execute gg do merge
      try {
        await _ggDoMerge.exec(
          directory: repoDir,
          ggLog: ggLog,
          local: true,
          message: message,
        );
      } catch (e) {
        throw Exception('Failed to merge $repoName: $e');
      }
      // Set status to merged
      StatusUtils.setStatus(repoDir, StatusUtils.statusMerged, ggLog: ggLog);

      // Commit
      try {
        await _ggDoCommit.exec(
          directory: repoDir,
          ggLog: ggLog,
          message: 'kidney: set kidney status to merged',
          force: true,
        );
      } catch (e) {
        throw Exception('Failed to commit $repoName: $e');
      }

      // Push
      await _ggDoPush.exec(directory: repoDir, ggLog: ggLog);

      ggLog(green('$repoName: merged and pushed.'));

      // Execute gg do publish
      try {
        await _ggDoPublish.exec(directory: repoDir, ggLog: ggLog);
      } catch (e) {
        throw Exception('Failed to publish $repoName: $e');
      }

      ggLog(green('$repoName: published successfully.'));
    }

    ggLog(
      green(
        '✅ All repositories in ticket $ticketName published successfully.',
      ),
    );
  }

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
  }
}

/// Mock for [DoPublishCommand]
class MockDoPublishCommand extends MockDirCommand<void>
    implements DoPublishCommand {}
