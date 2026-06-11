// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_multi/src/backend/url_parser.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;
import 'git_handler.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'git_platform.dart';
import 'organization_utils.dart';
import 'repo_folder_resolver.dart';
import 'repository.dart';

/// Helper function to add a repository given a target argument.
/// It supports various formats like URLs, SSH links, and plain names.
/// For organization URLs, it fetches all repositories and clones them.
///
/// The [force] parameter determines whether an existing cloned
/// repository should be overwritten. If false and the destination
/// already exists and is not empty, the function logs "repo already added."
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
  required GitHandler gitCloner,
  GitHubPlatform? gitHubPlatform,
  AzureDevOpsPlatform? azureDevOpsPlatform,
  required String workspacePath,
  bool force = false,
  bool logIfAlreadyAdded = true,
  Future<void> Function(String repoName)? onRepoAdded,
}) async {
  // coverage:ignore-start
  gitHubPlatform ??= GitHubPlatform();
  azureDevOpsPlatform ??= AzureDevOpsPlatform();
  // coverage:ignore-end
  // ---------------------------------------------------------------------------
  /// Attempts to clone [repoUrl] as [repoName] into [workspacePath].
  /// If [allowFallback] is true and cloning fails, tries each known
  /// organization from .organizations file as a fallback.
  Future<void> attemptClone(
    String repoUrl,
    String repoName, {
    bool allowFallback = false,
  }) async {
    // If the repository is already present (under any folder name) ..........
    // For a plain-name add ([allowFallback]) the org is unknown, so any
    // folder carrying that repo name counts as present; for an explicit
    // url/org we match the exact remote so different orgs can coexist.
    final existing = existingCloneFolder(
      workspacePath: workspacePath,
      repoUrl: repoUrl,
      repoName: repoName,
      matchByNameOnly: allowFallback,
    );
    if (existing != null) {
      if (!force) {
        if (logIfAlreadyAdded) {
          ggLog(darkGray('$repoName already added.'));
        }
        if (onRepoAdded != null) {
          await onRepoAdded(repoName);
        }
        return;
      } else {
        await existing.delete(recursive: true);
      }
    }

    // Clones [url] into a staging folder and applies the org prefix.
    Future<void> cloneAndFinalize(String url) async {
      final staging = stagingCloneFolder(workspacePath, repoName);
      await GgStatusPrinter<void>(
        message: '${cyan(repoName)} from $url',
        ggLog: ggLog,
        useCarriageReturn: false,
      ).run(() => gitCloner.cloneRepo(url, staging.path));
      try {
        OrganizationUtils.appendOrganization(workspacePath, url);
      } catch (_) {
        // Swallow errors: organization info shouldn't block the core flow
      }
      finalizeClonedFolder(
        staging: staging,
        workspacePath: workspacePath,
        repoName: repoName,
        repoUrl: url,
        ggLog: ggLog,
      );
      if (onRepoAdded != null) {
        await onRepoAdded(repoName);
      }
    }

    // Explicit url/org add: clone exactly what was requested.
    if (!allowFallback) {
      await cloneAndFinalize(repoUrl);
      return;
    }

    // Plain-name add: try the known organizations first (the bare
    // "<name>/<name>" guess in [repoUrl] almost always 404s), and fall back
    // to that guess only when no organization has the repo.
    final orgs = OrganizationUtils.readOrganizations(workspacePath);
    final candidates = <String>[
      for (final org in orgs)
        '${org.url.endsWith('/') ? org.url : '${org.url}/'}$repoName.git',
      repoUrl,
    ];
    for (final url in candidates) {
      try {
        await cloneAndFinalize(url);
        return;
      } catch (_) {
        // Try the next candidate.
      }
    }
    ggLog(
      red('Failed to clone repository '
          '$repoName from any known organizations.'),
    );
  }

  // ---------------------------------------------------------------------------
  // Normalize URL: remove trailing "#" and "/" so that
  // "https://github.com/ggsuite/" and "https://github.com/ggsuite" behave the
  // same. This must happen before any URI parsing logic.
  var cleanedUrl = targetArg;
  while (cleanedUrl.endsWith('#') || cleanedUrl.endsWith('/')) {
    cleanedUrl = cleanedUrl.substring(0, cleanedUrl.length - 1);
  }

  final parsedUri = Uri.tryParse(cleanedUrl);

  if (parsedUri != null &&
      (parsedUri.scheme == 'http' || parsedUri.scheme == 'https') &&
      parsedUri.host.isNotEmpty) {
    UrlParser urlParser = const UrlParser();
    final parsedUrl = urlParser.parse(cleanedUrl);

    final uri = parsedUri;
    if (uri.pathSegments.isEmpty ||
        uri.pathSegments.every((segment) => segment.trim().isEmpty)) {
      throw Exception('Invalid organization URL provided: $cleanedUrl');
    }
    if (parsedUrl.repo == null &&
        parsedUrl.org != null &&
        parsedUrl.platformType == 'github') {
      // Treat as organization URL ---------------------------------------------

      final List<Repository> repos =
          await gitHubPlatform.fetchOrgRepos(parsedUrl.org!);
      if (repos.isEmpty) {
        ggLog(
          yellow('No repositories found for organization '
              '${parsedUrl.org!}'),
        );
        return;
      }
      await runWithLimit(
        repos,
        4,
        (repo) => attemptClone(repo.cloneUrl, repo.name),
      );
    } else if (parsedUrl.repo == null &&
        parsedUrl.org != null &&
        parsedUrl.platformType == 'azure' &&
        parsedUrl.project != null) {
      // Treat as Azure organization URL ---------------------------------------
      try {
        final List<Repository> repos = await azureDevOpsPlatform.fetchOrgRepos(
          parsedUrl.org!,
          project: parsedUrl.project,
        );
        if (repos.isEmpty) {
          ggLog(
            yellow('No repositories found for organization '
                '${parsedUrl.org!} and project ${parsedUrl.project}'),
          );
          return;
        }
        await runWithLimit(
          repos,
          4,
          (repo) => attemptClone(repo.cloneUrl, repo.name),
        );
      } catch (e) {
        if (e.toString().contains('Bitte installiere die Azure CLI')) {
          ggLog(yellow(e.toString().replaceAll('Exception: ', '')));
          return;
        } else {
          rethrow;
        }
      }
    } else {
      // Treat as a repository URL ---------------------------------------------
      String repoUrl = cleanedUrl;
      if (!repoUrl.endsWith('.git')) {
        repoUrl = '$repoUrl.git';
      }
      final String repoName = extractRepoName(repoUrl) ?? 'unknown_repo';
      await attemptClone(repoUrl, repoName);
    }
  } else if (targetArg.startsWith('git@ssh.dev.azure.com:')) {
    // Azure DevOps SSH --------------------------------------------------------
    final String repoName = extractRepoName(targetArg) ?? 'unknown_repo';
    await attemptClone(targetArg, repoName);
  } else if (targetArg.startsWith('git@')) {
    // SSH URL -----------------------------------------------------------------
    final String repoName = extractRepoName(targetArg) ?? 'unknown_repo';
    await attemptClone(targetArg, repoName);
  } else if (targetArg.contains('/')) {
    // username/repo -----------------------------------------------------------
    final String repoUrl = 'https://github.com/$targetArg.git';
    final String repoName = extractRepoName(repoUrl) ?? 'unknown_repo';
    await attemptClone(repoUrl, repoName);
  } else {
    // plain repo name ---------------------------------------------------------
    final String repoUrl = 'https://github.com/$targetArg/$targetArg.git';
    final String repoName = extractRepoName(repoUrl) ?? 'unknown_repo';
    await attemptClone(repoUrl, repoName, allowFallback: true);
  }
}

