// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:gg_console_colors/gg_console_colors.dart';
// ignore: lines_longer_than_80_chars
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_localize_refs/gg_localize_refs.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart';

import '../../backend/git_handler.dart' hide ProcessRunner;
import '../../backend/add_repository_helper.dart';
import '../../backend/filesystem_utils.dart';
import '../../backend/git_platform.dart' hide ProcessRunner;
import '../../backend/legacy_git_hooks.dart';
import '../../backend/organization_utils.dart';
import '../../backend/repo_folder_resolver.dart';
import '../../backend/repo_setup.dart';
import '../../backend/ticket_json.dart';
import '../../backend/workspace_migration.dart';
import '../../backend/workspace_utils.dart';
import 'add_deps.dart' show fetchDependencyRepoUrl;
import 'install_gitattributes.dart' hide ProcessRunner;

/// Resolves the repository URL of a hosted dependency.
/// Subset of [fetchDependencyRepoUrl] without named args, for test stubs.
typedef FetchRepoUrl = Future<String?> Function(String packageName);

/// Command to add a repo or all repos of an organization to master+ticket.
/// In ticket mode it also auto-clones transitive deps and re-localizes refs.
/// Use `--force` to overwrite an existing repo in the master workspace.
class AddCommand extends Command<dynamic> {
  /// Constructor for AddCommand.
  AddCommand({
    required this.ggLog,
    GitHandler? gitCloner,
    GitHubPlatform? gitHubPlatform,
    ProcessRunner? processRunner,
    String? masterWorkspacePath,
    String? executionPath,
    gg.DoCommit? ggDoCommit,
    SortedProcessingList? sortedProcessingList,
    ChangeRefsToPubDev? unlocalizeRefs,
    ChangeRefsToLocal? localizeRefs,
    BackupPublishTo? backupPublishTo,
    Graph? graph,
    FetchRepoUrl? fetchRepoUrl,
    SelectOrganization? selectOrganization,
    // coverage:ignore-start
  })  : _selectOrganization = selectOrganization ?? defaultSelectOrganization,
        gitCloner = gitCloner ?? GitHandler(),
        gitHubPlatform = gitHubPlatform ?? GitHubPlatform(),
        processRunner = processRunner ?? Process.run,
        executionPath = executionPath ?? Directory.current.path,
        masterWorkspacePath =
            masterWorkspacePath ?? WorkspaceUtils.defaultMasterWorkspacePath(),
        _ggDoCommit = ggDoCommit ?? gg.DoCommit(ggLog: ggLog),
        _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog),
        _unlocalizeRefs = unlocalizeRefs ?? ChangeRefsToPubDev(ggLog: ggLog),
        _localizeRefs = localizeRefs ?? ChangeRefsToLocal(ggLog: ggLog),
        _backupPublishTo = backupPublishTo ?? BackupPublishTo(ggLog: ggLog),
        _graph = graph ?? Graph(ggLog: ggLog),
        _fetchRepoUrl = fetchRepoUrl ?? fetchDependencyRepoUrl
  // coverage:ignore-end
  {
    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Overwrite existing repository in master workspace.',
      defaultsTo: false,
    );
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'Enable verbose logging.',
      defaultsTo: false,
    );
  }

  /// The log function.
  final GgLog ggLog;

  /// Instance to handle cloning.
  final GitHandler gitCloner;

  /// Optional GitHub platform instance to handle GitHub-specific operations.
  final GitHubPlatform? gitHubPlatform;

  /// Instance to handle running general processes.
  final ProcessRunner processRunner;

  /// Resolved master workspace path.
  final String masterWorkspacePath;

  /// The path from which the command was executed.
  final String executionPath;

  /// gg do commit used after localization with --git in ticket copies.
  final gg.DoCommit _ggDoCommit;

  /// Sorted processing helper for ticket-wide iteration.
  final SortedProcessingList _sortedProcessingList;

  /// Unlocalize refs helper.
  final ChangeRefsToPubDev _unlocalizeRefs;

  /// Localize refs helper.
  final ChangeRefsToLocal _localizeRefs;

  /// Captures original `publish_to` so it can be restored on publish.
  final BackupPublishTo _backupPublishTo;

  /// Graph helper for determining nodes between endpoints.
  final Graph _graph;

  /// Resolves a hosted-dep repo URL; tests inject stubs (incl. throwing).
  final FetchRepoUrl _fetchRepoUrl;

  /// Asks which organization a plain repo name refers to when several own it.
  final SelectOrganization _selectOrganization;

  @override
  String get name => 'add';

  @override
  String get description => 'Adds the specified git repo or all git repos '
      'from the specified organization into the master workspace-and if run '
      'from inside a ticket, also into that ticket workspace. After adding, '
      'all repositories in the ticket are unlocalized and then localized '
      'with --git in two passes.';

  @override
  Future<void> run() async {
    if (argResults!.rest.isEmpty) {
      throw UsageException('Missing target parameter.', usage);
    }

    final targets = argResults!.rest;
    final bool force = argResults!['force'] as bool;
    final String? ticketPath = WorkspaceUtils.detectTicketPath(executionPath);
    final bool verbose = argResults!['verbose'] as bool? ?? false;

    // Maintenance: a workspace created before gg grouped its repositories by
    // organization still holds them flat. Move them first, so everything
    // below sees a single layout.
    migrateToOrgFolders(workspacePath: masterWorkspacePath, ggLog: ggLog);
    if (ticketPath != null) {
      // The ticket is re-localized at the end of this run, which repairs the
      // relative path references the move invalidates.
      migrateToOrgFolders(workspacePath: ticketPath, ggLog: ggLog);
    }

    // If not in a ticket workspace: keep original behaviour (no graph logic).
    if (ticketPath == null) {
      await runWithLimit(
        targets,
        4,
        (targetArg) => addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: gitCloner,
          gitHubPlatform: gitHubPlatform,
          workspacePath: masterWorkspacePath,
          force: force,
          logIfAlreadyAdded: true,
          selectOrganization: _selectOrganization,
        ),
      );
      return;
    }

    // Ticket mode: ensure requested repos are present in master first.
    final requestedRepoNames = <String>{};
    for (final targetArg in targets) {
      final repoName = extractRepoName(targetArg);
      if (repoName != null) {
        requestedRepoNames.add(repoName);
      }
    }
    await runWithLimit(
      targets,
      4,
      (targetArg) => addRepositoryHelper(
        targetArg: targetArg,
        ggLog: ggLog,
        gitCloner: gitCloner,
        gitHubPlatform: gitHubPlatform,
        workspacePath: masterWorkspacePath,
        force: force,
        // When inside a ticket we do not spam "already added" messages.
        logIfAlreadyAdded: false,
        selectOrganization: _selectOrganization,
        // We intentionally do not copy here; we copy after graph processing.
      ),
    );

    // Clone missing transitive deps so the graph can resolve between-nodes.
    await _cloneMissingTransitiveDeps(ggLog: ggLog);

    final ticketDir = Directory(ticketPath);

    // Build dep graph of master + compute nodes between endpoints.
    Map<String, Node> allNodes = const {};
    try {
      allNodes = await _graph.get(
        directory: Directory(masterWorkspacePath),
        ggLog: ggLog,
      );
    } catch (e) {
      ggLog(
        red('Failed to build dependency graph: $e'),
      );
      allNodes = const {};
    }

    // Endpoints = CLI-requested repos + repos already in the ticket.
    final endpointsByName = <String, Node>{};

    // Endpoints based on requested repositories ------------------------------
    for (final name in requestedRepoNames) {
      final node = findNode(
        packageName: name,
        nodes: allNodes,
      );
      if (node != null) {
        endpointsByName.putIfAbsent(node.name, () => node);
      }
    }

    // Additional endpoints from existing ticket repositories -----------------
    final existingTicketRepos = RepoFolderResolver.repoDirs(ticketPath);

    for (final repoDir in existingTicketRepos) {
      final repoName = RepoFolderResolver.packageName(repoDir) ??
          path.basename(repoDir.path);
      final node = findNode(
        packageName: repoName,
        nodes: allNodes,
      );
      if (node != null) {
        endpointsByName.putIfAbsent(node.name, () => node);
      }
    }

    final endpoints = endpointsByName.values.toList();

    final betweenNodes = endpoints.length >= 2
        ? _graph.getNodesBetween(
            allNodes,
            endpoints,
          )
        : <Node>[];

    final finalToCopy = <String>{
      ...requestedRepoNames,
      // Use the directory name, not the (primary) package name: for a
      // cross-language bridge repo the Dart package name differs from the
      // folder name, and the copy step locates repos by folder name.
      ...betweenNodes.map((n) => path.basename(n.directory.path)),
    };

    final GgLog taskLog = verbose ? ggLog : <String>[].add;

    ggLog(yellow('Copying the following repos:'));

    await _copyReposToTicket(
      ticketPath: ticketPath,
      repoNames: finalToCopy,
      ggLog: taskLog,
      reportLog: ggLog,
    );

    // Write config files (workspace, .gitattributes) before commit.
    await GgStatusPrinter<void>(
      message: 'Writing project config files',
      ggLog: ggLog,
    ).run(
      () => _writeProjectConfigFiles(
        ticketDir: ticketDir,
        ggLog: taskLog,
      ),
    );

    // Finally perform a single re-localization pass for the whole ticket.
    await GgStatusPrinter<void>(
      message: 'Set dependencies to path, committing',
      ggLog: ggLog,
    ).run(
      () => _relocalizeAllReposInTicket(
        ticketDir: ticketDir,
        ggLog: taskLog,
      ),
    );
  }

  // Ticket support helpers
  // ...........................................................................
  /// Clones missing deps of every repo in master that belongs to a known org.
  /// Git deps go via [addRepositoryHelper]; hosted deps via pub.dev lookup.
  /// Loops to a fixpoint; failures are swallowed (helper already logs).
  Future<void> _cloneMissingTransitiveDeps({
    required GgLog ggLog,
  }) async {
    final masterDir = Directory(masterWorkspacePath);
    if (!masterDir.existsSync()) {
      return;
    }

    // Normalize known org URLs once (e.g. "https://github.com/ggsuite").
    final orgs = OrganizationUtils.readOrganizations(masterWorkspacePath);
    final orgUrls = orgs
        .map((o) => o.url.replaceAll(RegExp(r'/+$'), '').toLowerCase())
        .toSet();

    // Known org names, used to map npm scopes (`@<org>/<name>`) back to a
    // cloneable repository in a known organization.
    final orgNames = orgs.map((o) => o.name.toLowerCase()).toSet();

    // Cache pub.dev lookups across the fixpoint loop.
    final hostedLookupCache = <String, String?>{};

    while (true) {
      final existingDirs = RepoFolderResolver.repoDirs(masterWorkspacePath);

      // Known names: folder basenames plus manifest package names, so that
      // a cross-language bridge repo (whose folder name differs from its
      // package name) is recognized by its package name too.
      final knownPackages = <String>{};
      for (final dir in existingDirs) {
        knownPackages.add(path.basename(dir.path));
        final packageName = RepoFolderResolver.packageName(dir);
        if (packageName != null) {
          knownPackages.add(packageName);
        }
      }

      // Plan: depName -> targetArg (name for git, full URL for hosted).
      final plan = <String, String>{};

      for (final repoDir in existingDirs) {
        Future<void> scan(Map<String, Dependency> deps) async {
          for (final entry in deps.entries) {
            final depName = entry.key;
            if (knownPackages.contains(depName) || plan.containsKey(depName)) {
              continue;
            }
            final dep = entry.value;
            if (dep is GitDependency) {
              plan[depName] = depName; // helper falls back to org URLs
            } else if (dep is HostedDependency) {
              // Resolve repo URL via pub.dev; accept only known-org URLs.
              if (!hostedLookupCache.containsKey(depName)) {
                try {
                  hostedLookupCache[depName] = await _fetchRepoUrl(depName);
                } catch (_) {
                  hostedLookupCache[depName] = null;
                }
              }
              final repoUrl = hostedLookupCache[depName];
              if (repoUrl == null || repoUrl.isEmpty) {
                continue;
              }
              final normalized =
                  repoUrl.replaceAll(RegExp(r'/+$'), '').toLowerCase();
              final inKnownOrg = orgUrls.any(
                (o) => normalized.startsWith(o),
              );
              if (!inKnownOrg) {
                continue;
              }
              plan[depName] = repoUrl;
            }
          }
        }

        // Dart: scan pubspec.yaml dependencies.
        final pubspecFile = File(path.join(repoDir.path, 'pubspec.yaml'));
        if (pubspecFile.existsSync()) {
          Pubspec? parsed;
          try {
            parsed = Pubspec.parse(pubspecFile.readAsStringSync());
          } catch (_) {
            parsed = null; // skip unparseable pubspec
          }
          if (parsed != null) {
            await scan(parsed.dependencies);
            await scan(parsed.devDependencies);
          }
        }

        // TypeScript: scan package.json for cross-language (npm) deps so a
        // bridge referenced only from the TypeScript side is cloned too.
        _planNpmDepsFromPackageJson(
          repoDir: repoDir,
          knownPackages: knownPackages,
          orgNames: orgNames,
          plan: plan,
        );
      }

      if (plan.isEmpty) {
        return;
      }

      bool addedAny = false;
      for (final entry in plan.entries) {
        final depName = entry.key;
        Directory? destDir = RepoFolderResolver.resolve(
          workspacePath: masterWorkspacePath,
          repoName: depName,
        );
        if (destDir != null) {
          continue;
        }
        try {
          await addRepositoryHelper(
            targetArg: entry.value,
            ggLog: ggLog,
            gitCloner: gitCloner,
            gitHubPlatform: gitHubPlatform,
            workspacePath: masterWorkspacePath,
            logIfAlreadyAdded: false,
            selectOrganization: _selectOrganization,
          );
        } catch (_) {
          // Swallow: addRepositoryHelper already logged the failure.
        }
        destDir = RepoFolderResolver.resolve(
          workspacePath: masterWorkspacePath,
          repoName: depName,
        );
        if (destDir != null) {
          addedAny = true;
        }
      }

      // No progress -> stop (e.g. remaining deps are unreachable).
      if (!addedAny) {
        return;
      }
    }
  }

  // ...........................................................................
  /// Adds the scoped npm dependencies of [repoDir]'s `package.json` to [plan]
  /// when their scope maps to a known organization in [orgNames].
  ///
  /// This is what makes the transitive clone cross-language: a bridge repo
  /// that is only referenced from a TypeScript package (via its npm name,
  /// e.g. `@tssuite/gg-bridge-dart-typescript`) still gets cloned into the
  /// master workspace. The bare package name is used as target so that
  /// [addRepositoryHelper] resolves it against the known organization URLs.
  void _planNpmDepsFromPackageJson({
    required Directory repoDir,
    required Set<String> knownPackages,
    required Set<String> orgNames,
    required Map<String, String> plan,
  }) {
    final packageJsonFile = File(path.join(repoDir.path, 'package.json'));
    if (!packageJsonFile.existsSync()) {
      return;
    }

    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(packageJsonFile.readAsStringSync());
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      json = decoded;
    } catch (_) {
      return; // skip unparseable package.json
    }

    void scanSection(String section) {
      final deps = json[section];
      if (deps is! Map<String, dynamic>) {
        return;
      }
      for (final fullName in deps.keys) {
        // Only scoped deps (`@org/name`) can be mapped back to an org.
        if (!fullName.startsWith('@')) {
          continue;
        }
        final slash = fullName.indexOf('/');
        if (slash <= 1 || slash == fullName.length - 1) {
          continue;
        }
        final scope = fullName.substring(1, slash).toLowerCase();
        if (!orgNames.contains(scope)) {
          continue;
        }
        final bareName = fullName.substring(slash + 1);
        if (knownPackages.contains(bareName) || plan.containsKey(bareName)) {
          continue;
        }
        // Bare name: addRepositoryHelper falls back to known org URLs.
        plan[bareName] = bareName;
      }
    }

    scanSection('dependencies');
    scanSection('devDependencies');
  }

  // ...........................................................................
  /// Find a node by package name in the dependency graph.
  Node? findNode({
    required String packageName,
    required Map<String, Node> nodes,
  }) {
    if (nodes.isEmpty) {
      return null;
    }
    Node? node = nodes[packageName];
    if (node != null) {
      return node;
    }
    for (final Node n in nodes.values) {
      // Match by primary name or any cross-language alias (Dart name, npm
      // name, directory name), so a repo can be requested under any of them.
      if (n.name == packageName || n.aliases.contains(packageName)) {
        return n;
      }
      final Node? foundNode = findNode(
        packageName: packageName,
        nodes: n.dependencies,
      );
      if (foundNode != null) {
        return foundNode;
      }
    }
    return null;
  }

  /// Copies all [repoNames] from master into the ticket at [ticketPath].
  /// Up to [maxParallel] parallel; status via [reportLog], verbose via
  /// [ggLog].
  Future<void> _copyReposToTicket({
    required String ticketPath,
    required Set<String> repoNames,
    required GgLog ggLog,
    required GgLog reportLog,
    int maxParallel = 4,
  }) async {
    final queue = repoNames.toList();
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final int index;
        if (nextIndex >= queue.length) {
          return;
        }
        index = nextIndex++;
        final repoName = queue[index];
        await _copyRepoToTicket(
          repoName: repoName,
          ticketPath: ticketPath,
          ggLog: ggLog,
        );
        reportLog(blue('✅ $repoName'));
      }
    }

    final workers = <Future<void>>[
      for (var i = 0; i < maxParallel && i < queue.length; i++) worker(),
    ];

    await Future.wait(workers);
  }

  /// Copies the repository from the master workspace to the [ticketPath] but
  /// does not trigger a ticket-wide relocalization.
  Future<void> _copyRepoToTicket({
    required String repoName,
    required String ticketPath,
    required GgLog ggLog,
  }) async {
    final srcDir = RepoFolderResolver.resolve(
      workspacePath: masterWorkspacePath,
      repoName: repoName,
    );
    if (srcDir == null) {
      ggLog(red('Repository $repoName not found in master workspace.'));
      return;
    }

    // The ticket copy keeps the location the repo has in the master
    // workspace, i.e. `<ticket>/<org>/<repo>`.
    final relativePath = RepoFolderResolver.relativePath(
      workspacePath: masterWorkspacePath,
      repoDir: srcDir,
    );
    final destDir = Directory(path.join(ticketPath, relativePath));
    if (destDir.existsSync() && destDir.listSync().isNotEmpty) {
      ggLog(darkGray('$repoName already exists in ticket workspace.'));
      return;
    }

    await _prepareMasterRepositoryForCopy(
      repoDir: srcDir,
      repoName: repoName,
      ggLog: ggLog,
    );

    // Copy from master into ticket -------------------------------------------
    await copyDirectory(srcDir, destDir);

    final String ticketName = path.basename(ticketPath);

    // Checkout a branch named as the ticket ----------------------------------
    try {
      await gitCloner.checkoutBranch(ticketName, destDir.path);
    } catch (e) {
      ggLog(red('Failed to checkout branch $ticketName: $e'));
    }

    // Install deps for every package manager the repo uses (Dart and/or TS).
    await installRepoDependencies(
      dir: destDir,
      repoName: repoName,
      ggLog: ggLog,
      processRunner: processRunner,
    );

    ggLog(blue('Added repository $repoName to ticket workspace.'));
  }

  /// Prepares the master repository state before copying it into a ticket.
  Future<void> _prepareMasterRepositoryForCopy({
    required Directory repoDir,
    required String repoName,
    required GgLog ggLog,
  }) async {
    await _gitFetch(repoDir: repoDir, repoName: repoName, ggLog: ggLog);
    await _gitResetHardToOriginMain(
      repoDir: repoDir,
      repoName: repoName,
      ggLog: ggLog,
    );
    await _gitDeleteAllLocalTags(
      repoDir: repoDir,
      repoName: repoName,
      ggLog: ggLog,
    );
    await _gitFetchTags(repoDir: repoDir, repoName: repoName, ggLog: ggLog);
    await _gitFetchPruneTags(
      repoDir: repoDir,
      repoName: repoName,
      ggLog: ggLog,
    );

    // The runtime progress of a publish (.gg/gg-publish.json) is gitignored,
    // so the reset above never removes it. It records the progress of a
    // publish of ANOTHER branch and must not linger in the master workspace —
    // and never reach a ticket copy (copyDirectory skips it too).
    final stalePublishProgress = File(
      path.join(repoDir.path, '.gg', 'gg-publish.json'),
    );
    if (stalePublishProgress.existsSync()) {
      stalePublishProgress.deleteSync();
      ggLog(
        yellow(
          'Removed stale publish progress '
          '(.gg/gg-publish.json) in $repoName.',
        ),
      );
    }
  }

  /// Runs a single git command in [repoDir] and logs success/failure.
  Future<ProcessResult> _runGit({
    required Directory repoDir,
    required List<String> arguments,
    required String successMessage,
    required String failureLabel,
    required GgLog ggLog,
  }) async {
    final result = await processRunner(
      'git',
      arguments,
      workingDirectory: repoDir.path,
      runInShell: true,
    );

    if (result.exitCode != 0) {
      ggLog(red('Failed to execute $failureLabel: ${result.stderr}'));
    } else {
      ggLog(darkGray(successMessage));
    }
    return result;
  }

  /// Runs `git fetch` in [repoDir].
  Future<void> _gitFetch({
    required Directory repoDir,
    required String repoName,
    required GgLog ggLog,
  }) async {
    await _runGit(
      repoDir: repoDir,
      arguments: <String>['fetch'],
      successMessage: 'Executed git fetch in $repoName in master workspace.',
      failureLabel: 'git fetch in $repoName in master workspace',
      ggLog: ggLog,
    );
  }

  /// Runs `git reset --hard origin/main` in [repoDir].
  Future<void> _gitResetHardToOriginMain({
    required Directory repoDir,
    required String repoName,
    required GgLog ggLog,
  }) async {
    await _runGit(
      repoDir: repoDir,
      arguments: <String>['reset', '--hard', 'origin/main'],
      successMessage: 'Executed git reset --hard origin/main in '
          '$repoName in master workspace.',
      failureLabel:
          'git reset --hard origin/main in $repoName in master workspace',
      ggLog: ggLog,
    );
  }

  /// Deletes all local tags in [repoDir] without using a shell pipe.
  /// Lists tags via `git tag -l`, then `git tag -d <tags...>` in one call
  /// (macOS-safe; xargs-pipe variant fails under Process.run).
  Future<void> _gitDeleteAllLocalTags({
    required Directory repoDir,
    required String repoName,
    required GgLog ggLog,
  }) async {
    final list = await _runGit(
      repoDir: repoDir,
      arguments: <String>['tag', '-l'],
      successMessage: 'Listed local tags in $repoName in master workspace.',
      failureLabel: 'git tag -l in $repoName in master workspace',
      ggLog: ggLog,
    );

    if (list.exitCode != 0) {
      return;
    }

    final tags = (list.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (tags.isEmpty) {
      ggLog(
        darkGray(
          'No local tags to delete in $repoName in master workspace.',
        ),
      );
      return;
    }

    await _runGit(
      repoDir: repoDir,
      arguments: <String>['tag', '-d', ...tags],
      successMessage:
          'Deleted ${tags.length} local tag(s) in $repoName in master '
          'workspace.',
      failureLabel: 'git tag -d <tags> in $repoName in master workspace',
      ggLog: ggLog,
    );
  }

  /// Runs `git fetch --tags` in [repoDir].
  Future<void> _gitFetchTags({
    required Directory repoDir,
    required String repoName,
    required GgLog ggLog,
  }) async {
    await _runGit(
      repoDir: repoDir,
      arguments: <String>['fetch', '--tags'],
      successMessage:
          'Executed git fetch --tags in $repoName in master workspace.',
      failureLabel: 'git fetch --tags in $repoName in master workspace',
      ggLog: ggLog,
    );
  }

  /// Runs `git fetch --prune --tags` in [repoDir].
  Future<void> _gitFetchPruneTags({
    required Directory repoDir,
    required String repoName,
    required GgLog ggLog,
  }) async {
    await _runGit(
      repoDir: repoDir,
      arguments: <String>['fetch', '--prune', '--tags'],
      successMessage: 'Executed git fetch --prune --tags in '
          '$repoName in master workspace.',
      failureLabel: 'git fetch --prune --tags in $repoName in master workspace',
      ggLog: ggLog,
    );
  }

  /// Re-localizes all ticket repos in two passes (sorted order):
  /// 1) unlocalize, 2) localize --git + pub upgrade + commit.
  Future<void> _relocalizeAllReposInTicket({
    required Directory ticketDir,
    required GgLog ggLog,
  }) async {
    final ticketName = path.basename(ticketDir.path);

    // Collect repositories in processing order.
    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (nodes.isEmpty) {
      ggLog(yellow('⚠️ No repos in this ticket'));
      return;
    }

    // Write the ticket marker into every repo so the full ticket layout
    // travels with each feature branch. It is overwritten on every `do add`,
    // keeping the repo list current, and committed in iteration 2 below.
    final repoDirs = nodes.map((n) => n.directory).toList();
    writeTicketJsonToRepos(
      repoDirs: repoDirs,
      ticket: buildTicketJson(ticketDir: ticketDir, repoDirs: repoDirs),
    );

    // Iteration 1: Unlocalize all ---------------------------------------------
    for (final node in nodes) {
      final repoDir = node.directory;
      final repoName = path.basename(repoDir.path);
      try {
        // Dart and TypeScript each keep their own backup in .gg today; the
        // shared and root-level names are what older checkouts still carry.
        final backupFiles = [
          for (final name in const <String>[
            'gg_localize_refs_backup_dart.json',
            'gg_localize_refs_backup_ts.json',
            'gg_localize_refs_backup.json',
          ])
            File(path.join(repoDir.path, '.gg', name)),
          File(path.join(repoDir.path, '.gg_localize_refs_backup.json')),
        ];
        if (backupFiles.any((f) => f.existsSync())) {
          await _unlocalizeRefs.get(directory: repoDir, ggLog: ggLog);
        }
      } catch (e) {
        ggLog(red('Failed to unlocalize refs for $repoName: $e'));
        throw Exception('Failed to relocalize ticket');
      }
    }

    // Iteration 2: Localize ---------------------------------------------------
    for (final node in nodes) {
      final repoDir = node.directory;
      final repoName = path.basename(repoDir.path);
      try {
        await _backupPublishTo.exec(directory: repoDir, ggLog: ggLog);
        await _localizeRefs.get(directory: repoDir, ggLog: ggLog);
      } catch (e) {
        ggLog(red('Failed to localize refs for $repoName: $e'));
        throw Exception('Failed to relocalize ticket');
      }

      // Refresh deps after relocalize (dart pub upgrade and/or pm install).
      await installRepoDependencies(
        dir: repoDir,
        repoName: repoName,
        ggLog: ggLog,
        processRunner: processRunner,
        upgradeDart: true,
      );

      // Force-stage the ticket marker: `.gg/` is gitignored, so a plain
      // `git add .` would skip it. Force-adding makes it a tracked file that
      // travels with the feature branch.
      await _runGit(
        repoDir: repoDir,
        arguments: const ['add', '-f', '.gg/.ticket.json'],
        successMessage: 'Staged .gg/.ticket.json in $repoName.',
        failureLabel: 'git add -f .gg/.ticket.json in $repoName',
        ggLog: ggLog,
      );

      // Commit per repo; skip changelog (gg_changelog needs pubspec.yaml).
      try {
        await _ggDoCommit.exec(
          directory: repoDir,
          ggLog: ggLog,
          message: '#gg: changed references to path',
          force: true,
          updateChangeLog: false,
        );
      } catch (e) {
        ggLog(red('Failed to commit $repoName: $e'));
      }
    }

    ggLog('✅ Re-localized all repositories in ticket $ticketName.');
  }

  /// Rewrites the VS Code `.code-workspace` file for the given [ticketDir]
  /// with one folder entry per repository in the ticket.
  Future<void> _rewriteCodeWorkspace({
    required Directory ticketDir,
    required GgLog ggLog,
  }) async {
    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    // The entries are relative to the ticket root, so a repo inside an
    // organization folder is listed as `<org>/<repo>`.
    final folderPaths = <String>{
      for (final node in nodes)
        RepoFolderResolver.relativePath(
          workspacePath: ticketDir.path,
          repoDir: node.directory,
        ),
    };

    writeCodeWorkspaceFile(ticketDir, folderPaths.toList());
  }

  /// Writes all project configuration files that depend on the set of
  /// repositories in a ticket, such as the VS Code workspace and
  /// `.gitattributes`.
  ///
  /// Also removes the obsolete `gg`-generated pre-push hook from every repo of
  /// the ticket. `gg` no longer installs git hooks — pushing to `main` is
  /// blocked by the remote and merges go through pull requests — but a hook
  /// installed by an older `gg do add` survives in checkouts and would keep
  /// running on every push.
  Future<void> _writeProjectConfigFiles({
    required Directory ticketDir,
    required GgLog ggLog,
  }) async {
    await _rewriteCodeWorkspace(ticketDir: ticketDir, ggLog: ggLog);

    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    for (final node in nodes) {
      removeLegacyGitHooks(repoDir: node.directory, ggLog: ggLog);
    }

    await DoInstallGitattributesCommand(
      ggLog: ggLog,
      sortedProcessingList: _sortedProcessingList,
      processRunner: processRunner,
    ).exec(
      directory: ticketDir,
      ggLog: ggLog,
    );
  }
}
