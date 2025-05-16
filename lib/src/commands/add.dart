// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../backend/git_cloner.dart';
import '../backend/add_repository_helper.dart';

/// Command to add a repository or all repositories from an organization.
///
/// This command adds the specified git repo (also Gitlab and other servers
/// compatible) or all git repos of the specified organization.
/// It clones the project into the master workspace of the project root and-
/// if executed from inside a ticket directory (./tickets/ticket)—it also
/// copies the repository into this ticket directory.  When the repository is
/// already present in the master workspace it is **not** cloned again but just
/// copied into the ticket.
///
/// Use the "--force" flag to overwrite an existing repository in the master
/// workspace.
class AddCommand extends Command<dynamic> {
  /// Constructor for AddCommand.
  AddCommand({
    required this.ggLog,
    GitCloner? gitCloner,
    Future<http.Response> Function(Uri)? repoFetcher,
    String? workspacePath,
    // coverage:ignore-start
  })  : gitCloner = gitCloner ?? GitCloner(),
        repoFetcher = repoFetcher ?? http.get,
        workspacePath = workspacePath ?? _defaultMasterWorkspacePath() {
    // -----------------------------------------------------------------------
    // Command line flags -----------------------------------------------------
    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'If set, an existing repository in the master workspace will be '
          'deleted before cloning it again.',
      negatable: false,
      defaultsTo: false,
    );
  }
  // coverage:ignore-end

  /// The log function.
  final GgLog ggLog;

  /// Instance to handle cloning.
  final GitCloner gitCloner;

  /// Function to fetch repositories from the organization API.
  final Future<http.Response> Function(Uri) repoFetcher;

  /// Resolved master workspace path.
  final String workspacePath;

  @override
  String get name => 'add';

  @override
  String get description => 'Adds the specified git repo or all git repos '
      'from the specified organization into the master workspace—and if run '
      'from inside a ticket, also into that ticket workspace.';

  @override
  Future<void> run() async {
    if (argResults!.rest.isEmpty) {
      throw UsageException('Missing target parameter.', usage);
    }

    final String targetArg = argResults!.rest[0];
    // Read the --force flag (defaults to false if not provided)
    final bool force = (argResults!['force'] as bool?) ?? false;

    // Detect whether we are inside a ticket directory -------------------------
    final String? ticketPath = _detectTicketPath();

    await addRepositoryHelper(
      targetArg: targetArg,
      ggLog: ggLog,
      gitCloner: gitCloner,
      repoFetcher: repoFetcher,
      workspacePath: workspacePath,
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

  // ---------------------------------------------------------------------------
  // Ticket support helpers ----------------------------------------------------

  /// Copies the repository from the master workspace to the [ticketPath].  If
  /// the repository already exists in the ticket workspace, nothing happens.
  Future<void> _addRepoToTicket({
    required String repoName,
    required String ticketPath,
  }) async {
    final srcDir = Directory(path.join(workspacePath, repoName));
    if (!srcDir.existsSync()) {
      // Should never happen – repo must be present in master at this point.
      ggLog(red('Repository $repoName not found in master workspace.'));
      return;
    }

    final destDir = Directory(path.join(ticketPath, repoName));
    if (destDir.existsSync() && destDir.listSync().isNotEmpty) {
      ggLog(darkGray('$repoName already exists in ticket workspace.'));
      return;
    }

    await _copyDirectory(srcDir, destDir);
    ggLog(green('Added repository $repoName to ticket workspace.'));
  }

  /// Recursively copies [source] to [destination].
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    if (!destination.existsSync()) {
      await destination.create(recursive: true);
    }

    await for (final entity in source.list(recursive: false)) {
      final newPath = path.join(destination.path, path.basename(entity.path));
      if (entity is File) {
        await entity.copy(newPath);
      } else if (entity is Directory) {
        // Coverage workaround: move block to a method for easier testing
        await _copySubDirectory(entity, Directory(newPath));
      } else if (entity is Link) {
        final target = await entity.target();
        await Link(newPath).create(target);
      }
    }
  }

  /// Helper to copy a subdirectory (extracted for testability and coverage)
  Future<void> _copySubDirectory(
    Directory source,
    Directory destination,
  ) async {
    await _copyDirectory(source, destination);
  }

  /// Walks up the directory tree to find a ticket directory and returns its
  /// path when found, otherwise `null`.
  String? _detectTicketPath() {
    var current = Directory.current;
    while (true) {
      final parent = current.parent;
      if (path.basename(parent.path) == 'tickets') {
        return current.path;
      }
      if (current.path == parent.path) {
        // Reached filesystem root without finding a ticket.
        return null;
      }
      current = parent;
    }
  }

  // ---------------------------------------------------------------------------
  // Static helpers ------------------------------------------------------------

  /// Determines the project root (directory that contains either a
  /// `kidney_ws_master` folder or a `tickets` folder) and returns the full path
  /// to the master workspace inside that root.
  static String _defaultMasterWorkspacePath() {
    var dir = Directory.current;
    while (true) {
      // Found an existing master workspace in this folder → use it.
      if (Directory(path.join(dir.path, 'kidney_ws_master')).existsSync()) {
        return path.join(dir.path, 'kidney_ws_master');
      }
      // Found the tickets folder → the root is the parent of tickets.
      if (Directory(path.join(dir.path, 'tickets')).existsSync()) {
        return path.join(dir.path, 'kidney_ws_master');
      }
      final parent = dir.parent;
      if (parent.path == dir.path) {
        // Reached filesystem root → fall back to current directory.
        return path.join(Directory.current.path, 'kidney_ws_master');
      }
      dir = parent;
    }
  }
}