/// Processes [items] with [task], running up to [maxParallel] tasks at a time.
/// Tasks run in submission order; the first failure is rethrown after all
/// already-started tasks have settled.
Future<void> runWithLimit<T>(
  Iterable<T> items,
  int maxParallel,
  Future<void> Function(T item) task,
) async {
  final queue = items.toList();
  var nextIndex = 0;

  Future<void> worker() async {
    while (true) {
      if (nextIndex >= queue.length) {
        return;
      }
      final item = queue[nextIndex++];
      await task(item);
    }
  }

  final workers = <Future<void>>[
    for (var i = 0; i < maxParallel && i < queue.length; i++) worker(),
  ];

  await Future.wait(workers);
}

/// Extracts the repository name from a git URL supporting:
/// - GitHub SSH (git@github.com:owner/repo.git)
/// - Azure DevOps SSH (git@ssh.dev.azure.com:v3/org/project/repo(.git))
/// - HTTPS (https://github.com/owner/repo(.git))
/// - username/repo
String? extractRepoName(String repoUrl) {
  UrlParser urlParser = const UrlParser();
  return urlParser.parse(repoUrl).repo;
}

/// Returns the folder already holding this repo, or null. Matches by git
/// remote (any folder name), then by a folder named exactly [repoName]
/// (legacy layout). [matchByNameOnly] (plain-name adds with unknown org)
/// additionally accepts an org-prefixed folder via its package name.
Directory? existingCloneFolder({
  required String workspacePath,
  required String repoUrl,
  required String repoName,
  bool matchByNameOnly = false,
}) {
  final byUrl = RepoFolderResolver.resolveByRemoteUrl(
    workspacePath: workspacePath,
    repoUrl: repoUrl,
  );
  if (byUrl != null) {
    return byUrl;
  }
  final exact = Directory(path.join(workspacePath, repoName));
  if (exact.existsSync() && exact.listSync().isNotEmpty) {
    return exact;
  }
  return matchByNameOnly
      ? RepoFolderResolver.resolve(
          workspacePath: workspacePath,
          repoName: repoName,
        )
      : null;
}

