// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_git/gg_git.dart' as gg_git;
import 'package:gg_log/gg_log.dart';
import 'package:interact/interact.dart';
import 'package:path/path.dart' as path;

import '../../backend/constants.dart';
import '../../backend/filesystem_utils.dart';
import '../../backend/git_handler.dart' hide ProcessRunner;
import '../../backend/repo_folder_resolver.dart';
import '../../backend/repo_setup.dart';
import '../../backend/ticket_json.dart';
import '../../backend/workspace_migration.dart';
import '../../backend/workspace_utils.dart';

/// Lets the user pick one branch from [branches]; returns null on cancel.
typedef BranchSelector = Future<String?> Function(List<String> branches);

/// Copies a directory tree; injectable for tests.
typedef CopyDirectory = Future<void> Function(Directory src, Directory dest);

/// Reproduces a whole ticket from a single `.gg/ticket.json` marker.
///
/// `gg multi do checkout <X>` resolves [X] in three modes:
/// * executed inside a `.master` repo → [X] is the ticket name, read from that
///   repo's branch;
/// * [X] is a known `.master` repo → interactive branch selection in that repo;
/// * otherwise [X] is a ticket name → searched across all `.master` repos.
///
/// Once a `.ticket.json` is found it is used to recreate the ticket workspace,
/// clone any missing repositories, and check out the existing feature branch in
/// every repository (with its already path-localized deps), so a ticket created
/// elsewhere is reproduced. Unlike a fresh `do add` it does not re-install git
/// hooks or `.gitattributes`.
class DoCheckoutCommand extends Command<dynamic> {
  /// Constructor.
  DoCheckoutCommand({
    required this.ggLog,
    GitHandler? gitHandler,
    gg_git.Fetch? fetch,
    gg_git.Checkout? checkout,
    gg_git.ShowFile? showFile,
    gg_git.RemoteBranches? remoteBranches,
    gg_git.RemoteBranchExists? remoteBranchExists,
    String? masterWorkspacePath,
    String? executionPath,
    ProcessRunner? processRunner,
    BranchSelector? selectBranch,
    CopyDirectory? copyDir,
    // coverage:ignore-start
  })  : gitHandler = gitHandler ?? GitHandler(),
        _fetch = fetch ?? gg_git.Fetch(ggLog: ggLog),
        _checkout = checkout ?? gg_git.Checkout(ggLog: ggLog),
        _showFile = showFile ?? gg_git.ShowFile(ggLog: ggLog),
        _remoteBranches = remoteBranches ?? gg_git.RemoteBranches(ggLog: ggLog),
        _remoteBranchExists =
            remoteBranchExists ?? gg_git.RemoteBranchExists(ggLog: ggLog),
        masterWorkspacePath =
            masterWorkspacePath ?? WorkspaceUtils.defaultMasterWorkspacePath(),
        executionPath = executionPath ?? Directory.current.path,
        processRunner = processRunner ?? Process.run,
        _selectBranch = selectBranch ?? _defaultSelectBranch,
        _copyDir = copyDir ?? copyDirectory;
  // coverage:ignore-end

  /// The log function.
  final GgLog ggLog;

  /// Clones repositories that are missing from the master workspace.
  final GitHandler gitHandler;

  final gg_git.Fetch _fetch;
  final gg_git.Checkout _checkout;
  final gg_git.ShowFile _showFile;
  final gg_git.RemoteBranches _remoteBranches;
  final gg_git.RemoteBranchExists _remoteBranchExists;

  /// Resolved master workspace path.
  final String masterWorkspacePath;

  /// The path from which the command was executed.
  final String executionPath;

  /// Runs `dart pub get` / `<pm> install` after checkout.
  final ProcessRunner processRunner;

  final BranchSelector _selectBranch;
  final CopyDirectory _copyDir;

  @override
  String get name => 'checkout';

  @override
  String get description =>
      'Reproduces a ticket from its .gg/ticket.json marker by checking out '
      'the feature branch in every repository of the ticket.';

  // coverage:ignore-start
  static Future<String?> _defaultSelectBranch(List<String> branches) async {
    final index = Select(
      prompt: 'Select a ticket branch',
      options: branches,
    ).interact();
    return branches[index];
  }
  // coverage:ignore-end

