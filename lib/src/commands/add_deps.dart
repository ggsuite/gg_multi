// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../backend/git_cloner.dart';
import '../backend/add_repository_helper.dart';

/// Command to add dependencies of a project from the master workspace.
/// It iterates over dependencies in pubspec.yaml and adds each one using
/// the add command logic.
class AddDepsCommand extends Command<void> {
  /// Constructor
  AddDepsCommand({
    required this.ggLog,
    GitCloner? gitCloner,
    Future<http.Response> Function(Uri)? repoFetcher,
    String? workspacePath,
    // coverage:ignore-start
  })  : gitCloner = gitCloner ?? GitCloner(),
        repoFetcher = repoFetcher ?? http.get,
        workspacePath = workspacePath ??
            path.join(Directory.current.path, 'kidney_ws_master');
  // coverage:ignore-end

  /// Log function.
  final GgLog ggLog;

  /// Instance to handle cloning.
  final GitCloner gitCloner;

  /// Function to fetch repositories.
  final Future<http.Response> Function(Uri) repoFetcher;

  /// Workspace path for cloned repositories.
  final String workspacePath;

  @override
  String get name => 'add-deps';

  @override
  String get description =>
      'Iterates over all dependencies specified in pubspec.yaml '
      'in dependencies and dev_dependencies of a project '
      'from the master workspace and adds them.';

  @override
  Future<void> run() async {
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
    final deps = <String>{}
      ..addAll(pubspec.dependencies.keys)
      ..addAll(pubspec.devDependencies.keys);
    if (deps.isEmpty) {
      ggLog('No dependencies found in pubspec.yaml '
          'for project ${pubspec.name}.');
      return;
    }
    for (final dep in deps) {
      await addRepositoryHelper(
        targetArg: dep,
        ggLog: ggLog,
        gitCloner: gitCloner,
        repoFetcher: repoFetcher,
        workspacePath: workspacePath,
      );
    }
  }
}
