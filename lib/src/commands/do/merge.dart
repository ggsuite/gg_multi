// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg/gg.dart' as gg;
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;

import '../../backend/workspace_utils.dart';
import '../../backend/status_utils.dart';

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

/// Command to squash-merge the ticket branch into main,
/// checkout main, and push for all repos in the current ticket.
class DoMergeCommand extends DirCommand<void> {
  /// Constructor
  DoMergeCommand({
    required super.ggLog,
    super.name = 'merge',
    super.description = 'Squash-merges the ticket branch into main, '
        'checks out main, and pushes for all repos in the ticket.',
    gg.CanCommit? ggCanCommit,
    gg.DoCommit? ggDoCommit,
    ProcessRunner? processRunner,
  })  : _ggCanCommit = ggCanCommit ?? gg.CanCommit(ggLog: ggLog),
        _ggDoCommit = ggDoCommit ?? gg.DoCommit(ggLog: ggLog),
        _processRunner = processRunner ?? _defaultProcessRunner;

  /// Instance of gg CanCommit
  final gg.CanCommit _ggCanCommit;

  /// Instance of gg DoCommit
  final gg.DoCommit _ggDoCommit;

  /// The process runner
  final ProcessRunner _processRunner;

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
      ggLog(red('Merge must be executed inside a ticket folder.'));
      throw Exception('Not inside a ticket folder');
    }

    final ticketDir = Directory(ticketPath);
    final ticketName = path.basename(ticketDir.path);

    // Collect all repository directories in the ticket
    final subs = ticketDir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

    if (subs.isEmpty) {
      ggLog(yellow('⚠️ No repositories found in ticket $ticketName.'));
      return;
    }

    // Iterate over each repository and perform the merge
    final failedRepos = <String>[];
    for (final repoDir in subs) {
      final repoName = path.basename(repoDir.path);
      ggLog(yellow('Merging $repoName in ticket $ticketName...'));
      try {
        // Step 2: Check status
        final status = StatusUtils.readStatus(repoDir, ggLog: ggLog);
        if (status != StatusUtils.statusGitLocalized) {
          throw Exception('Please execute kidney_core review before merging');
        }

        // Step 3: gg can commit
        await _ggCanCommit.exec(directory: repoDir, ggLog: ggLog);

        // Step 4: Squash and merge into main
        final mergeResult = await _processRunner(
          'git',
          ['-C', repoDir.path, 'merge', '--squash', ticketName],
        );
        if (mergeResult.exitCode != 0) {
          throw Exception('git merge --squash failed: ${mergeResult.stderr}');
        }
        await _ggDoCommit.exec(
          directory: repoDir,
          ggLog: ggLog,
          message: 'Squash-merge of $ticketName',
          updateChangeLog: false,
        );

        // Step 5: Checkout main and set status
        final checkoutResult = await _processRunner(
          'git',
          ['-C', repoDir.path, 'checkout', 'main'],
        );
        if (checkoutResult.exitCode != 0) {
          throw Exception('git checkout main failed: ${checkoutResult.stderr}');
        }
        StatusUtils.setStatus(
          repoDir,
          StatusUtils.statusLocalMerged,
          ggLog: ggLog,
        );

        // Step 6: gg can commit again
        await _ggCanCommit.exec(directory: repoDir, ggLog: ggLog);

        // Step 7: Push main and set status
        final pushResult = await _processRunner(
          'git',
          ['-C', repoDir.path, 'push', 'origin', 'main'],
        );
        if (pushResult.exitCode != 0) {
          throw Exception('git push origin main failed: ${pushResult.stderr}');
        }
        StatusUtils.setStatus(repoDir, StatusUtils.statusMerged, ggLog: ggLog);
      } catch (e) {
        ggLog(red('❌ Failed to merge $repoName: $e'));
        failedRepos.add(repoName);
      }
    }

    // Summarize the results
    if (failedRepos.isEmpty) {
      ggLog(
        green('✅ All repositories in ticket $ticketName '
            'merged and pushed successfully.'),
      );
    } else {
      ggLog(
        red(
          '❌ Failed to merge the following '
          'repositories in ticket $ticketName:',
        ),
      );
      for (final repoName in failedRepos) {
        ggLog(red(' - $repoName'));
      }
      throw Exception(
        'Failed to merge some repositories in ticket $ticketName',
      );
    }
  }
}
