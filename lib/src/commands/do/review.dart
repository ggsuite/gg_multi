// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_localize_refs/gg_localize_refs.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;

import '../../backend/workspace_utils.dart';
import '../../backend/status_utils.dart';
import '../../commands/can/review.dart';

/// Command to review all repos in the ticket.
class DoReviewCommand extends DirCommand<void> {
  /// Constructor
  DoReviewCommand({
    required super.ggLog,
    super.name = 'review',
    super.description = 'Reviews all repositories in the current ticket.',
    CanReviewCommand? canReviewCommand,
    UnlocalizeRefs? unlocalizeRefs,
    LocalizeRefs? localizeRefs,
    SortedProcessingList? sortedProcessingList,
  })  : _canReviewCommand = canReviewCommand ?? CanReviewCommand(ggLog: ggLog),
        _unlocalizeRefs = unlocalizeRefs ?? UnlocalizeRefs(ggLog: ggLog),
        _localizeRefs = localizeRefs ?? LocalizeRefs(ggLog: ggLog),
        _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog);

  /// Instance of CanReviewCommand
  final CanReviewCommand _canReviewCommand;

  /// Instance of UnlocalizeRefs
  final UnlocalizeRefs _unlocalizeRefs;

  /// Instance of LocalizeRefs
  final LocalizeRefs _localizeRefs;

  /// Instance of SortedProcessingList
  final SortedProcessingList _sortedProcessingList;

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
    // Step 1: Run can review
    try {
      await _canReviewCommand.exec(directory: directory, ggLog: ggLog);
    } catch (e) {
      ggLog(red('kidney_core can review failed: $e'));
      throw Exception('kidney_core can review failed');
    }

    // Step 2: Detect ticket folder
    final String? ticketPath = WorkspaceUtils.detectTicketPath(
      path.absolute(directory.path),
    );
    if (ticketPath == null) {
      // coverage:ignore-start
      ggLog(red('This command must be executed inside a ticket folder.'));
      throw Exception('Not inside a ticket folder');
      // coverage:ignore-end
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

    // Step 3: Perform unlocalize and localize for each repo
    final failedRepos = <String>[];
    for (final repo in subs) {
      final repoDir = repo.directory;
      final repoName = path.basename(repoDir.path);
      bool okUnloc = false;
      try {
        await _unlocalizeRefs.get(directory: repoDir, ggLog: ggLog);
        ggLog(green('Unlocalized refs for $repoName'));
        StatusUtils.setStatus(
          repoDir,
          StatusUtils.statusUnlocalized,
          ggLog: ggLog,
        );
        okUnloc = true;
      } catch (e) {
        ggLog(red('Failed to unlocalize refs for $repoName: $e'));
        okUnloc = false;
      }
      if (!okUnloc) {
        failedRepos.add(repoName);
        continue;
      }
      try {
        await _localizeRefs.get(directory: repoDir, ggLog: ggLog, git: true);
        ggLog(green('Localized refs for $repoName'));
        StatusUtils.setStatus(
          repoDir,
          StatusUtils.statusGitLocalized,
          ggLog: ggLog,
        );
      } catch (e) {
        ggLog(red('Failed to localize refs with --git for $repoName: $e'));
        failedRepos.add(repoName);
      }
    }

    // Summarize the results
    if (failedRepos.isEmpty) {
      ggLog(
        green('✅ All repositories in ticket '
            '$ticketName reviewed successfully.'),
      );
    } else {
      ggLog(
        red(
          '❌ Failed to review the following '
          'repositories in ticket $ticketName:',
        ),
      );
      for (final repoName in failedRepos) {
        ggLog(red(' - $repoName'));
      }
      throw Exception(
        'Failed to review some repositories in ticket $ticketName',
      );
    }
  }
}

/// Mock for [DoReviewCommand]
class MockDoReviewCommand extends MockDirCommand<void>
    implements DoReviewCommand {}
