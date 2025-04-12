// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:http/http.dart' as http;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:path/path.dart' as path;

import '../backend/git_cloner.dart';
import '../backend/add_repository_helper.dart';

/// Iterates over all dependencies specified in pubspec.yaml in both
/// dependencies and dev_dependencies.
/// Executes for every dependency: kidney_core add repo_name/repo_url
class AddDepsCommand extends Command<void> {
  /// Constructor for AddDepsCommand.
  AddDepsCommand({
    required this.ggLog,
    GitCloner? gitCloner,
    Future<http.Response> Function(Uri)? repoFetcher,
    String? workspacePath,
  })  : gitCloner = gitCloner ?? GitCloner(),
        repoFetcher = repoFetcher ?? http.get,
        workspacePath = workspacePath ??
            path.join(Directory.current.path, 'kidney_ws_master');

  /// The log function.
  final GgLog ggLog;

  /// Instance to handle cloning.
  final GitCloner gitCloner;

  /// Function to fetch repositories from the organization API.
  final Future<http.Response> Function(Uri) repoFetcher;

  /// Workspace path for cloned repositories.
  final String workspacePath;

  @override
  String get name => 'add-deps';

  @override
  String get description => 'Iterates over all dependencies specified '
      'in pubspec.yaml in dependencies and dev_dependencies. '
      'Executes for every dependency kidney_core add <repo_name/repo_url>';

  @override
  Future<void> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw UsageException('No additional arguments expected', usage);
    }
    final pubspecFile = File('pubspec.yaml');
    if (!pubspecFile.existsSync()) {
      ggLog('pubspec.yaml not found in current directory.');
      return;
    }
    final content = pubspecFile.readAsStringSync();
    final pubspec = Pubspec.parse(content);
    final deps = <String>{};
    deps.addAll(pubspec.dependencies.keys);
    deps.addAll(pubspec.devDependencies.keys);
    if (deps.isEmpty) {
      ggLog('No dependencies found in pubspec.yaml.');
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
