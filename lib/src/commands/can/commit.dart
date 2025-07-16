// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:gg/gg.dart' show CanCommit;
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import '../../backend/workspace_utils.dart';
import 'package:path/path.dart' as path;

/// Typedef for creating Directory instances (for testing).
typedef DirectoryFactory = Directory Function(String path);

/// Command to check if all repos in the ticket can be committed.
class CanCommitCommand extends Command<void> {
  /// Constructor for CanCommitCommand
  CanCommitCommand({
    required this.ggLog,
    String? executionPath,
    CanCommit? ggCanCommit,
    // coverage:ignore-start
  })  : _executionPath = executionPath ?? Directory.current.path,
        _ggCanCommit = ggCanCommit ?? CanCommit(ggLog: ggLog);
  // coverage:ignore-end

  /// Logging function
  final GgLog ggLog;

  /// Execution path
  final String _executionPath;

  /// Instance of gg CanCommit
  final CanCommit _ggCanCommit;

  @override
  String get name => 'commit';

  @override
  String get description =>
      'Checks if all repositories in the current ticket can be committed.';

  @override
  Future<void> run() async {
    final ticketPath = WorkspaceUtils.detectTicketPath(_executionPath);
    if (ticketPath == null) {
      ggLog(red('This command must be executed inside a ticket folder.'));
      return;
    }
    final ticketDir = Directory(ticketPath);
    final ticketName = path.basename(ticketDir.path);
    final subs = ticketDir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));
    if (subs.isEmpty) {
      ggLog(yellow('⚠️ No repositories found in ticket $ticketName.'));
      return;
    }
    for (final repoDir in subs) {
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
    ggLog(green('✅ All repositories in ticket $ticketName can be committed.'));
  }
}
