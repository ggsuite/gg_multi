// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:pubspec_parse/pubspec_parse.dart';

/// Command to list dependencies of the current project.
class ListDepsCommand extends Command<dynamic> {
  /// Constructor.
  ListDepsCommand({required this.ggLog}) {
    _addArgs();
  }

  /// The log function.
  final GgLog ggLog;

  @override
  String get name => 'deps';

  @override
  String get description =>
      'Lists dependencies and dev_dependencies of the project.';

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
    // final depthStr = argResults?['depth'] as String?;
    // final depth = int.tryParse(depthStr ?? '1') ?? 1;
    final pubspecFile = File('pubspec.yaml');
    if (!pubspecFile.existsSync()) {
      ggLog('pubspec.yaml not found in current directory.');
      return;
    }
    try {
      final content = pubspecFile.readAsStringSync();
      final pubspec = Pubspec.parse(content);
      final projectLine =
          '${pubspec.name} v.${pubspec.version?.toString() ?? '1.0.0'} (dart)';
      ggLog(projectLine);
      pubspec.dependencies.forEach((key, value) {
        ggLog(' |-- $key ${value.toString()} (dart)');
      });
      pubspec.devDependencies.forEach((key, value) {
        ggLog(' |-- dev:$key ${value.toString()} (dart)');
      });
    } catch (e) {
      ggLog('Error parsing pubspec.yaml: $e');
    }
  }
}
