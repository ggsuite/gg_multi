// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:path/path.dart' as path;
import 'package:gg_log/gg_log.dart';

/// Command to initialize the master workspace (kidney_ws_master)
class InitCommand extends Command<void> {
  /// Constructor
  InitCommand({
    required this.ggLog,
    String? rootPath,
    // coverage:ignore-start
  }) : rootPath = rootPath ?? Directory.current.path;
  // coverage:ignore-end

  /// The log function
  final GgLog ggLog;

  /// Optional root path for where to create the master workspace
  final String rootPath;

  @override
  String get name => 'init';

  @override
  String get description => 'Initializes the master workspace.';

  @override
  Future<void> run() async {
    final wsPath = path.join(rootPath, 'kidney_ws_master');
    final wsDir = Directory(wsPath);
    if (wsDir.existsSync()) {
      ggLog(
        yellow(
          'Master workspace already exists at: $wsPath',
        ),
      );
      return;
    }
    wsDir.createSync(recursive: true);
    ggLog(green('Master workspace initialized at: $wsPath'));
  }
}
