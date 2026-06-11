// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;
import '../../backend/add_repository_helper.dart';
import '../../backend/constants.dart';
import '../../backend/repo_folder_resolver.dart';

/// Factory for `Directory` instances — overridable in tests.
typedef DirectoryFactory = Directory Function(String path);

/// Deletes a repo from master (only if no ticket uses it) or from the
/// invoking ticket. From the workspace root, refuses to delete master if any
/// ticket still references the repo and lists the offending tickets.
class RemoveCommand extends Command<void> {
  /// Constructor.
  RemoveCommand({
    required this.ggLog,
    String? rootPath,
    DirectoryFactory? directoryFactory,
    // coverage:ignore-start
  })  : rootPath = rootPath ?? Directory.current.path,
        directoryFactory = directoryFactory ?? Directory.new;
  // coverage:ignore-end

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
      _removeFromTicket(repoName);
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

  // ######################
  // Private
  // ######################

  // ...........................................................................

  // ...........................................................................
  /// Deletes the repo from the ticket the command was invoked in.
  void _removeFromTicket(String repoName) {
    final resolved = RepoFolderResolver.resolve(
      workspacePath: rootPath,
      repoName: repoName,
    );
    final ticketRepoDir =
        resolved ?? directoryFactory(path.join(rootPath, repoName));
    if (ticketRepoDir.existsSync()) {
      ticketRepoDir.deleteSync(recursive: true);
      ggLog(
        green(
          'Deleted repository $repoName from ticket '
          '${path.basename(rootPath)}.',
        ),
      );
    } else {
      ggLog(
        red(
          'Repository $repoName is not part of ticket '
          '${path.basename(rootPath)}.',
        ),
      );
    }
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
