// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kidney_core/src/backend/organization.dart';
import 'package:kidney_core/src/backend/url_parser.dart';

import 'dart:io';

/// Typedef for running processes (for injection & tests).
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

/// Default process runner that uses the system's `Process.run`
// coverage:ignore-start
Future<ProcessResult> _defaultProcessRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) =>
    Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: true,
    );
// coverage:ignore-end

/// Interface for Git platforms like GitHub, Azure DevOps, GitLab.
abstract class GitPlatform {
  /// Builds the full clone URL for a repository.
  String buildRepoUrl(String org, String repo, [String? project]);

  /// Fetches the list of repositories for an organization.
  Future<List<Map<String, dynamic>>> fetchOrgRepos(
    String org, {
    String? project,
    http.Client? client,
  });

  /// Extracts organization information from a URL.
  Organization? extractOrgFromUrl(String url);

  /// Builds the base URL for the organization.
  String buildBaseUrl(String org, [String? project]);
}

/// GitHub implementation of GitPlatform.
class GitHubPlatform implements GitPlatform {
  @override
  String buildRepoUrl(String org, String repo, [String? project]) {
    return 'https://github.com/$org/$repo.git';
  }

  @override
  Future<List<Map<String, dynamic>>> fetchOrgRepos(
    String org, {
    String? project,
    http.Client? client,
  }) async {
    client ??= http.Client();
    final uri = Uri.parse('https://api.github.com/orgs/$org/repos');
    final response = await client.get(uri);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch repositories for organization $org: '
        '${response.body}',
      );
    }
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  @override
  Organization? extractOrgFromUrl(String url) {
    final parsed = const UrlParser().parse(url);
    if (parsed.platformType != 'github') return null;
    return Organization(
      name: parsed.org ?? '',
      url: buildBaseUrl(parsed.org ?? ''),
    );
  }

  @override
  String buildBaseUrl(String org, [String? project]) {
    return 'https://github.com/$org/';
  }
}

/// Azure DevOps implementation of GitPlatform.
class AzureDevOpsPlatform implements GitPlatform {
  /// Constructor accepts an optional process runner for testing.
  AzureDevOpsPlatform({
    ProcessRunner? processRunner,
  }) : _processRunner = processRunner ?? _defaultProcessRunner;

  final ProcessRunner _processRunner;

  @override
  String buildRepoUrl(String org, String repo, [String? project]) {
    if (project == null) {
      throw ArgumentError('Project name is required for Azure DevOps.');
    }
    return 'https://ssh.dev.azure.com:v3/$org/$project/$repo.git';
  }

  @override
  Future<List<Map<String, dynamic>>> fetchOrgRepos(
    String org, {
    String? project,
    http.Client? client,
  }) async {
    if (project == null) {
      throw ArgumentError('Project name is required for Azure DevOps.');
    }
    await _checkAzInstalled();
    final result = await _processRunner(
      'az',
      [
        'repos',
        'list',
        '--organization',
        'https://dev.azure.com/$org',
        '--project',
        project,
      ],
    );
    if (result.exitCode != 0) {
      throw Exception(
        'Failed to fetch repositories for organization $org, '
        'project $project: ${result.stderr}',
      );
    }
    final jsonOutput = result.stdout.toString();
    try {
      final repos = jsonDecode(jsonOutput) as List<dynamic>;
      return repos.map((repo) {
        final repoMap = repo as Map<String, dynamic>;
        return <String, dynamic>{
          'name': repoMap['name'] as String?,
          'clone_url': repoMap['sshUrl'] as String?,
        };
      }).toList();
    } catch (e) {
      throw Exception('Failed to parse Azure CLI output: $e');
    }
  }

  /// Checks if az CLI is installed by running 'az --version'.
  /// Throws an exception with installation instructions if not installed.
  Future<void> _checkAzInstalled() async {
    try {
      final result = await _processRunner('az', ['--version']);
      if (result.exitCode != 0) {
        throw Exception(result.stderr);
      }
    } catch (e) {
      throw Exception(
        'Bitte installiere die Azure CLI mit folgenden Befehlen: \n'
        '    winget install --exact --id Microsoft.AzureCLI \n'
        '    az extension add --name azure-devops',
      );
    }
  }

  @override
  Organization? extractOrgFromUrl(String url) {
    final parsed = const UrlParser().parse(url);
    if (parsed.platformType != 'azure') return null;
    return Organization(
      name: parsed.org ?? '',
      url: buildBaseUrl(parsed.org ?? '', parsed.project),
      projectName: parsed.project,
    );
  }

  @override
  String buildBaseUrl(String org, [String? project]) {
    return project != null
        ? 'https://ssh.dev.azure.com:v3/$org/$project/'
        : 'https://ssh.dev.azure.com:v3/$org/';
  }
}
