// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;
import '../../backend/add_repository_helper.dart';
import '../../backend/constants.dart';
import '../../backend/repo_folder_resolver.dart';
import '../../backend/ticket_json.dart';

/// Factory for `Directory` instances — overridable in tests.
typedef DirectoryFactory = Directory Function(String path);

/// Deletes a repo from master (only if no ticket uses it) or from the
/// invoking ticket. From the workspace root, refuses to delete master if any
/// ticket still references the repo and lists the offending tickets. Inside a
/// ticket it refuses to delete a repo that links to other repos of the
/// ticket, because that would tear the dependency chain apart.
class RemoveCommand extends Command<void> {
  /// Constructor.
  RemoveCommand({
    required this.ggLog,
    String? rootPath,
    DirectoryFactory? directoryFactory,
    SortedProcessingList? sortedProcessingList,
    // coverage:ignore-start
  })  : rootPath = rootPath ?? Directory.current.path,
        directoryFactory = directoryFactory ?? Directory.new,
        // coverage:ignore-end
        _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog);

  // ...........................................................................
  @override
  String get name => 'rm';

  // ...........................................................................
  @override
  String get description =>
      'Delete a repo folder if only in master; otherwise list usage.';

  // ...........................................................................
  @override
  Future<void> run() async {
    if (argResults!.rest.isEmpty) {
      throw UsageException('Missing target parameter.', usage);
    }
    final targetArg = argResults!.rest.first;
    final repoName = extractRepoName(targetArg) ?? 'unknown_repo';

    if (_isTicketDirectory(rootPath)) {
      await _removeFromTicket(repoName);
      return;
    }
    _removeFromMasterIfUnused(repoName);
  }

  /// Log sink.
  final GgLog ggLog;

  /// Root directory to search for workspaces.
  final String rootPath;

  /// Factory used to materialize Directory handles (tests substitute it).
  final DirectoryFactory directoryFactory;

  /// Resolves the dependency graph of the repos of a ticket.
  final SortedProcessingList _sortedProcessingList;

  // ######################
  // Private
  // ######################

  // ...........................................................................

  // ...........................................................................
  /// Deletes the repo from the ticket the command was invoked in.
  Future<void> _removeFromTicket(String repoName) async {
    final resolved = RepoFolderResolver.resolve(
      workspacePath: rootPath,
      repoName: repoName,
    );
    final ticketRepoDir =
        resolved ?? directoryFactory(path.join(rootPath, repoName));
    if (!ticketRepoDir.existsSync()) {
      ggLog(
        red(
          'Repository $repoName is not part of ticket '
          '${path.basename(rootPath)}.',
        ),
      );
      return;
    }

    final nodes = await _sortedProcessingList.get(
      directory: directoryFactory(rootPath),
      ggLog: ggLog,
    );

    _throwIfLinkingOtherRepos(repoName, ticketRepoDir, nodes);

    ticketRepoDir.deleteSync(recursive: true);
    RepoFolderResolver.removeEmptyOrgFolder(
      workspacePath: rootPath,
      repoDir: ticketRepoDir,
    );
    ggLog(
      darkGray('Deleted repository ') +
          green(repoName) +
          darkGray(' from ticket ') +
          green(path.basename(rootPath)) +
          darkGray('.'),
    );

    _updateTicketJson(ticketRepoDir, nodes);
  }

  // ...........................................................................
  /// Throws when the repo sits between two other repos of the ticket, i.e.
  /// when another ticket repo depends on it while it itself depends on a
  /// further ticket repo. Deleting it would break that chain.
  void _throwIfLinkingOtherRepos(
    String repoName,
    Directory ticketRepoDir,
    List<Node> nodes,
  ) {
    final target = nodes.where(
      (node) =>
          path.equals(node.directory.path, ticketRepoDir.path) ||
          node.aliases.contains(repoName),
    );
    if (target.isEmpty) {
      return; // The repo is no package — nothing can depend on it.
    }

    final node = target.first;
    final dependents = node.dependents.keys.toList()..sort();
    final dependencies = node.dependencies.keys.toList()..sort();
    if (dependents.isEmpty || dependencies.isEmpty) {
      return;
    }

    ggLog(
      red(
        'Repository $repoName connects other repos of ticket '
        '${path.basename(rootPath)}:',
      ),
    );
    for (final dependent in dependents) {
      ggLog(' - $dependent depends on $repoName');
    }
    for (final dependency in dependencies) {
      ggLog(' - $repoName depends on $dependency');
    }
    ggLog(
      red(
        'Please remove ${dependents.join(', ')} first.',
      ),
    );

    throw Exception(
      'Cannot remove $repoName: it sits between '
      '${dependents.join(', ')} and ${dependencies.join(', ')}.',
    );
  }

  // ...........................................................................
  /// Rewrites the `.gg/ticket.json` marker of the repos that remain in the
  /// ticket so the deleted repo no longer shows up in their repository list.
  ///
  /// Only repos that already carry a marker are updated — a ticket that never
  /// saw a `do add` does not gain one here. The marker is written but not
  /// staged or committed; the next `do add` / `do commit` picks it up.
  void _updateTicketJson(Directory removedRepoDir, List<Node> nodes) {
    final remaining = [
      for (final node in nodes)
        if (!path.equals(node.directory.path, removedRepoDir.path))
          node.directory,
    ];

    // A repo checked out before the files inside `.gg` were unhidden still
    // carries the marker under its old name — it counts as "has a marker",
    // and writeTicketJsonToRepos then writes the current one next to it.
    final withMarker = [
      for (final dir in remaining)
        if (File(path.join(dir.path, ticketJsonRelativePath)).existsSync() ||
            File(
              path.join(dir.path, legacyTicketJsonRelativePath),
            ).existsSync())
          dir,
    ];
    if (withMarker.isEmpty) {
      return;
    }

    writeTicketJsonToRepos(
      repoDirs: withMarker,
      ticket: buildTicketJson(
        ticketDir: directoryFactory(rootPath),
        repoDirs: remaining,
      ),
    );
    ggLog(
      green(
        'Removed ${path.basename(removedRepoDir.path)} from '
        '$ticketJsonRelativePath of ${withMarker.length} repo(s).',
      ),
    );
  }

  // ...........................................................................
  /// Scans tickets, deletes the master copy iff none reference the repo.
  void _removeFromMasterIfUnused(String repoName) {
    final ticketsContainingRepo = _ticketsReferencing(repoName);
    final resolved = RepoFolderResolver.resolve(
      workspacePath: path.join(rootPath, ggMultiMasterFolder),
      repoName: repoName,
    );
    final masterRepoDir = resolved ??
        directoryFactory(
          path.join(rootPath, ggMultiMasterFolder, repoName),
        );
    final existsInMaster = masterRepoDir.existsSync();

    if (ticketsContainingRepo.isEmpty && !existsInMaster) {
      ggLog(red('Repository $repoName not found in any workspace.'));
      return;
    }

    if (ticketsContainingRepo.isEmpty) {
      masterRepoDir.deleteSync(recursive: true);
      RepoFolderResolver.removeEmptyOrgFolder(
        workspacePath: path.join(rootPath, ggMultiMasterFolder),
        repoDir: masterRepoDir,
      );
      ggLog(green('Deleted repository $repoName from master workspace.'));
      return;
    }

    ggLog('Repository $repoName is used by the following tickets:');
    for (final ticket in ticketsContainingRepo) {
      ggLog(' - $ticket');
    }
    ggLog(
      red(
        'Please remove it from those tickets first '
        '(or run `gg multi do rm $repoName` from inside the ticket).',
      ),
    );
  }

  // ...........................................................................
  /// Returns the names of all tickets that still hold a copy of [repoName].
  List<String> _ticketsReferencing(String repoName) {
    final ticketsRoot = Directory(path.join(rootPath, ggMultiTicketFolder));
    if (!ticketsRoot.existsSync()) return const <String>[];
    return [
      for (final ticket in ticketsRoot.listSync().whereType<Directory>())
        if (RepoFolderResolver.resolve(
              workspacePath: ticket.path,
              repoName: repoName,
            ) !=
            null)
          path.basename(ticket.path),
    ];
  }

  // ...........................................................................
  /// True when [dirPath]'s parent is `tickets/`.
  bool _isTicketDirectory(String dirPath) {
    return path.basename(path.dirname(dirPath)) == ggMultiTicketFolder;
  }
}
