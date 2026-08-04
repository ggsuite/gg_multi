// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';

import '../../../backend/git_snapshot.dart';
import '../../../backend/repo_folder_resolver.dart';
import '../../../backend/ticket_cleanup.dart';
import '../../../backend/workspace_utils.dart';

/// Closes the ticket the command is invoked in: deletes the remote feature
/// branches of its repositories and moves the whole ticket — repositories
/// as they are, plus the `.code-workspace` file — to `<root>/.trash/<ticket>`.
///
/// This is the explicit counterpart of the offer `gg multi do publish` makes
/// once every repo of a ticket is published: keep working for now, close the
/// ticket later with this command. Nothing is deleted outright — the trash
/// keeps everything recoverable, uncommitted leftovers included.
///
/// `--no-delete-remote-branch` keeps the remote branches; the local folders
/// move to the trash either way.
class RemoveTicketCommand extends Command<void> {
  /// Constructor.
  RemoveTicketCommand({
    required this.ggLog,
    String? rootPath,
    ProcessRunner? processRunner,
    // coverage:ignore-start
  })  : rootPath = rootPath ?? Directory.current.path,
        // coverage:ignore-end
        _processRunner = processRunner {
    argParser.addFlag(
      'delete-remote-branch',
      defaultsTo: true,
      help: 'Delete the remote feature branch of every ticket repo.',
    );
  }

  // ...........................................................................
  @override
  String get name => 'ticket';

  // ...........................................................................
  @override
  String get description =>
      'Move the current ticket to the trash and delete its remote branches';

  // ...........................................................................
  @override
  Future<void> run() async {
    final ticketPath = WorkspaceUtils.detectTicketPath(rootPath);
    if (ticketPath == null) {
      throw Exception(
        cError('»gg do rm ticket« must be called inside a ticket folder.'),
      );
    }

    final ticketDir = Directory(ticketPath);
    final repoDirs = RepoFolderResolver.repoDirs(ticketPath);

    await cleanUpTicket(
      ticketDir: ticketDir,
      repoDirs: repoDirs,
      deleteRemoteBranch: argResults!['delete-remote-branch'] as bool,
      ggLog: ggLog,
      taskLog: ggLog,
      processRunner: _processRunner,
    );
  }

  /// Log sink.
  final GgLog ggLog;

  /// Directory the command was invoked in.
  final String rootPath;

  /// Runs git (injectable for tests); null falls back to the real runner.
  final ProcessRunner? _processRunner;
}
