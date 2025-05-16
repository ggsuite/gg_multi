// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
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
/// already exists and is not empty, the function logs "repo already added.".
///
/// The [logIfAlreadyAdded] parameter controls whether the "already added"
/// message is logged when a repository is skipped because it's already
/// present. This can be disabled when adding to a ticket workspace to
/// suppress duplicate logs.
///
/// The optional [onRepoAdded] callback is executed for every repository that is
/// ensured to be present (either cloned or detected as already cloned).  This
/// makes it easy to plug-in additional behaviour (e.g. copy the repo to a
/// ticket workspace) without touching the core cloning logic.
Future<void> addRepositoryHelper({
  required String targetArg,
  required GgLog ggLog,
  required GitCloner gitCloner,
  required Future<http.Response> Function(Uri) repoFetcher,
  required String workspacePath,
  bool force = false,
  bool logIfAlreadyAdded = true,
  Future<void> Function(String repoName)? onRepoAdded,
}) async {
  // ---------------------------------------------------------------------------
  // Local helper function to attempt cloning or skip if already exists.
  Future<void> attemptClone(String repoUrl, String repoName) async {
    final destination = path.join(workspacePath, repoName);
    final destDir = Directory(destination);

    // If repository folder already exists and is not empty ....................
    if (destDir.existsSync() && destDir.listSync().isNotEmpty) {
      if (!force) {
        if (logIfAlreadyAdded) {
          ggLog(darkGray('$repoName already added.'));
        }
        if (onRepoAdded != null) {
          await onRepoAdded(repoName);
        }
        return;
      } else {
        await destDir.delete(recursive: true);
      }
    }

    // Clone the repository ....................................................
    await gitCloner.cloneRepo(repoUrl, destination);
    ggLog(green('Added repository $repoName from $repoUrl'));

    if (onRepoAdded != null) {
      await onRepoAdded(repoName);
    }
  }

  // ---------------------------------------------------------------------------
  // Normalize URL: remove trailing "#" and "/" so that
  // "https://github.com/ggsuite/" and "https://github.com/ggsuite" behave the
  // same. This must happen before any URI parsing logic.
  var cleanedUrl = targetArg;
  if (cleanedUrl.endsWith('#')) {
    cleanedUrl = cleanedUrl.substring(0, cleanedUrl.length - 1);
  }
  // Remove trailing slashes ONLY (preserve inner slashes between segments).
  cleanedUrl = cleanedUrl.replaceFirst(RegExp(r'/+$'), '');

  final parsedUri = Uri.tryParse(cleanedUrl);

  if (parsedUri != null &&
      (parsedUri.scheme == 'http' || parsedUri.scheme == 'https') &&
      parsedUri.host.isNotEmpty) {
    final uri = parsedUri;
    if (uri.pathSegments.isEmpty ||
        uri.pathSegments.every((segment) => segment.trim().isEmpty)) {
      throw Exception('Invalid organization URL provided: $cleanedUrl');
    }
    if (uri.pathSegments.length < 2) {
      // Treat as organization URL ---------------------------------------------
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
        ggLog(yellow('No repositories found for organization $orgName'));
        return;
      }
      for (final repoJson in reposJson) {
        final repoName = repoJson['name'] as String?;
        final cloneUrl = repoJson['clone_url'] as String?;
        if (repoName == null || cloneUrl == null) continue;
        await attemptClone(cloneUrl, repoName);
      }
    } else {
      // Treat as a repository URL ---------------------------------------------
      String repoUrl = cleanedUrl;
      if (!repoUrl.endsWith('.git')) {
        repoUrl = '$repoUrl.git';
      }
      final String repoName = extractRepoName(repoUrl);
      await attemptClone(repoUrl, repoName);
    }
  } else if (targetArg.startsWith('git@')) {
    // SSH URL -----------------------------------------------------------------
    final String repoUrl = targetArg;
    final String repoName = extractRepoName(repoUrl);
    await attemptClone(repoUrl, repoName);
  } else if (targetArg.contains('/')) {
    // username/repo -----------------------------------------------------------
    final String repoUrl = 'https://github.com/$targetArg.git';
    final String repoName = extractRepoName(repoUrl);
    await attemptClone(repoUrl, repoName);
  } else {
    // plain repo name ---------------------------------------------------------
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
    ggLog(
      red('pubspec.yaml not found in '
          'project $repoName in workspace $workspacePath.'),
    );
    return null;
  }
  try {
    final content = pubspecFile.readAsStringSync();
    return Pubspec.parse(content);
  } catch (e) {
    ggLog(red('Error parsing pubspec.yaml: $e'));
    return null;
  }
}