/// Returns a free folder to clone [repoName] into: the plain repo name,
/// or a temporary name when that folder is already taken.
Directory stagingCloneFolder(String workspacePath, String repoName) {
  final plain = Directory(path.join(workspacePath, repoName));
  if (!plain.existsSync() || plain.listSync().isEmpty) {
    return plain;
  }
  final tmp = Directory(path.join(workspacePath, '$repoName.clone-tmp'));
  if (tmp.existsSync()) {
    tmp.deleteSync(recursive: true);
  }
  return tmp;
}

/// Renames the freshly cloned [staging] folder to its org-prefixed name.
/// Keeps the staging name when no prefix applies or the target is taken.
void finalizeClonedFolder({
  required Directory staging,
  required String workspacePath,
  required String repoName,
  required String repoUrl,
  required GgLog ggLog,
}) {
  final org = const UrlParser().parse(repoUrl).org;
  final folderName = RepoFolderResolver.orgPrefixedFolderName(
    repoName: repoName,
    org: org,
    repoDir: staging,
  );
  if (folderName == path.basename(staging.path)) {
    return;
  }
  final target = Directory(path.join(workspacePath, folderName));
  try {
    if (target.existsSync()) {
      throw FileSystemException('Target folder exists', target.path);
    }
    staging.renameSync(target.path);
  } catch (e) {
    ggLog(
      yellow(
        'Could not rename $repoName to $folderName: $e — '
        'keeping ${path.basename(staging.path)}.',
      ),
    );
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
  final repoDir = (repoName != null
          ? RepoFolderResolver.resolve(
              workspacePath: workspacePath,
              repoName: repoName,
            )
          : null) ??
      Directory(path.join(workspacePath, repoName ?? ''));
  final pubspecPath = path.join(repoDir.path, 'pubspec.yaml');
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
