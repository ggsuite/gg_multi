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

/// Command to add a repository or all repositories from an organization.
///
/// This command adds the specified git repo (also Gitlab and other servers
/// compatible) or all git repos of the specified organization.
/// It clones the project into the master workspace
/// of the current Directory (kidney_ws_master)
/// and logs every repository that was added:
/// "added repository repo_name from repo_url".
class AddCommand extends Command<dynamic> {
  /// Constructor for AddCommand.
  AddCommand({
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

  /// The log function.
  final GgLog ggLog;

  /// Instance to handle cloning.
  final GitCloner gitCloner;

  /// Function to fetch repositories from the organization API.
  final Future<http.Response> Function(Uri) repoFetcher;

  /// Optional workspace path override.
  final String workspacePath;

  @override
  String get name => 'add';

  @override
  String get description => 'Adds the specified git repo or all git repos '
      'from the specified organization into the master workspace.';

  @override
  Future<void> run() async {
    // Ensure a target parameter is provided.
    if (argResults!.rest.isEmpty) {
      throw UsageException('Missing target parameter.', usage);
    }
    final String targetArg = argResults!.rest[0];
    await addRepositoryHelper(
      targetArg: targetArg,
      ggLog: ggLog,
      gitCloner: gitCloner,
      repoFetcher: repoFetcher,
      workspacePath: workspacePath,
    );
  }
}
