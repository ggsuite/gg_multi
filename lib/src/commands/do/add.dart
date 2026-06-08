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
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_localize_refs/gg_localize_refs.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart';

import '../../backend/git_handler.dart';
import '../../backend/add_repository_helper.dart';
import '../../backend/filesystem_utils.dart';
import '../../backend/git_platform.dart';
import '../../backend/organization_utils.dart';
import '../../backend/workspace_utils.dart';
import 'add_deps.dart' show fetchDependencyRepoUrl;
import 'install_git_hooks.dart';
import 'install_gitattributes.dart';

/// Typedef for a process runner function.
typedef ProcessRunner = Future<ProcessResult> Function(
  String,
  List<String>, {
  String? workingDirectory,
  bool runInShell,
});

/// Command to add a repository or all repositories from an organization.
///
/// This command adds the specified git repo (also Gitlab and other servers
/// compatible) or all git repos of the specified organization.
/// It clones the project into the master workspace of the project root and-
/// if executed from inside a ticket directory (./tickets/ticket)-it also
/// copies the repository into this ticket directory.  After copying, it
/// performs a ticket-wide two-pass re-localization:
/// 1) Unlocalize all repositories in the ticket in sorted processing order.
/// 2) Localize all repositories with --git, set git-localized status and
///    commit changes per repository. Any error aborts the flow immediately.
///    After localization, if a pubspec.yaml exists, "dart pub upgrade" is
///    executed and must succeed before committing.
///
/// When running inside a ticket workspace, the dependency graph that is used
/// for determining nodes *between* endpoints considers both endpoints that
/// stem from the CLI arguments *and* endpoints of repositories that already
/// exist in the ticket workspace. This allows adding the missing
/// repositories between an already present repo and a newly added one.
///
/// Use the "--force" flag to overwrite an existing repository in the master
/// workspace.
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
    // coverage:ignore-start
  })  : gitCloner = gitCloner ?? GitHandler(),
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
        _graph = graph ?? Graph(ggLog: ggLog)
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

  /// gg do commit instance used after localization with --git in ticket
  /// copies.
  final gg.DoCommit _ggDoCommit;

  /// Sorted processing helper for ticket-wide iteration.
  final SortedProcessingList _sortedProcessingList;

  /// Unlocalize refs helper.
  final ChangeRefsToPubDev _unlocalizeRefs;

  /// Localize refs helper.
  final ChangeRefsToLocal _localizeRefs;

  /// Captures the original `publish_to` value so it can be restored on
  /// publish.
  final BackupPublishTo _backupPublishTo;

  /// Graph helper for determining nodes between endpoints.
  final Graph _graph;

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
        // We intentionally do not copy here; we copy after graph processing.
      ),
    );

    // Transitively clone missing dependency-refs (Git + Hosted-from-known-org)
    // into the master so the dependency graph contains every repo required to
    // compute "between" nodes. Without this, a chain like
    // "gg_1 -> gg_2 -> gg_3" with only gg_1+gg_3 requested would never
    // auto-add gg_2 if it was not already in master (the graph has no gg_2
    // node, so getNodesBetween returns []).
    await _cloneMissingTransitiveDeps(ggLog: ggLog);

    final ticketDir = Directory(ticketPath);

    // Build the dependency graph of the master workspace and compute
    // all nodes between the provided endpoints.
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

    // Determine endpoints for between-node calculation:
    // 1) endpoints from CLI arguments
    // 2) additional endpoints from repos already present in the ticket.
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
    final existingTicketRepos =
        ticketDir.listSync(recursive: false).whereType<Directory>();

    for (final repoDir in existingTicketRepos) {
      final repoName = path.basename(repoDir.path);
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
      ...betweenNodes.map((n) => n.name),
    };

    final GgLog taskLog = verbose ? ggLog : <String>[].add;

    ggLog(yellow('Copying the following repos:'));

    await _copyReposToTicket(
      ticketPath: ticketPath,
      repoNames: finalToCopy,
      ggLog: taskLog,
      reportLog: ggLog,
    );

    // Write project configuration files (workspace + git hooks +
    // .gitattributes). Must run before the relocalize/commit step, because
    // gg requires ".gitattributes" with "* text=auto eol=lf" to be present
    // before any "gg do commit" call.
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

  // ---------------------------------------------------------------------------
  // Ticket support helpers ----------------------------------------------------

  // ...........................................................................
  /// Walks the pubspec.yaml of every repo currently in [masterWorkspacePath]
  /// and clones any referenced dependency that is not yet present in master,
  /// as long as it can be attributed to a known organization (from
  /// `.organizations`):
  ///
  ///  - `GitDependency` (e.g. `dep: git: …github.com:ggsuite/dep.git`) is
  ///    cloned via [addRepositoryHelper] using its package name; the existing
  ///    org-fallback in the helper picks the right base URL.
  ///  - `HostedDependency` (pub.dev) is resolved by querying pub.dev for the
  ///    package's `repository` URL and is cloned only if that URL starts with
  ///    one of the known organization URLs. Hosted deps from external orgs
  ///    (`dart-lang`, `flutter`, …) are skipped silently.
  ///  - `PathDependency` and `SdkDependency` are ignored.
  ///
  /// Loops to a fixpoint so newly-cloned repos contribute their own
  /// dependencies to the next iteration. Clone failures are swallowed
  /// ([addRepositoryHelper] already logs them).
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

    // Cache pub.dev lookups across the fixpoint loop so we don't re-query the
    // same hosted dep on every iteration.
    final hostedLookupCache = <String, String?>{};

    while (true) {
      final existingRepos = masterDir
          .listSync(recursive: false)
          .whereType<Directory>()
          .map((d) => path.basename(d.path))
          .toSet();

      // Per-iteration plan: depName -> clone targetArg ("name" for git deps so
      // the helper's org-fallback resolves the URL, full URL for hosted deps).
      final plan = <String, String>{};

      for (final repoName in existingRepos) {
        final pubspecFile = File(
          path.join(masterWorkspacePath, repoName, 'pubspec.yaml'),
        );
        if (!pubspecFile.existsSync()) {
          continue;
        }
        Pubspec parsed;
        try {
          parsed = Pubspec.parse(pubspecFile.readAsStringSync());
        } catch (_) {
          continue; // skip unparseable pubspec
        }

        Future<void> scan(Map<String, Dependency> deps) async {
          for (final entry in deps.entries) {
            final depName = entry.key;
            if (existingRepos.contains(depName) || plan.containsKey(depName)) {
              continue;
            }
            final dep = entry.value;
            if (dep is GitDependency) {
              plan[depName] = depName; // helper falls back to org URLs
            } else if (dep is HostedDependency) {
              // Resolve repo URL via pub.dev once, then accept only if it
              // belongs to a known org.
              if (!hostedLookupCache.containsKey(depName)) {
                try {
                  hostedLookupCache[depName] =
                      await fetchDependencyRepoUrl(depName);
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

        await scan(parsed.dependencies);
        await scan(parsed.devDependencies);
      }

      if (plan.isEmpty) {
        return;
      }

      bool addedAny = false;
      for (final entry in plan.entries) {
        final depName = entry.key;
        final destDir = Directory(path.join(masterWorkspacePath, depName));
        if (destDir.existsSync()) {
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
          );
        } catch (_) {
          // Swallow: addRepositoryHelper already logged the failure.
        }
        if (destDir.existsSync()) {
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

  /// Copies all given [repoNames] from the master workspace into the
  /// ticket at [ticketPath].
  ///
  /// Runs up to [maxParallel] copy operations concurrently. Per-repo
  /// success/failure status lines are written to [reportLog]; verbose
  /// command output goes to [ggLog].
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
        reportLog(green('✅ $repoName'));
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
    final srcDir = Directory(path.join(masterWorkspacePath, repoName));
    if (!srcDir.existsSync()) {
      ggLog(red('Repository $repoName not found in master workspace.'));
      return;
    }

    final destDir = Directory(path.join(ticketPath, repoName));
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

    // Install dependencies (language-aware): `dart pub get` for Dart/Flutter
    // and manifest-less repos, `<pm> install` (npm/yarn/pnpm) for TypeScript.
    gg.ProjectType? projectType;
    try {
      projectType = gg.detectProjectType(destDir);
    } catch (_) {
      projectType = null;
    }

    final String executable;
    final List<String> args;
    if (projectType == gg.ProjectType.typescript) {
      executable = gg.detectTypeScriptPackageManager(destDir).executable;
      args = <String>['install'];
    } else {
      executable = 'dart';
      args = <String>['pub', 'get'];
    }

    final result = await processRunner(
      executable,
      args,
      workingDirectory: destDir.path,
      runInShell: true,
    );
    final cmd = '$executable ${args.join(' ')}';
    if (result.exitCode == 0) {
      ggLog(darkGray('Executed $cmd in $repoName.'));
    } else {
      ggLog(red('Failed to execute $cmd in $repoName: ${result.stderr}'));
    }

    ggLog(green('Added repository $repoName to ticket workspace.'));
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

  /// Deletes all local tags in [repoDir] in a portable way (no shell pipe).
  ///
  /// Uses `git tag -l` to list tags, then `git tag -d <tag1> <tag2> …` to
  /// delete them in a single call. The previous implementation relied on
  /// `git tag -l | xargs git tag -d`, which does not work on macOS because
  /// the pipe is not interpreted as a real shell pipe by Process.run.
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

  /// Performs two iterations over all repositories in the ticket in
  /// SortedProcessingList order:
  /// 1) Unlocalize
  /// 2) Localize with --git, set status to git-localized, commit
  ///    and execute "dart pub upgrade" if a pubspec.yaml exists.
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

    // Iteration 1: Unlocalize all ---------------------------------------------
    for (final node in nodes) {
      final repoDir = node.directory;
      final repoName = path.basename(repoDir.path);
      try {
        final backupFile =
            File('${repoDir.path}/.gg_localize_refs_backup.json');
        if (backupFile.existsSync()) {
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

      // Refresh dependencies for the detected project type after the
      // references were rewritten to local paths. Runs `dart pub upgrade`
      // for Dart/Flutter packages and the equivalent install command for
      // TypeScript packages (npm/yarn/pnpm). Repos without a recognizable
      // manifest are skipped.
      gg.ProjectType? projectType;
      try {
        projectType = gg.detectProjectType(repoDir);
      } catch (_) {
        projectType = null;
      }

      if (projectType != null) {
        final String executable;
        final List<String> args;
        if (projectType == gg.ProjectType.typescript) {
          executable = gg.detectTypeScriptPackageManager(repoDir).executable;
          args = <String>['install'];
        } else {
          executable = 'dart';
          args = <String>['pub', 'upgrade'];
        }

        final refresh = await processRunner(
          executable,
          args,
          workingDirectory: repoDir.path,
          runInShell: true,
        );
        final cmd = '$executable ${args.join(' ')}';
        if (refresh.exitCode == 0) {
          ggLog(darkGray('Executed $cmd in $repoName.'));
        } else {
          ggLog(red('Failed to execute $cmd in $repoName: ${refresh.stderr}'));
        }
      }

      // Commit changes per repository -----------------------------------------
      //
      // Pass `updateChangeLog: false` to avoid gg_changelog, which
      // unconditionally reads pubspec.yaml and therefore fails in
      // TypeScript repositories. This is a purely mechanical
      // "reference rewrite" commit and does not belong in the changelog.
      try {
        await _ggDoCommit.exec(
          directory: repoDir,
          ggLog: ggLog,
          message: 'gg_multi: changed references to path',
          force: true,
          updateChangeLog: false,
        );
      } catch (e) {
        ggLog(red('Failed to commit $repoName: $e'));
      }
    }

    ggLog('✅ Re-localized all repositories in ticket $ticketName.');
  }

  /// Rewrites the VS Code `.code-workspace` file for the given [ticketDir].
  ///
  /// The workspace file contains one folder entry for each repository in the
  /// ticket so that all repositories can be opened together in VS Code.
  Future<void> _rewriteCodeWorkspace({
    required Directory ticketDir,
    required GgLog ggLog,
  }) async {
    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    final folderNames = <String>{};

    for (final node in nodes) {
      final repoDir = node.directory;
      final name = path.basename(repoDir.path);
      folderNames.add(name);
    }

    final folders = folderNames
        .map<Map<String, String>>(
          (name) => <String, String>{'path': name},
        )
        .toList();

    final ticketName = path.basename(ticketDir.path);

    final workspaceFile = File(
      path.join(ticketDir.path, '$ticketName.code-workspace'),
    );

    final content = jsonEncode(
      <String, Object?>{
        'folders': folders,
      },
    );

    await workspaceFile.writeAsString('$content\n');
  }

  /// Writes all project configuration files that depend on the set of
  /// repositories in a ticket, such as the VS Code workspace and git hooks.
  Future<void> _writeProjectConfigFiles({
    required Directory ticketDir,
    required GgLog ggLog,
  }) async {
    await _rewriteCodeWorkspace(ticketDir: ticketDir, ggLog: ggLog);

    await DoInstallGitHooksCommand(
      ggLog: ggLog,
      sortedProcessingList: _sortedProcessingList,
    ).exec(
      directory: ticketDir,
      ggLog: ggLog,
    );

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
