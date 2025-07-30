// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
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

/// Command to check if all repos in the ticket can be pushed.
class CanPushCommand extends DirCommand<void> {
  /// Constructor
  CanPushCommand({
    required super.ggLog,
    super.name = 'push',
    super.description =
        'Checks if all repositories in the current ticket can be pushed.',
    gg.CanPush? ggCanPush,
  }) : _ggCanPush = ggCanPush ?? gg.CanPush(ggLog: ggLog);

  /// Instance of gg CanPush
  final gg.CanPush _ggCanPush;

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

    // Collect all repository directories in the ticket
    final subs = ticketDir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

    if (subs.isEmpty) {
      ggLog(yellow('⚠️ No repositories found in ticket $ticketName.'));
      return;
    }

    // Iterate over each repository and check if it can be pushed
    for (final repoDir in subs) {
      final repoName = path.basename(repoDir.path);
      ggLog(
        yellow(
          'Checking if $repoName in ticket $ticketName can be pushed...',
        ),
      );
      try {
        await _ggCanPush.exec(directory: repoDir, ggLog: ggLog);
      } catch (e) {
        ggLog(red('❌ Cannot push $repoName: $e'));
        rethrow;
      }
    }

    // All successful
    ggLog(green('✅ All repositories in ticket $ticketName can be pushed.'));
  }
}

/// Mock for [CanPushCommand]
class MockCanPushCommand extends MockDirCommand<void>
    implements CanPushCommand {}
