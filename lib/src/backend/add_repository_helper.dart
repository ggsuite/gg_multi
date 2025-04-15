// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_log/gg_log.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'git_cloner.dart';
import 'package:pubspec_parse/pubspec_parse.dart';

/// Helper function to add a repository given a target argument.
/// It supports various formats like URLs, SSH links, and plain names.
/// For organization URLs, it fetches all repositories and clones them.
///
/// The [force] parameter determines whether an existing cloned
/// repository should be overwritten. If false and the destination
/// already exists and is not empty, the function logs "repo already added."
/// If true, the existing directory is deleted before cloning.
Future<void> addRepositoryHelper({
  required String targetArg,
  required GgLog ggLog,
  required GitCloner gitCloner,
  required Future<http.Response> Function(Uri) repoFetcher,
  required String workspacePath,
  bool force = false,
}) async {
  // Local helper function to attempt cloning or skip if already exists.
  Future<void> attemptClone(String repoUrl, String repoName) async {
    final destination = path.join(workspacePath, repoName);
    final destDir = Directory(destination);
    if (destDir.existsSync() && destDir.listSync().isNotEmpty) {
      if (!force) {
        ggLog('$repoName already added.');
        return;
      } else {
        await destDir.delete(recursive: true);
      }
    }
    await gitCloner.cloneRepo(repoUrl, destination);
    ggLog('added repository $repoName from $repoUrl');
  }

  final parsedUri = Uri.tryParse(targetArg);
  if (parsedUri != null &&
      (parsedUri.scheme == 'http' || parsedUri.scheme == 'https') &&
      parsedUri.host.isNotEmpty) {
    String cleanedUrl = targetArg;
    if (cleanedUrl.endsWith('#')) {
      cleanedUrl = cleanedUrl.substring(0, cleanedUrl.length - 1);
    }
    final uri = Uri.parse(cleanedUrl);
    if (uri.pathSegments.isEmpty ||
        uri.pathSegments.every((segment) => segment.trim().isEmpty)) {
      throw Exception('Invalid organization URL provided: $cleanedUrl');
    }
    if (uri.pathSegments.length < 2) {
      // Treat as organization URL
      final String orgName = uri.pathSegments.last.trim();
      final String apiUrl = 'https://api.github.com/orgs/$orgName/repos';
      final response = await repoFetcher(Uri.parse(apiUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch repositories for '
            'organization $orgName: ${response.body}');
      }
      final List<dynamic> reposJson =
          jsonDecode(response.body) as List<dynamic>;
      if (reposJson.isEmpty) {
        ggLog('No repositories found for organization $orgName');
        return;
      }
      for (final repoJson in reposJson) {
        final repoName = repoJson['name'] as String?;
        final cloneUrl = repoJson['clone_url'] as String?;
        if (repoName == null || cloneUrl == null) continue;
        await attemptClone(cloneUrl, repoName);
      }
    } else {
      // Treat as a repository URL
      String repoUrl = cleanedUrl;
      if (!repoUrl.endsWith('.git')) {
        repoUrl = '$repoUrl.git';
      }
      final String repoName = extractRepoName(repoUrl);
      await attemptClone(repoUrl, repoName);
    }
  } else if (targetArg.startsWith('git@')) {
    final String repoUrl = targetArg;
    final String repoName = extractRepoName(repoUrl);
    await attemptClone(repoUrl, repoName);
  } else if (targetArg.contains('/')) {
    final String repoUrl = 'https://github.com/$targetArg.git';
    final String repoName = extractRepoName(repoUrl);
    await attemptClone(repoUrl, repoName);
  } else {
    final String repoUrl = 'https://github.com/$targetArg/$targetArg.git';
    final String repoName = extractRepoName(repoUrl);
    await attemptClone(repoUrl, repoName);
  }
}

/// Extracts the repository name from a git URL supporting SSH and HTTPS.
String extractRepoName(String repoUrl) {
  if (repoUrl.startsWith('git@')) {
    final sshRegex = RegExp(r'^(?:git@[^:]+:)([^/]+)/(.+?)(?:\.git)?$');
    final match = sshRegex.firstMatch(repoUrl);
    if (match != null) {
      return match.group(2)!;
    }
  }
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

/// Retrieves the Pubspec for a repository in the master workspace.
/// Returns null if pubspec.yaml is not found or parsing fails.
Pubspec? getPubspecFromWorkspace({
  required String targetArg,
  required String workspacePath,
  required GgLog ggLog,
}) {
  final repoName = extractRepoName(targetArg);
  final pubspecPath = path.join(workspacePath, repoName, 'pubspec.yaml');
  final pubspecFile = File(pubspecPath);
  if (!pubspecFile.existsSync()) {
    ggLog('pubspec.yaml not found in '
        'project $repoName in workspace $workspacePath.');
    return null;
  }
  try {
    final content = pubspecFile.readAsStringSync();
    return Pubspec.parse(content);
  } catch (e) {
    ggLog('Error parsing pubspec.yaml: $e');
    return null;
  }
}
