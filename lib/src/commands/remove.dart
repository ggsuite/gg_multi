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
import '../backend/add_repository_helper.dart';
import '../backend/constants.dart';

/// Typedef for creating Directory instances,
/// used for dependency injection in tests.
typedef DirectoryFactory = Directory Function(String path);

/// Deletes the project folder if the repository is only contained
/// in the master workspace of the current Directory
/// and no other workspaces.
/// If not, it prints:
/// ```
/// This repo is used by the following feature branches:
/// - ...
/// Please remove these branches first.
/// ```
class RemoveCommand extends Command<void> {
  /// Constructor with optional root path
  /// override and directory factory for testing.
  RemoveCommand({
    required this.ggLog,
    String? rootPath,
    DirectoryFactory? directoryFactory,
    // coverage:ignore-start
  })  : rootPath = rootPath ?? Directory.current.path,
        directoryFactory = directoryFactory ?? Directory.new;
  // coverage:ignore-end

  /// The log function
  final GgLog ggLog;

  /// Root directory to search for workspaces
  final String rootPath;

  /// Factory function to create Directory instances (useful for testing)
  final DirectoryFactory directoryFactory;

  @override
  String get name => 'remove';

  @override
  String get description =>
      'Delete a repo folder if only in master; otherwise list usage.';

  @override
  Future<void> run() async {
    if (argResults!.rest.isEmpty) {
      throw UsageException(
        'Missing target parameter.',
        usage,
      );
    }
    // Determine target name
    final targetArg = argResults!.rest.first;
    final repoName = extractRepoName(targetArg);

    // If a ticket exists, delete ticket folder
    final ticketPath = path.join(rootPath, kidneyTicketFolder, repoName);
    final ticketDir = Directory(ticketPath);
    if (ticketDir.existsSync()) {
      ticketDir.deleteSync(recursive: true);
      ggLog(green('Deleted ticket $repoName at $ticketPath'));
      return;
    }

    // Find all workspaces under rootPath starting with "kidney_ws_"
    final rootDir = Directory(rootPath);
    if (!rootDir.existsSync()) {
      ggLog(red('Root path not found: $rootPath'));
      return;
    }
    final workspaces = rootDir.listSync().whereType<Directory>().toList();

    // Find in which workspaces the repo exists
    final found = <String>[];
    for (final ws in workspaces) {
      final subDir = Directory(path.join(ws.path, repoName));
      if (subDir.existsSync()) {
        found.add(path.basename(ws.path));
      }
    }

    // Handle cases
    if (found.isEmpty) {
      ggLog(red('Repository $repoName not found in any workspace.'));
      return;
    }
    if (found.length == 1 && found.first == kidneyMasterFolder) {
      // Only in master: delete
      final toDelete =
          directoryFactory(path.join(rootPath, kidneyMasterFolder, repoName));
      if (toDelete.existsSync()) {
        toDelete.deleteSync(recursive: true);
        ggLog(
          green('Deleted repository $repoName from master workspace.'),
        );
      } else {
        ggLog(red('Repository folder not found: ${toDelete.path}'));
      }
      return;
    }

    // In master and other feature branches
    // or only feature branches
    ggLog('This repo is used by the following feature branches:');
    for (final ws in found.where(
      (n) => n != kidneyMasterFolder,
    )) {
      ggLog(' - $ws');
    }
    ggLog(red('Please remove these branches first.'));
  }
}
