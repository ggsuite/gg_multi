// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;
import '../backend/constants.dart';
import '../backend/workspace_utils.dart';
import '../backend/vscode_launcher.dart';
import 'package:path/path.dart' as p;

/// Command to open all repos (or a single repo) under a ticket in VS Code.
class CodeCommand extends Command<void> {
  /// Constructor.
  CodeCommand({
    required this.ggLog,
    String? rootPath,
    String? executionPath,
    DirectoryFactory? directoryFactory,
    VSCodeLauncher? launcher,
    SortedProcessingList? sortedProcessingList,
    // coverage:ignore-start
  })  : workspacePath = rootPath ?? WorkspaceUtils.defaultKidneyWorkspacePath(),
        _executionPath = executionPath ?? Directory.current.path,
        _dirFactory = directoryFactory ?? Directory.new,
        _launcher = launcher ?? VSCodeLauncher();
  // coverage:ignore-end

  /// The log function.
  final GgLog ggLog;

  /// Kidney workspace path.
  final String workspacePath;

  /// The path from which the command is executed.
  final String _executionPath;

  /// Used for test injection.
  final DirectoryFactory _dirFactory;

  /// Responsible for launching VS Code.
  final VSCodeLauncher _launcher;

  String _rel(String absPath) => p.relative(absPath, from: _executionPath);

  @override
  String get name => 'code';

  @override
  String get description =>
      'Open all repos under a ticket, or a single repo, in VS Code.';

  @override
  Future<void> run() async {
    final args = argResults!.rest;

    // No explicit target, try to detect ticket from execution path.
    if (args.isEmpty) {
      final ticketPath = WorkspaceUtils.detectTicketPath(_executionPath);
      if (ticketPath == null) {
        throw UsageException(
          'Missing ticket parameter.',
          usage,
        );
      }

      final ticketDir = Directory(ticketPath);
      await _openTicketWorkspace(ticketDir);
      return;
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
      ggLog(red('Ticket $ticketName not found at ${_rel(ticketDir.path)}'));
      return;
    }

    if (repoName != null) {
      final repoDir = Directory(path.join(ticketDir.path, repoName));
      if (!repoDir.existsSync()) {
        ggLog(
          red(
            'Repository $repoName not found '
            'in ticket $ticketName at ${_rel(repoDir.path)}',
          ),
        );
        return;
      }
      await _openInVSCode(repoDir);
    } else {
      await _openTicketWorkspace(ticketDir);
    }
  }

  /// Opens the VS Code workspace file `<ticket_name>.code-workspace` that
  /// belongs to [ticketDir]. The file does not need to exist yet; VS Code
  /// can create it on demand.
  Future<void> _openTicketWorkspace(Directory ticketDir) async {
    final ticketName = path.basename(ticketDir.path);
    final workspacePath =
        path.join(ticketDir.path, '$ticketName.code-workspace');

    await _launcher.openPath(workspacePath);
    ggLog(
      green(
        'Opened workspace $ticketName.code-workspace '
        'at ${_rel(workspacePath)}',
      ),
    );
  }

  Future<void> _openInVSCode(Directory dir) async {
    await _launcher.openDirectory(dir);
    ggLog(green('Opened ${path.basename(dir.path)} at ${_rel(dir.path)}'));
  }
}

/// Typedef for creating Directory instances (for testing).
typedef DirectoryFactory = Directory Function(String path);
