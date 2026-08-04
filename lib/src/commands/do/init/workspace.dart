// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as p;
import 'package:path/path.dart' as path;

import '../../../backend/constants.dart';
import '../../../backend/workspace_utils.dart';

/// Command to initialize the ocean workspace
class InitWorkspaceCommand extends Command<void> {
  /// Constructor
  InitWorkspaceCommand({
    required this.ggLog,
    String? rootPath,
    // coverage:ignore-start
  }) : rootPath = rootPath ?? Directory.current.path;
  // coverage:ignore-end

  /// The log function
  final GgLog ggLog;

  /// Optional root path for where to create the ocean workspace
  final String rootPath;

  String _rel(String absPath) => p.relative(absPath, from: rootPath);

  @override
  String get name => 'workspace';

  @override
  String get description => 'Initialize the ocean workspace';

  @override
  Future<void> run() async {
    final rootDir = Directory(rootPath);

    final wsPath = path.join(rootDir.path, ggMultiOceanFolder);
    final wsDir = Directory(wsPath);

    if (wsDir.existsSync()) {
      ggLog(cWarn('Ocean workspace already exists at: ${_rel(wsPath)}'));
      return;
    }

    if (rootDir.listSync().isNotEmpty) {
      ggLog(cError('The directory must be empty to initialize a workspace.'));
      return;
    }

    if (WorkspaceUtils.isInsideExistingWorkspace(rootDir.path)) {
      ggLog(
        cError('Cannot initialize a new workspace inside an existing Gg Multi '
            'workspace.'),
      );
      return;
    }

    // -----------------------------------------------------------------------
    // Create the workspace ---------------------------------------------------
    wsDir.createSync(recursive: true);
    ggLog(cDetail('✓ Ocean workspace initialized at: ${_rel(wsPath)}'));
  }
}