  @override
  Future<void> run() async {
    if (argResults!.rest.isEmpty) {
      throw UsageException('Missing ticket or repository name.', usage);
    }
    final arg = argResults!.rest.first;

    // Maintenance: move the repositories of an old master workspace into
    // their organization folders before resolving anything.
    migrateToOrgFolders(workspacePath: masterWorkspacePath, ggLog: ggLog);

    // Mode 1: executed inside a master repo → arg is the ticket name.
    final currentRepo = _currentMasterRepoPath();
    if (currentRepo != null) {
      await _reproduceFromBranch(
        repoPath: currentRepo,
        branch: arg,
        alreadyFetched: false,
      );
      return;
    }

    // Mode 2: arg is a known master repo → interactive branch selection.
    final repoDir = RepoFolderResolver.resolve(
      workspacePath: masterWorkspacePath,
      repoName: arg,
    );
    if (repoDir != null) {
      await _handleRepoMode(repoDir);
      return;
    }

    // Mode 3: arg is a ticket name → search all master repos for the branch.
    for (final repo in _listMasterRepos()) {
      try {
        await _fetch.get(directory: repo, ggLog: ggLog);
      } catch (e) {
        ggLog(red('Failed to fetch ${path.basename(repo.path)}: $e'));
        continue;
      }
      final exists = await _remoteBranchExists.get(
        directory: repo,
        ggLog: ggLog,
        branch: arg,
      );
      if (exists) {
        await _reproduceFromBranch(
          repoPath: repo.path,
          branch: arg,
          alreadyFetched: true,
        );
        return;
      }
    }

    throw Exception(
      'No repository in the master workspace has a branch "$arg".',
    );
  }

  // ...........................................................................
  /// Fetches [repoDir], lists its remote ticket branches and lets the user pick
  /// one to reproduce.
  Future<void> _handleRepoMode(Directory repoDir) async {
    await _fetch.get(directory: repoDir, ggLog: ggLog);
    final all = await _remoteBranches.get(directory: repoDir, ggLog: ggLog);
    final branches = all.where((b) => b != 'main' && b != 'master').toList();
    if (branches.isEmpty) {
      ggLog(
        yellow('No ticket branches found in ${path.basename(repoDir.path)}.'),
      );
      return;
    }
    final selected = await _selectBranch(branches);
    if (selected == null || selected.isEmpty) {
      return;
    }
    await _reproduceFromBranch(
      repoPath: repoDir.path,
      branch: selected,
      alreadyFetched: true,
    );
  }

  // ...........................................................................
  /// Reads the `.ticket.json` marker from `origin/<branch>` of [repoPath] and
  /// reproduces the ticket it describes.
  Future<void> _reproduceFromBranch({
    required String repoPath,
    required String branch,
    required bool alreadyFetched,
  }) async {
    final dir = Directory(repoPath);
    if (!alreadyFetched) {
      await _fetch.get(directory: dir, ggLog: ggLog);
    }
    // A branch pushed before the files inside `.gg` were unhidden carries the
    // marker under its old, hidden name — it still describes a valid ticket.
    var content = await _showFile.get(
      directory: dir,
      ggLog: ggLog,
      ref: 'origin/$branch',
      filePath: ticketJsonRelativePath,
    );
    content ??= await _showFile.get(
      directory: dir,
      ggLog: ggLog,
      ref: 'origin/$branch',
      filePath: legacyTicketJsonRelativePath,
    );
    if (content == null) {
      throw Exception(
        'Could not read $ticketJsonRelativePath from "origin/$branch" — '
        'the branch may not be pushed/fetched, or has no marker.',
      );
    }
    final TicketJson ticket;
    try {
      ticket = TicketJson.fromJsonString(content);
    } on FormatException catch (e) {
      throw Exception('Invalid $ticketJsonRelativePath on "$branch": $e');
    }
    await _reproduce(ticket);
  }

  // ...........................................................................
  /// Recreates the ticket workspace and all its repositories on the feature
  /// branch.
  Future<void> _reproduce(TicketJson ticket) async {
    final ticketName = ticket.issueId;
    if (ticketName.isEmpty) {
      throw Exception('The ticket marker has no issue_id.');
    }

    final root = path.dirname(masterWorkspacePath);
    final ticketDir = Directory(
      path.join(root, ggMultiTicketFolder, ticketName),
    );
    if (!ticketDir.existsSync()) {
      ticketDir.createSync(recursive: true);
    }
    writeRootTicket(
      ticketDir,
      issueId: ticket.issueId,
      description: ticket.description,
    );

    final succeeded = <String>[];
    final failed = <String>[];
    for (final repo in ticket.repositories) {
      final masterRepoDir = await _ensureMasterRepo(repo);
      if (masterRepoDir == null) {
        ggLog(red('Could not obtain repository ${repo.name}; skipping.'));
        failed.add(repo.name);
        continue;
      }
      final repoPath = await _setupTicketRepo(
        ticketDir: ticketDir,
        masterRepoDir: masterRepoDir,
        branch: ticketName,
        repoName: repo.name,
      );
      if (repoPath == null) {
        failed.add(repo.name);
      } else {
        succeeded.add(repoPath);
      }
    }

    // The workspace lists only the repos that were actually checked out.
    writeCodeWorkspaceFile(ticketDir, succeeded);

    final relPath = path.relative(ticketDir.path, from: executionPath);
    if (failed.isEmpty) {
      ggLog(green('✅ Checked out ticket $ticketName'));
    } else {
      ggLog(
        red(
          '⚠️ Checked out ticket $ticketName, but ${failed.length} repo(s) '
          'failed: ${failed.join(', ')}',
        ),
      );
    }
    ggLog(yellow('Enter the ticket workspace with:'));
    ggLog(blue('cd $relPath'));
  }

