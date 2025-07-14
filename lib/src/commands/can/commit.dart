// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:gg/gg.dart' as gg;
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;
import '../../backend/workspace_utils.dart';

/// Checks if the current ticket's repositories can be committed
class CanCommitCommand extends Command<void> {
  /// Constructor
  CanCommitCommand({
    required this.ggLog,
    String? executionPath,
  }) : executionPath = executionPath ?? Directory.current.path;

  /// Logger function
  final GgLog ggLog;

  /// The path from which the command was executed.
  final String executionPath;

  @override
  String get name => 'commit';

  @override
  String get description => 'Checks if the current tickets '
      'repositories can be committed.';

  @override
  Future<void> run() async {
    // Detect the ticket directory
    final String? ticketPath = WorkspaceUtils.detectTicketPath(
      executionPath,
    );
    if (ticketPath == null) {
      ggLog(red('This command must be run inside a ticket folder.'));
      throw Exception('Not inside a ticket folder.');
    }

    final ticketDir = Directory(ticketPath);
    final ticketName = path.basename(ticketDir.path);
    final repos = (await ticketDir.list().toList())
        .whereType<Directory>().toList()
      ..sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

    if (repos.isEmpty) {
      ggLog(yellow('No repositories found in ticket $ticketName.'));
      return;
    }

    bool hasFailures = false;
    final canCommit = gg.CanCommit(ggLog: ggLog);

    for (final repoDir in repos) {
      final repoName = path.basename(repoDir.path);
      ggLog('Checking if $repoName in ticket $ticketName can be committed...');
      try {
        await canCommit.exec(directory: repoDir, ggLog: ggLog);
        ggLog(green('✅ $repoName in ticket $ticketName can be committed.'));
      } catch (e) {
        ggLog(
          red(
            '❌ $repoName in ticket $ticketName cannot be committed: $e',
          ),
        );
        hasFailures = true;
      }
    }

    if (hasFailures) {
      throw Exception(
        'Some repositories in ticket $ticketName cannot be committed.',
      );
    }

    ggLog(green('All repositories in ticket $ticketName can be committed.'));
  }
}
