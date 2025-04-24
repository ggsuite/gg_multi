// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;
import '../backend/add_repository_helper.dart';

/// Deletes the project folder if the repository is only contained
/// in the master workspace of the current Directory
/// (kidney_ws_master) and no other workspaces (kidney_ws_*).
/// If not, it prints:
/// ```
/// This repo is used by the following feature branches:
/// - ...
/// Please remove these branches first.
/// ```
class RemoveCommand extends Command<void> {
  /// Constructor with optional root path override.
  RemoveCommand({
    required this.ggLog,
    String? rootPath,
    // coverage:ignore-start
  }) : rootPath = rootPath ?? Directory.current.path;
  // coverage:ignore-end

  /// Log function
  final GgLog ggLog;

  /// Root directory to search for workspaces
  final String rootPath;

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
    // Determine repo name
    final targetArg = argResults!.rest.first;
    final repoName = extractRepoName(targetArg);

    // Find all workspaces under rootPath starting with "kidney_ws_"
    final rootDir = Directory(rootPath);
    if (!rootDir.existsSync()) {
      ggLog('Root path not found: $rootPath');
      return;
    }
    final workspaces = rootDir
        .listSync()
        .whereType<Directory>()
        .where((d) => path.basename(d.path).startsWith('kidney_ws_'))
        .toList();

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
      ggLog('Repository $repoName not found in any workspace.');
      return;
    }
    if (found.length == 1 && found.first == 'kidney_ws_master') {
      // Only in master: delete
      final toDelete = Directory(
        path.join(rootPath, 'kidney_ws_master', repoName),
      );
      if (toDelete.existsSync()) {
        toDelete.deleteSync(recursive: true);
        ggLog('Deleted repository $repoName '
            'from master workspace.');
      } else {
        ggLog('Repository folder not found: ${toDelete.path}');
      }
      return;
    }

    // In master and other feature branches
    // or only feature branches
    ggLog('This repo is used by the following feature branches:');
    for (final ws in found.where(
      (n) => n != 'kidney_ws_master',
    )) {
      ggLog(' - $ws');
    }
    ggLog('Please remove these branches first.');
  }
}