  // ...........................................................................
  /// Returns the master repository at [repo] (cloning it from its URL when it
  /// is missing), or null when it cannot be obtained.
  Future<Directory?> _ensureMasterRepo(TicketRepo repo) async {
    final existing = RepoFolderResolver.resolve(
      workspacePath: masterWorkspacePath,
      repoName: repo.name,
    );
    if (existing != null) {
      return existing;
    }
    if (repo.url.isEmpty) {
      return null;
    }
    final target = RepoFolderResolver.destination(
      workspacePath: masterWorkspacePath,
      repoUrl: repo.url,
      repoName: repo.name,
    );
    try {
      await gitHandler.cloneRepo(repo.url, target);
    } catch (e) {
      ggLog(red('Failed to clone ${repo.name} from ${repo.url}: $e'));
      return null;
    }
    return Directory(target);
  }

  // ...........................................................................
  /// Copies [masterRepoDir] into the ticket (when not already present) and
  /// checks out the existing feature [branch] there, then installs deps.
  /// Returns the path of the repo relative to the ticket root, or null when
  /// the branch could not be checked out.
  Future<String?> _setupTicketRepo({
    required Directory ticketDir,
    required Directory masterRepoDir,
    required String branch,
    required String repoName,
  }) async {
    // The ticket mirrors the layout of the master workspace, so the repo ends
    // up in the organization folder it has there.
    final relativePath = RepoFolderResolver.relativePath(
      workspacePath: masterWorkspacePath,
      repoDir: masterRepoDir,
    );
    final destDir = Directory(path.join(ticketDir.path, relativePath));

    if (!(destDir.existsSync() && destDir.listSync().isNotEmpty)) {
      // Fetch the master clone so its `origin/<branch>` is available in the
      // copy, then copy it into the ticket.
      await _fetch.get(directory: masterRepoDir, ggLog: ggLog);
      await _copyDir(masterRepoDir, destDir);
    }

    try {
      await _checkout.get(directory: destDir, ggLog: ggLog, branch: branch);
    } catch (e) {
      ggLog(red('Failed to checkout $branch in $repoName: $e'));
      return null;
    }

    await installRepoDependencies(
      dir: destDir,
      repoName: repoName,
      ggLog: ggLog,
      processRunner: processRunner,
    );
    ggLog(blue('Added $repoName on branch $branch.'));
    return relativePath;
  }

  // ...........................................................................
  /// Returns the path of the `.master` repository that contains
  /// [executionPath], or null when the command is not run inside one.
  ///
  /// The repository is either a direct child of the master workspace or sits
  /// one level deeper inside its organization folder, so the first two
  /// segments below the workspace are checked.
  String? _currentMasterRepoPath() {
    final master = path.normalize(masterWorkspacePath);
    final exec = path.normalize(executionPath);
    if (exec == master || !path.isWithin(master, exec)) {
      return null;
    }
    final segments = path.split(path.relative(exec, from: master));
    var repoPath = path.join(master, segments.first);
    if (!Directory(repoPath).existsSync()) {
      return null;
    }
    if (RepoFolderResolver.isOrgFolder(Directory(repoPath))) {
      if (segments.length < 2) {
        return null;
      }
      repoPath = path.join(repoPath, segments[1]);
      if (!Directory(repoPath).existsSync()) {
        return null;
      }
    }
    return repoPath;
  }

  // ...........................................................................
  /// Lists the git repositories of the master workspace.
  List<Directory> _listMasterRepos() {
    return RepoFolderResolver.repoDirs(masterWorkspacePath)
        .where((d) => Directory(path.join(d.path, '.git')).existsSync())
        .toList();
  }
}
