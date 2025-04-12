// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;
import '../../backend/add_repository_helper.dart';

/// Command to list dependencies of a project from the master workspace.
class ListDepsCommand extends Command<dynamic> {
  /// Constructor
  ListDepsCommand({
    required this.ggLog,
    String? workspacePath,
    // coverage:ignore-start
  }) : workspacePath = workspacePath ??
            path.join(Directory.current.path, 'kidney_ws_master') {
    _addArgs();
  }
  // coverage:ignore-end

  /// Log function.
  final GgLog ggLog;

  /// Workspace path for projects.
  final String workspacePath;

  @override
  String get name => 'deps';

  @override
  String get description => 'Lists dependencies and dev_dependencies '
      'of a project from the master workspace.';

  void _addArgs() {
    argParser.addOption(
      'depth',
      abbr: 'd',
      help: 'The depth for listing dependencies.',
      defaultsTo: '1',
    );
  }

  @override
  void run() {
    if (argResults!.rest.isEmpty) {
      throw UsageException('Missing target repository parameter.', usage);
    }
    final targetArg = argResults!.rest[0];
    final pubspec = getPubspecFromWorkspace(
      targetArg: targetArg,
      workspacePath: workspacePath,
      ggLog: ggLog,
    );
    if (pubspec == null) {
      return;
    }
    final projectLine =
        '${pubspec.name} v.${pubspec.version?.toString() ?? '1.0.0'} (dart)';
    ggLog(projectLine);
    pubspec.dependencies.forEach((key, value) {
      ggLog(' |-- $key ${value.toString()} (dart)');
    });
    pubspec.devDependencies.forEach((key, value) {
      ggLog(' |-- dev:$key ${value.toString()} (dart)');
    });
  }
}
