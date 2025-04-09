// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:http/http.dart' as http;

import '../backend/git_cloner.dart';

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
    // coverage:ignore-start
  })  : gitCloner = gitCloner ?? GitCloner(),
        repoFetcher = repoFetcher ?? http.get;
  // coverage:ignore-end

  /// The log function.
  final GgLog ggLog;

  /// Instance to handle cloning.
  final GitCloner gitCloner;

  /// Function to fetch repositories from the organization API.
  final Future<http.Response> Function(Uri) repoFetcher;

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

    // Define the master workspace directory path.
    final String masterWorkspacePath =
        '${Directory.current.path}${Platform.pathSeparator}kidney_ws_master';

    // Check if the target is an organization URL.
    if (targetArg.startsWith('http') && !targetArg.endsWith('.git')) {
      final Uri orgUri = Uri.parse(targetArg);
      final List<String> segments =
          orgUri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) {
        throw Exception('Invalid organization URL: $targetArg');
      }
      final String orgName = segments.last;
      // Construct GitHub API URL for organization repositories
      final String apiUrl = 'https://api.github.com/orgs/$orgName/repos';
      final response = await repoFetcher(Uri.parse(apiUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch repositories '
            'for organization $orgName: ${response.body}');
      }
      final List<dynamic> reposJson =
          jsonDecode(response.body) as List<dynamic>;
      if (reposJson.isEmpty) {
        ggLog('No repositories found for organization $orgName');
        return;
      }
      // Clone each repository from the fetched list.
      for (final repoJson in reposJson) {
        final repoName = repoJson['name'] as String?;
        final cloneUrl = repoJson['clone_url'] as String?;
        if (repoName == null || cloneUrl == null) continue;
        final String destination =
            '$masterWorkspacePath${Platform.pathSeparator}$repoName';
        await gitCloner.cloneRepo(cloneUrl, destination);
        ggLog('added repository $repoName from $cloneUrl');
      }
    } else {
      // Single repository cloning.
      String repoUrl;
      if (targetArg.startsWith('git@')) {
        repoUrl = targetArg;
      } else if (targetArg.startsWith('http')) {
        repoUrl = targetArg;
      } else if (targetArg.contains('/')) {
        // Assume format "username/repo".
        repoUrl = 'https://github.com/$targetArg.git';
      } else {
        // Assume repo name, default organization same as repo name.
        repoUrl = 'https://github.com/$targetArg/$targetArg.git';
      }
      final String repoName = _extractRepoName(repoUrl);
      final String destination =
          '$masterWorkspacePath${Platform.pathSeparator}$repoName';
      await gitCloner.cloneRepo(repoUrl, destination);
      ggLog('added repository $repoName from $repoUrl');
    }
  }

  /// Extracts repository name from a git URL supporting SSH and HTTPS.
  String _extractRepoName(String repoUrl) {
    // Check if the URL is an SSH URL
    if (repoUrl.startsWith('git@')) {
      // Expected SSH format: git@github.com:username/repo.git
      final sshRegex = RegExp(r'^(?:git@[^:]+:)([^/]+)/(.+?)(?:\.git)?$');
      final match = sshRegex.firstMatch(repoUrl);
      if (match != null) {
        return match.group(2)!;
      }
    }
    // Fallback to URI parsing for other formats.
    try {
      final uri = Uri.parse(repoUrl);
      var repoName = uri.pathSegments.last;
      if (repoName.endsWith('.git')) {
        repoName = repoName.substring(0, repoName.length - 4);
      }
      return repoName;
    } catch (e) {
      return repoUrl;
    }
  }
}
