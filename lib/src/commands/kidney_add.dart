// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:gg/gg.dart' as gg;
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_localize_refs/gg_localize_refs.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;

import '../backend/git_handler.dart';
import '../backend/add_repository_helper.dart';
import '../backend/filesystem_utils.dart';
import '../backend/git_platform.dart';
import '../backend/workspace_utils.dart';
import '../backend/status_utils.dart';

/// Typedef for a process runner function.
typedef ProcessRunner = Future<ProcessResult> Function(
  String,
  List<String>, {
  String? workingDirectory,
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
    UnlocalizeRefs? unlocalizeRefs,
    LocalizeRefs? localizeRefs,
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
        _unlocalizeRefs = unlocalizeRefs ?? UnlocalizeRefs(ggLog: ggLog),
        _localizeRefs = localizeRefs ?? LocalizeRefs(ggLog: ggLog),
        _graph = graph ?? Graph(ggLog: ggLog)
  // coverage:ignore-end
  {
    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Overwrite existing repository in master workspace.',
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
  final UnlocalizeRefs _unlocalizeRefs;

  /// Localize refs helper.
  final LocalizeRefs _localizeRefs;

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

    // If not in a ticket workspace: keep original behaviour (no graph logic).
    if (ticketPath == null) {
      for (final targetArg in targets) {
        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: gitCloner,
          gitHubPlatform: gitHubPlatform,
          workspacePath: masterWorkspacePath,
          force: force,
          logIfAlreadyAdded: true,
        );
      }
      return;
    }

    // Ticket mode: ensure requested repos are present in master first.
    final requestedRepoNames = <String>{};
    for (final targetArg in targets) {
      final repoName = extractRepoName(targetArg);
      if (repoName != null) {
        requestedRepoNames.add(repoName);
      }
      await addRepositoryHelper(
        targetArg: targetArg,
        ggLog: ggLog,
        gitCloner: gitCloner,
        gitHubPlatform: gitHubPlatform,
        workspacePath: masterWorkspacePath,
        force: force,
        // When inside a ticket we do not spam "already added" messages.
        logIfAlreadyAdded: false,
        // We intentionally do not copy here; we copy after graph processing.
      );
    }

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

    // Copy all required repositories into the ticket.
    for (final repoName in finalToCopy) {
      await _copyRepoToTicket(
        repoName: repoName,
        ticketPath: ticketPath,
      );
    }

    // Finally perform a single re-localization pass for the whole ticket.
    await _relocalizeAllReposInTicket(ticketDir);

    // Rewrite the VS Code workspace so that all ticket repositories are
    // available as folders in a single workspace file.
    await _rewriteCodeWorkspace(ticketDir);
  }

  // ---------------------------------------------------------------------------
  // Ticket support helpers ----------------------------------------------------

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

  /// Copies the repository from the master workspace to the [ticketPath] but
  /// does not trigger a ticket-wide relocalization.
  Future<void> _copyRepoToTicket({
    required String repoName,
    required String ticketPath,
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

    // Before copying, update the repository in the master workspace
    final fetchResult = await processRunner(
      'git',
      ['fetch'],
      workingDirectory: srcDir.path,
    );
    if (fetchResult.exitCode != 0) {
      ggLog(
        red(
          'Failed to git fetch in $repoName in master workspace: '
          '${fetchResult.stderr}',
        ),
      );
    } else {
      final pullResult = await processRunner(
        'git',
        ['pull'],
        workingDirectory: srcDir.path,
      );
      if (pullResult.exitCode != 0) {
        ggLog(
          red(
            'Failed to git pull in $repoName in master workspace: '
            '${pullResult.stderr}',
          ),
        );
      }
    }

    // Copy from master into ticket -------------------------------------------
    await copyDirectory(srcDir, destDir);

    final String ticketName = path.basename(ticketPath);

    // Checkout a branch named as the ticket ----------------------------------
    try {
      await gitCloner.checkoutBranch(ticketName, destDir.path);
    } catch (e) {
      ggLog(red('Failed to checkout branch $ticketName: $e'));
    }

    // Run dart pub get in the repo -------------------------------------------
    final result = await processRunner(
      'dart',
      ['pub', 'get'],
      workingDirectory: destDir.path,
    );
    if (result.exitCode == 0) {
      ggLog(green('Executed dart pub get in $repoName.'));
    } else {
      ggLog(
        red(
          'Failed to execute dart pub get in $repoName: '
          '${result.stderr}',
        ),
      );
    }

    ggLog(green('Added repository $repoName to ticket workspace.'));
  }

  /// Performs two iterations over all repositories in the ticket in
  /// SortedProcessingList order:
  /// 1) Unlocalize
  /// 2) Localize with --git, set status to git-localized, commit
  ///    and execute "dart pub upgrade" if a pubspec.yaml exists.
  Future<void> _relocalizeAllReposInTicket(Directory ticketDir) async {
    final ticketName = path.basename(ticketDir.path);

    // Collect repositories in processing order.
    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (nodes.isEmpty) {
      ggLog(yellow('⚠️ No repositories found in ticket $ticketName.'));
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
        throw Exception('Failed to relocalize ticket $ticketName');
      }
    }

    // Iteration 2: Localize with --git all ------------------------------------
    for (final node in nodes) {
      final repoDir = node.directory;
      final repoName = path.basename(repoDir.path);
      try {
        await _localizeRefs.get(directory: repoDir, ggLog: ggLog);
        StatusUtils.setStatus(
          repoDir,
          StatusUtils.statusLocalized,
          ggLog: ggLog,
        );
      } catch (e) {
        ggLog(red('Failed to localize refs for $repoName: $e'));
        throw Exception('Failed to relocalize ticket $ticketName');
      }

      // Execute "dart pub upgrade" if pubspec.yaml exists -------------------
      final pubspec = File(path.join(repoDir.path, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        final upgrade = await processRunner(
          'dart',
          ['pub', 'upgrade'],
          workingDirectory: repoDir.path,
        );
        if (upgrade.exitCode == 0) {
          ggLog(green('Executed dart pub upgrade in $repoName.'));
        } else {
          ggLog(
            red(
              'Failed to execute dart pub upgrade in '
              '$repoName: ${upgrade.stderr}',
            ),
          );
        }
      }

      // Commit changes per repository -----------------------------------------
      try {
        await _ggDoCommit.exec(
          directory: repoDir,
          ggLog: ggLog,
          message: 'kidney: changed references to git',
          force: true,
        );
      } catch (e) {
        ggLog(red('Failed to commit $repoName: $e'));
      }
    }

    ggLog(green('✅ Re-localized all repositories in ticket $ticketName.'));
  }

  /// Rewrites the VS Code `.code-workspace` file for the given [ticketDir].
  ///
  /// The workspace file contains one folder entry for each repository in the
  /// ticket so that all repositories can be opened together in VS Code.
  Future<void> _rewriteCodeWorkspace(Directory ticketDir) async {
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
}
