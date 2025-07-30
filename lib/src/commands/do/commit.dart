// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg/gg.dart' as gg;
import 'package:gg_changelog/gg_changelog.dart' as cl;
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;

import '../../backend/workspace_utils.dart';

/// Command to commit changes across all repositories in the current ticket.
class DoCommitCommand extends DirCommand<void> {
  /// Constructor
  DoCommitCommand({
    required super.ggLog,
    super.name = 'commit',
    super.description =
        'Commits changes across all repositories in the current ticket.',
    gg.CanCommit? ggCanCommit,
    gg.DoCommit? ggDoCommit,
  }) : _ggDoCommit = ggDoCommit ?? gg.DoCommit(ggLog: ggLog) {
    _addArgs();
  }

  /// Instance of gg DoCommit to perform the commit action
  final gg.DoCommit _ggDoCommit;

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    String? message,
    cl.LogType? logType,
    bool? updateChangeLog,
  }) =>
      get(
        directory: directory,
        ggLog: ggLog,
        message: message,
        logType: logType,
        updateChangeLog: updateChangeLog,
      );

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    String? message,
    cl.LogType? logType,
    bool? updateChangeLog,
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

    // Iterate over each repository and perform the commit
    final failedRepos = <String>[];
    for (final repoDir in subs) {
      final repoName = path.basename(repoDir.path);
      ggLog(yellow('Committing $repoName in ticket $ticketName...'));
      try {
        await _ggDoCommit.exec(
          directory: repoDir,
          ggLog: ggLog,
          message: message,
          logType: logType,
          updateChangeLog: updateChangeLog,
        );
      } catch (e) {
        ggLog(red('❌ Failed to commit $repoName: $e'));
        failedRepos.add(repoName);
      }
    }

    // Summarize the results
    if (failedRepos.isEmpty) {
      ggLog(
        green(
          '✅ All repositories in ticket $ticketName committed successfully.',
        ),
      );
    } else {
      ggLog(
        red(
          '❌ Failed to commit the following '
          'repositories in ticket $ticketName:',
        ),
      );
      for (final repoName in failedRepos) {
        ggLog(red(' - $repoName'));
      }
      throw Exception(
        'Failed to commit some repositories in ticket $ticketName',
      );
    }
  }

  // Adds command line arguments
  void _addArgs() {
    argParser.addFlag(
      'log',
      abbr: 'l',
      help: 'Do not add message to CHANGELOG.md.',
      negatable: true,
      defaultsTo: true,
    );

    argParser.addOption(
      'message',
      abbr: 'm',
      help: 'The commit message and log entry.',
    );
  }
}

/// Mock for [DoCommitCommand]
class MockDoCommitCommand extends MockDirCommand<void>
    implements DoCommitCommand {}
