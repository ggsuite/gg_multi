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
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;

import '../../backend/workspace_utils.dart';

/// Command to check if all repos in the ticket can be committed.
class CanCommitCommand extends DirCommand<void> {
  /// Constructor
  CanCommitCommand({
    required super.ggLog,
    super.name = 'commit',
    super.description =
        'Checks if all repositories in the current ticket can be committed.',
    gg.CanCommit? ggCanCommit,
    SortedProcessingList? sortedProcessingList,
  })  : _ggCanCommit = ggCanCommit ?? gg.CanCommit(ggLog: ggLog),
        _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog);

  /// Instance of gg CanCommit
  final gg.CanCommit _ggCanCommit;

  /// Sorted processing list for repos
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
    // Detect if we are inside a ticket folder
    final String? ticketPath = WorkspaceUtils.detectTicketPath(
      path.absolute(directory.path),
    );
    if (ticketPath == null) {
      ggLog(red('This command must be executed inside a ticket folder.'));
      throw Exception('Not inside a ticket folder');
    }

    final ticketDir = Directory(ticketPath);
    final ticketName = path.basename(ticketDir.path);

    // Collect all repository directories in the ticket via SortedProcessingList
    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (nodes.isEmpty) {
      ggLog(yellow('⚠️ No repositories found in ticket $ticketName.'));
      return;
    }

    // Iterate over each repository and check if it can be committed
    for (final node in nodes) {
      final repoDir = node.directory;
      final repoName = path.basename(repoDir.path);
      ggLog(
        yellow(
          'Checking if $repoName in ticket $ticketName can be committed...',
        ),
      );
      try {
        await _ggCanCommit.exec(directory: repoDir, ggLog: ggLog);
      } catch (e) {
        ggLog(red('❌ Cannot commit $repoName: $e'));
        rethrow;
      }
    }

    // All successful
    ggLog('✅ All repositories in ticket $ticketName can be committed.');
  }
}

/// Mock for [CanCommitCommand]
class MockCanCommitCommand extends MockDirCommand<void>
    implements CanCommitCommand {}
