// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg/gg.dart' as gg;
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;

import '../../backend/workspace_utils.dart';

/// Command to check if all repos in the ticket were pushed.
class DidPushCommand extends DirCommand<void> {
  /// Creates a new did push command.
  DidPushCommand({
    required super.ggLog,
    super.name = 'push',
    super.description =
        'Checks if all repositories in the current ticket were pushed.',
    gg.DidPush? ggDidPush,
    SortedProcessingList? sortedProcessingList,
  })  : _ggDidPush = ggDidPush ?? gg.DidPush(ggLog: ggLog),
        _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog);

  /// gg command that checks whether a repository was pushed.
  final gg.DidPush _ggDidPush;

  /// Sorted processing list for repos.
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
      ggLog(yellow('⚠️ No repositories found in ticket $ticketName.'));
      return;
    }

    for (final node in nodes) {
      final repoDir = node.directory;
      final repoName = path.basename(repoDir.path);
      ggLog(
        yellow(
          'Checking if $repoName in ticket $ticketName was pushed...',
        ),
      );
      try {
        await _ggDidPush.exec(directory: repoDir, ggLog: ggLog);
      } catch (e) {
        ggLog(red('❌ $repoName was not pushed: $e'));
        rethrow;
      }
    }

    ggLog('✅ All repositories in ticket $ticketName were pushed.');
  }
}

/// Mock for [DidPushCommand]
class MockDidPushCommand extends MockDirCommand<void>
    implements DidPushCommand {}
