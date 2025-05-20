// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;
import '../backend/constants.dart';
import '../backend/workspace_utils.dart';
import '../backend/vscode_launcher.dart';

/// Typedef for creating Directory instances (for testing).
typedef DirectoryFactory = Directory Function(String path);

/// Command to open all repos (or a single repo) under a ticket in VS Code.
class CodeCommand extends Command<void> {
  /// Constructor.
  CodeCommand({
    required this.ggLog,
    String? rootPath,
    DirectoryFactory? directoryFactory,
    VSCodeLauncher? launcher,
    // coverage:ignore-start
  })  : workspacePath = rootPath ?? WorkspaceUtils.defaultKidneyWorkspacePath(),
        _dirFactory = directoryFactory ?? Directory.new,
        _launcher = launcher ?? VSCodeLauncher();
  // coverage:ignore-end

  /// The log function.
  final GgLog ggLog;

  /// Kidney workspace path.
  final String workspacePath;

  /// Used for test injection.
  final DirectoryFactory _dirFactory;

  /// Responsible for launching VS Code.
  final VSCodeLauncher _launcher;

  @override
  String get name => 'code';

  @override
  String get description =>
      'Open all repos under a ticket, or a single repo, in VS Code.';

  @override
  Future<void> run() async {
    final args = argResults!.rest;
    if (args.isEmpty) {
      throw UsageException('Missing ticket parameter.', usage);
    }
    final target = args.first;
    final parts = target.split(RegExp(r'[\\/]'));
    if (parts.isEmpty || parts.length > 2) {
      throw UsageException(
        'Invalid target format. Use <ticket> or <ticket>/<repo>.',
        usage,
      );
    }
    final ticketName = parts[0];
    final repoName = parts.length == 2 ? parts[1] : null;
    final ticketsDir = _dirFactory(
      path.join(workspacePath, kidneyTicketFolder),
    );
    final ticketDir = Directory(path.join(ticketsDir.path, ticketName));
    if (!ticketDir.existsSync()) {
      ggLog(red('Ticket $ticketName not found at ${ticketDir.path}'));
      return;
    }
    if (repoName != null) {
      final repoDir = Directory(path.join(ticketDir.path, repoName));
      if (!repoDir.existsSync()) {
        ggLog(
          red(
            'Repository $repoName not found '
            'in ticket $ticketName at ${repoDir.path}',
          ),
        );
        return;
      }
      await _openInVSCode(repoDir);
    } else {
      final subs = ticketDir.listSync().whereType<Directory>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      if (subs.isEmpty) {
        ggLog(red('No repositories found under ticket $ticketName.'));
        return;
      }
      for (final d in subs) {
        await _openInVSCode(d);
      }
    }
  }

  Future<void> _openInVSCode(Directory dir) async {
    await _launcher.open(dir);
    ggLog(green('Opened ${path.basename(dir.path)} at ${dir.path}'));
  }
}
