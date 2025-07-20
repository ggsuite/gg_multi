// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../backend/constants.dart';
import '../backend/git_handler.dart';
import '../backend/add_repository_helper.dart';
import '../backend/git_platform.dart';

/// Command to add dependencies of a project from the master workspace.
/// It iterates over dependencies in pubspec.yaml and adds each one using
/// the add command logic.
class AddDepsCommand extends Command<void> {
  /// Constructor
  AddDepsCommand({
    required this.ggLog,
    GitHandler? gitCloner,
    GitHubPlatform? gitHubPlatform,
    Future<http.Response> Function(Uri)? repoFetcher,
    Future<http.Response> Function(Uri)? packageFetcher,
    String? workspacePath,
    // coverage:ignore-start
  })  : gitCloner = gitCloner ?? GitHandler(),
        gitHubPlatform = gitHubPlatform ?? GitHubPlatform(),
        packageFetcher = packageFetcher ?? http.get,
        workspacePath = workspacePath ??
            path.join(Directory.current.path, kidneyMasterFolder);
  // coverage:ignore-end

  /// The log function.
  final GgLog ggLog;

  /// Instance to handle cloning.
  final GitHandler gitCloner;

  /// Instance to handle GitHub specific operations.
  final GitHubPlatform gitHubPlatform;

  /// Function to fetch package info from pub.dev.
  final Future<http.Response> Function(Uri) packageFetcher;

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
      ggLog(
        darkGray('No dependencies found in pubspec.yaml '
            'for project ${pubspec.name}.'),
      );
      return;
    }
    for (final dep in deps) {
      try {
        final repoUrl = await fetchDependencyRepoUrl(
          dep,
          packageFetcher: packageFetcher,
        );
        if (repoUrl == null || repoUrl.isEmpty) {
          ggLog(
            red('No repository URL found for '
                'dependency $dep on pub.dev, skipping.'),
          );
          continue;
        }
        // New check: ignore dependencies whose repo URL starts with dart-lang
        if (repoUrl.startsWith('https://github.com/dart-lang/')) {
          ggLog(
            yellow(
              'Ignoring dependency $dep from dart-lang repository: $repoUrl',
            ),
          );
          continue;
        }
        try {
          await addRepositoryHelper(
            targetArg: repoUrl,
            ggLog: ggLog,
            gitCloner: gitCloner,
            gitHubPlatform: gitHubPlatform,
            workspacePath: workspacePath,
          );
        } catch (e) {
          ggLog(red('Failed to clone dependency $dep from $repoUrl: $e'));
        }
      } catch (e) {
        ggLog(red('Failed to fetch repository info for dependency $dep: $e'));
      }
    }
  }
}

/// Fetches the repository URL for a package from pub.dev.
/// Returns the repository URL as a string if found, otherwise null.
Future<String?> fetchDependencyRepoUrl(
  String packageName, {
  Future<http.Response> Function(Uri)? packageFetcher,
}) async {
  final fetcher = packageFetcher ?? http.get;
  final url = Uri.parse('https://pub.dev/api/packages/$packageName');
  final response = await fetcher(url);
  if (response.statusCode != 200) {
    throw Exception(
      'Failed to fetch package info from pub.dev for $packageName',
    );
  }
  final data = jsonDecode(response.body) as Map<String, dynamic>;
  if (data.containsKey('latest')) {
    final latest = data['latest'] as Map<String, dynamic>;
    if (latest.containsKey('pubspec')) {
      final pubspec = latest['pubspec'] as Map<String, dynamic>;
      if (pubspec.containsKey('repository')) {
        final repoUrl = pubspec['repository'] as String;
        return repoUrl;
      }
    }
  }
  return null;
}
