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
import 'package:gg_one/gg_one.dart' as gg;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../../backend/constants.dart';
import '../../backend/git_handler.dart';
import '../../backend/add_repository_helper.dart';
import '../../backend/git_platform.dart';

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
            path.join(Directory.current.path, ggMultiMasterFolder);
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
    final info = getManifestDependenciesFromWorkspace(
      targetArg: targetArg,
      workspacePath: workspacePath,
      ggLog: ggLog,
    );
    if (info == null) {
      return;
    }
    final deps = info.deps;
    if (deps.isEmpty) {
      ggLog(
        darkGray('No dependencies found in ${info.manifestFile} '
            'for project ${info.name}.'),
      );
      return;
    }
    for (final dep in deps) {
      try {
        final repoUrl = await fetchDependencyRepoUrl(
          dep,
          type: info.type,
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

/// Fetches the repository URL for a dependency from its registry: pub.dev for
/// Dart/Flutter, the npm registry for TypeScript. Returns the URL if found,
/// otherwise null.
Future<String?> fetchDependencyRepoUrl(
  String packageName, {
  gg.ProjectType type = gg.ProjectType.dart,
  Future<http.Response> Function(Uri)? packageFetcher,
}) async {
  final fetcher = packageFetcher ?? http.get;

  if (type == gg.ProjectType.typescript) {
    return _fetchNpmRepoUrl(packageName, fetcher);
  }

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

/// Fetches a dependency's repository URL from the npm registry.
Future<String?> _fetchNpmRepoUrl(
  String packageName,
  Future<http.Response> Function(Uri) fetcher,
) async {
  final url = Uri.parse('https://registry.npmjs.org/$packageName');
  final response = await fetcher(url);
  if (response.statusCode != 200) {
    throw Exception(
      'Failed to fetch package info from npm for $packageName',
    );
  }
  final data = jsonDecode(response.body) as Map<String, dynamic>;
  final repository = data['repository'];

  String? raw;
  if (repository is String) {
    raw = repository;
  } else if (repository is Map<String, dynamic>) {
    raw = repository['url']?.toString();
  }
  if (raw == null) {
    return null;
  }
  // npm repository URLs are commonly of the form
  // "git+https://github.com/owner/repo.git".
  return raw.replaceFirst(RegExp(r'^git\+'), '');
}

/// Reads the package name, dependency names and project type from a repo's
/// manifest (`pubspec.yaml` or `package.json`) in the master workspace.
/// Returns null (and logs) when no manifest is found or it cannot be parsed.
({String name, Set<String> deps, gg.ProjectType type, String manifestFile})?
    getManifestDependenciesFromWorkspace({
  required String targetArg,
  required String workspacePath,
  required GgLog ggLog,
}) {
  final repoName = extractRepoName(targetArg);
  final repoDir = Directory(path.join(workspacePath, repoName ?? ''));

  final gg.ProjectType type;
  try {
    type = gg.detectProjectType(repoDir);
  } catch (_) {
    // No recognizable manifest — reuse the Dart not-found message.
    getPubspecFromWorkspace(
      targetArg: targetArg,
      workspacePath: workspacePath,
      ggLog: ggLog,
    );
    return null;
  }

  switch (type) {
    case gg.ProjectType.dart:
    case gg.ProjectType.flutter:
      final pubspec = getPubspecFromWorkspace(
        targetArg: targetArg,
        workspacePath: workspacePath,
        ggLog: ggLog,
      );
      if (pubspec == null) {
        return null;
      }
      return (
        name: pubspec.name,
        deps: <String>{
          ...pubspec.dependencies.keys,
          ...pubspec.devDependencies.keys,
        },
        type: type,
        manifestFile: 'pubspec.yaml',
      );
    case gg.ProjectType.typescript:
      final file = File(path.join(repoDir.path, 'package.json'));
      final Map<String, dynamic> json;
      try {
        json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      } catch (e) {
        ggLog(red('Error parsing package.json: $e'));
        return null;
      }
      final deps = <String>{};
      for (final key in const ['dependencies', 'devDependencies']) {
        final section = json[key];
        if (section is Map) {
          deps.addAll(section.keys.map((e) => e.toString()));
        }
      }
      return (
        name: json['name']?.toString() ?? repoName ?? 'unknown',
        deps: deps,
        type: type,
        manifestFile: 'package.json',
      );
  }
}
