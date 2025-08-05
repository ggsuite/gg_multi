// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

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
        _localizeRefs = localizeRefs ?? LocalizeRefs(ggLog: ggLog)
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

  /// gg do commit instance used after localization with --git in ticket copies.
  final gg.DoCommit _ggDoCommit;

  /// Sorted processing helper for ticket-wide iteration.
  final SortedProcessingList _sortedProcessingList;

  /// Unlocalize refs helper.
  final UnlocalizeRefs _unlocalizeRefs;

  /// Localize refs helper.
  final LocalizeRefs _localizeRefs;

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
    for (final targetArg in targets) {
      await addRepositoryHelper(
        targetArg: targetArg,
        ggLog: ggLog,
        gitCloner: gitCloner,
        gitHubPlatform: gitHubPlatform,
        workspacePath: masterWorkspacePath,
        force: force,
        logIfAlreadyAdded: ticketPath == null,
        onRepoAdded: ticketPath == null
            ? null
            : (String repoName) async {
                await _addRepoToTicket(
                  repoName: repoName,
                  ticketPath: ticketPath,
                );
              },
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Ticket support helpers ----------------------------------------------------

  /// Copies the repository from the master workspace to the [ticketPath]. If
  /// the repository already exists in the ticket workspace, nothing happens.
  /// Afterwards perform a two-pass re-localization on ALL repos inside the
  /// ticket in sorted processing order.
  Future<void> _addRepoToTicket({
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

    // Copy from master into ticket --------------------------------------------
    await copyDirectory(srcDir, destDir);

    final String ticketName = path.basename(ticketPath);

    // Checkout a branch named as the ticket -----------------------------------
    try {
      await gitCloner.checkoutBranch(ticketName, destDir.path);
    } catch (e) {
      ggLog(red('Failed to checkout branch $ticketName: $e'));
    }

    // Run dart pub get in the repo --------------------------------------------
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
          'Failed to execute dart pub get in $repoName: ${result.stderr}',
        ),
      );
    }

    ggLog(green('Added repository $repoName to ticket workspace.'));

    // Ticket-wide two-pass re-localization ------------------------------------
    await _relocalizeAllReposInTicket(Directory(ticketPath));
  }

  /// Performs two iterations over all repositories in the ticket in
  /// SortedProcessingList order:
  /// 1) Unlocalize
  /// 2) Localize with --git, set status to git-localized, commit
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
        await _unlocalizeRefs.get(directory: repoDir, ggLog: ggLog);
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

      // Commit changes per repository -----------------------------------------
      try {
        await _ggDoCommit.exec(
          directory: repoDir,
          ggLog: ggLog,
          message: 'kidney: changed references to git',
        );
      } catch (e) {
        ggLog(red('Failed to commit $repoName: $e'));
        throw Exception('Failed to relocalize ticket $ticketName');
      }
    }

    ggLog(green('✅ Re-localized all repositories in ticket $ticketName.'));
  }
}
