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
import '../../backend/dependency_overrides.dart';
import '../../backend/repo_folder_resolver.dart';
import '../../backend/ticket_json.dart';
import '../../backend/workspace_utils.dart';

/// Factory for `Directory` instances — overridable in tests.
typedef DirectoryFactory = Directory Function(String path);

/// Deletes a repo from ocean (only if no ticket uses it) or from the
/// invoking ticket. From the workspace root, refuses to delete ocean if any
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
  String get description => 'Delete a repo folder from ocean or ticket';

  // ...........................................................................
  @override
  Future<void> run() async {
    if (argResults!.rest.isEmpty) {
      throw UsageException('Missing target parameter.', usage);
    }
    final targetArg = argResults!.rest.first;
    final repoName = extractRepoName(targetArg) ?? 'unknown_repo';

    final ticketPath = WorkspaceUtils.detectTicketPath(rootPath);
    if (ticketPath != null) {
      _root = ticketPath;
      await _removeFromTicket(repoName);
      return;
    }

    _root = WorkspaceUtils.defaultGgMultiWorkspacePath(workingDir: rootPath);
    _removeFromOceanIfUnused(repoName);
  }

  /// Log sink.
  final GgLog ggLog;

  /// Directory the command was invoked in.
  final String rootPath;

  /// The workspace [rootPath] belongs to: the ticket directory when invoked
  /// inside a ticket, the Gg Multi workspace root otherwise. Resolved in
  /// [run], so the command also works from any sub-folder.
  late final String _root;

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
      workspacePath: _root,
      repoName: repoName,
    );
    final ticketRepoDir =
        resolved ?? directoryFactory(path.join(_root, repoName));
    if (!ticketRepoDir.existsSync()) {
      ggLog(
        cError(
          'Repository $repoName is not part of ticket '
          '${path.basename(_root)}.',
        ),
      );
      return;
    }

    final nodes = await _sortedProcessingList.get(
      directory: directoryFactory(_root),
      ggLog: ggLog,
    );

    _throwIfLinkingOtherRepos(repoName, ticketRepoDir, nodes);

    // Collect the names the repo is referenced by *before* it is gone — the
    // manifest that carries them is deleted with it.
    final removedNames = _packageNamesOf(repoName, ticketRepoDir, nodes);

    ticketRepoDir.deleteSync(recursive: true);
    RepoFolderResolver.removeEmptyOrgFolder(
      workspacePath: _root,
      repoDir: ticketRepoDir,
    );
    ggLog(
      darkGray('✓ Deleted repository ') +
          cCmd(repoName) +
          darkGray(' from ticket ') +
          cCmd(path.basename(_root)) +
          darkGray('.'),
    );

    _updateTicketJson(ticketRepoDir, nodes);
    _removeDependencyOverrides(ticketRepoDir, nodes, removedNames);
  }

  // ...........................................................................
  /// All names the removed repo can appear under in another repo's
  /// `dependency_overrides`: the folder name, the name it was addressed with,
  /// and the package name(s) the dependency graph knows it by.
  Set<String> _packageNamesOf(
    String repoName,
    Directory ticketRepoDir,
    List<Node> nodes,
  ) {
    final names = <String>{repoName, path.basename(ticketRepoDir.path)};
    for (final node in nodes) {
      if (path.equals(node.directory.path, ticketRepoDir.path)) {
        names.add(node.name);
        names.addAll(node.aliases);
      }
    }
    return names;
  }

  // ...........................................................................
  /// Drops the removed repo from the `pubspec_overrides.yaml` of the repos
  /// that stay in the ticket.
  ///
  /// Those overrides point at the sibling checkout (`path: ../<repo>`) that
  /// just disappeared, so leaving them would break `dart pub get` in every
  /// remaining repo.
  void _removeDependencyOverrides(
    Directory removedRepoDir,
    List<Node> nodes,
    Set<String> removedNames,
  ) {
    final remaining = [
      for (final node in nodes)
        if (!path.equals(node.directory.path, removedRepoDir.path))
          node.directory,
    ];

    final changed = removeDependencyOverrides(
      repoDirs: remaining,
      packageNames: removedNames,
    );
    if (changed.isEmpty) {
      return;
    }

    ggLog(
      cDetail(
        '✓ Removed ${path.basename(removedRepoDir.path)} from '
        '$pubspecOverridesFileName of ${changed.length} repo(s).',
      ),
    );
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
      cError(
        'Repository $repoName connects other repos of ticket '
        '${path.basename(_root)}:',
      ),
    );
    for (final dependent in dependents) {
      ggLog(' - $dependent depends on $repoName');
    }
    for (final dependency in dependencies) {
      ggLog(' - $repoName depends on $dependency');
    }
    ggLog(
      cError(
        'Please remove ${dependents.join(', ')} first.',
      ),
    );

    throw Exception(
      cError(
        'Cannot remove $repoName: it sits between '
        '${dependents.join(', ')} and ${dependencies.join(', ')}.',
      ),
    );
  }

  // ...........................................................................
  /// Rewrites the ticket's `ticket.json` so the deleted repo no longer shows
  /// up in its repository list.
  ///
  /// Only a ticket that already has a `ticket.json` is updated — one that never
  /// saw a `do add` does not gain one here.
  void _updateTicketJson(Directory removedRepoDir, List<Node> nodes) {
    final ticketDir = directoryFactory(_root);
    if (!File(path.join(ticketDir.path, ticketJsonFileName)).existsSync()) {
      return;
    }

    final remaining = [
      for (final node in nodes)
        if (!path.equals(node.directory.path, removedRepoDir.path))
          node.directory,
    ];

    writeTicketJson(
      ticketDir,
      buildTicketJson(ticketDir: ticketDir, repoDirs: remaining),
    );
    ggLog(
      cDetail(
        '✓ Removed ${path.basename(removedRepoDir.path)} from '
        '$ticketJsonFileName.',
      ),
    );
  }

  // ...........................................................................
  /// Scans tickets, deletes the ocean copy iff none reference the repo.
  void _removeFromOceanIfUnused(String repoName) {
    final ticketsContainingRepo = _ticketsReferencing(repoName);
    final resolved = RepoFolderResolver.resolve(
      workspacePath: path.join(_root, ggMultiOceanFolder),
      repoName: repoName,
    );
    final oceanRepoDir = resolved ??
        directoryFactory(
          path.join(_root, ggMultiOceanFolder, repoName),
        );
    final existsInMaster = oceanRepoDir.existsSync();

    if (ticketsContainingRepo.isEmpty && !existsInMaster) {
      ggLog(cError('Repository $repoName not found in any workspace.'));
      return;
    }

    if (ticketsContainingRepo.isEmpty) {
      oceanRepoDir.deleteSync(recursive: true);
      RepoFolderResolver.removeEmptyOrgFolder(
        workspacePath: path.join(_root, ggMultiOceanFolder),
        repoDir: oceanRepoDir,
      );
      ggLog(cDetail('✓ Deleted repository $repoName from ocean.'));
      return;
    }

    ggLog('Repository $repoName is used by the following tickets:');
    for (final ticket in ticketsContainingRepo) {
      ggLog(' - $ticket');
    }
    ggLog(
      cError(
        'Please remove it from those tickets first '
        '(or run `gg multi do rm $repoName` from inside the ticket).',
      ),
    );
  }

  // ...........................................................................
  /// Returns the names of all tickets that still hold a copy of [repoName].
  List<String> _ticketsReferencing(String repoName) {
    final ticketsRoot = Directory(path.join(_root, ggMultiTicketFolder));
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
}
