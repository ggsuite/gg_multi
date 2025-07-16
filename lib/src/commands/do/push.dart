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

/// Command to push changes across all repositories in the current ticket.
class DoPushCommand extends DirCommand<void> {
  /// Constructor
  DoPushCommand({
    required super.ggLog,
    super.name = 'push',
    super.description =
        'Pushes changes across all repositories in the current ticket.',
    gg.CanPush? ggCanPush,
    gg.DoPush? ggDoPush,
  }) : _ggDoPush = ggDoPush ?? gg.DoPush(ggLog: ggLog) {
    _addArgs();
  }

  /// Instance of gg DoPush to perform the push action
  final gg.DoPush _ggDoPush;

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    bool? force,
  }) =>
      get(
        directory: directory,
        ggLog: ggLog,
        force: force,
      );

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    bool? force,
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

    // Iterate over each repository and perform the push
    final failedRepos = <String>[];
    for (final repoDir in subs) {
      final repoName = path.basename(repoDir.path);
      ggLog(yellow('Pushing $repoName in ticket $ticketName...'));
      try {
        await _ggDoPush.exec(
          directory: repoDir,
          ggLog: ggLog,
          force: force,
        );
      } catch (e) {
        ggLog(red('❌ Failed to push $repoName: $e'));
        failedRepos.add(repoName);
      }
    }

    // Summarize the results
    if (failedRepos.isEmpty) {
      ggLog(
        green('✅ All repositories in ticket $ticketName pushed successfully.'),
      );
    } else {
      ggLog(
        red(
          '❌ Failed to push the following repositories in ticket $ticketName:',
        ),
      );
      for (final repoName in failedRepos) {
        ggLog(red(' - $repoName'));
      }
      throw Exception('Failed to push some repositories in ticket $ticketName');
    }
  }

  // Adds command line arguments
  void _addArgs() {
    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Do a force push.',
      defaultsTo: false,
      negatable: true,
    );
  }
}

/// Mock for [DoPushCommand]
class MockDoPushCommand extends MockDirCommand<void> implements DoPushCommand {}
