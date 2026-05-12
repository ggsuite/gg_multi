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

/// Command to check if all repos in the ticket can be pushed.
class CanPushCommand extends DirCommand<void> {
  /// Constructor
  CanPushCommand({
    required super.ggLog,
    super.name = 'push',
    super.description =
        'Checks if all repositories in the current ticket can be pushed.',
    gg.CanPush? ggCanPush,
    SortedProcessingList? sortedProcessingList,
  })  : _ggCanPush = ggCanPush ?? gg.CanPush(ggLog: ggLog),
        _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog);

  /// Instance of gg CanPush
  final gg.CanPush _ggCanPush;

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
    // Collect all repository directories in the ticket via SortedProcessingList
    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (nodes.isEmpty) {
      ggLog(yellow('⚠️ No repos in this ticket'));
      return;
    }

    // Iterate over each repository and check if it can be pushed
    for (final node in nodes) {
      final repoDir = node.directory;
      final repoName = path.basename(repoDir.path);
      ggLog('${cyan(repoName)}:');
      try {
        await _ggCanPush.exec(directory: repoDir, ggLog: ggLog);
      } catch (e) {
        ggLog(red('❌ Cannot push $repoName: $e'));
        rethrow;
      }
    }

    // All successful
    ggLog('✅ All repos can be pushed');
  }
}

/// Mock for [CanPushCommand]
class MockCanPushCommand extends MockDirCommand<void>
    implements CanPushCommand {}
