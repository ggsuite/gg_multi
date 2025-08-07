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
    gg.DoMerge? ggDoMerge,
    gg.DoPublish? ggDoPublish,
    SortedProcessingList? sortedProcessingList,
    ProcessRunner? processRunner,
    CanPublishCommand? canPublishCommand,
  })  : _ggDoMerge = ggDoMerge ?? gg.DoMerge(ggLog: ggLog),
        _ggDoPublish = ggDoPublish ?? gg.DoPublish(ggLog: ggLog),
        _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog),
        _canPublishCommand =
            canPublishCommand ?? CanPublishCommand(ggLog: ggLog);

  /// Instance of gg DoMerge
  final gg.DoMerge _ggDoMerge;

  /// Instance of gg DoPublish
  final gg.DoPublish _ggDoPublish;

  /// Instance of SortedProcessingList
  final SortedProcessingList _sortedProcessingList;

  /// Instance of CanPublishCommand
  final CanPublishCommand _canPublishCommand;

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
  }) =>
      get(
        directory: directory,
        ggLog: ggLog,
      );

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
  }) async {
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

    // Step 2: Run kidney_core can publish
    try {
      await _canPublishCommand.exec(directory: ticketDir, ggLog: ggLog);
    } catch (e) {
      ggLog(red('kidney_core can publish failed: $e'));
      throw Exception('kidney_core can publish failed');
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

    // Step 3-4: Iterate over each repository and perform merge and publish
    final failedRepos = <String>[];
    for (final repo in subs) {
      final repoDir = repo.directory;
      final repoName = path.basename(repoDir.path);

      if(StatusUtils.readStatus(repoDir, ggLog: ggLog) ==
          StatusUtils.statusMerged) {
        ggLog(
          yellow('Repository $repoName in ticket '
              '$ticketName is already merged.'),
        );
        continue;
      }

      final answer = Confirm(
        prompt: 'Ready to publish $repoName in ticket $ticketName?',
        defaultValue: false, // this is optional
        waitForNewLine: true, // optional and will be false by default
      ).interact();
      if(answer == false) {
        return;
      }

      ggLog(yellow('Publishing $repoName in ticket $ticketName...'));
      try {
        // Execute gg do merge
        await _ggDoMerge.exec(directory: repoDir, ggLog: ggLog);
        // Set status to merged
        StatusUtils.setStatus(repoDir, StatusUtils.statusMerged, ggLog: ggLog);
        // Execute gg do publish
        await _ggDoPublish.exec(directory: repoDir, ggLog: ggLog);
      } catch (e) {
        ggLog(red('❌ Failed to publish $repoName: $e'));
        failedRepos.add(repoName);
      }
    }

    // Summarize the results
    if (failedRepos.isEmpty) {
      ggLog(
        green(
          '✅ All repositories in ticket $ticketName published successfully.',
        ),
      );
    } else {
      ggLog(
        red(
          '❌ Failed to publish the following '
          'repositories in ticket $ticketName:',
        ),
      );
      for (final repoName in failedRepos) {
        ggLog(red(' - $repoName'));
      }
      throw Exception(
        'Failed to publish some repositories in ticket $ticketName',
      );
    }
  }
}

/// Mock for [DoPublishCommand]
class MockDoPublishCommand extends MockDirCommand<void>
    implements DoPublishCommand {}
