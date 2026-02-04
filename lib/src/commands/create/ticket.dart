// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;
import '../../backend/constants.dart';
import '../../backend/workspace_utils.dart';
import 'package:path/path.dart' as p;

/// Typedef for creating Directory instances (for testing).
typedef DirectoryFactory = Directory Function(String path);

/// Command to create a ticket folder and save ticket data as JSON.
///
/// This is implemented as a [DirCommand] so that all paths that are printed
/// to the console are relative to the directory where the command is
/// executed (the `--input` argument or `Directory.current`), not to the
/// workspace root.  As a consequence, when the command is invoked *inside*
/// the `tickets` folder, the user is instructed to
/// `cd <ticket_name>` instead of `cd tickets/<ticket_name>`.
class TicketCommand extends DirCommand<void> {
  /// Constructor with optional workspace [rootPath] and [directoryFactory].
  ///
  /// * [rootPath] defines the Kidney workspace root that contains the
  ///   `tickets` folder.  It defaults to
  ///   [WorkspaceUtils.defaultKidneyWorkspacePath].
  /// * [directoryFactory] is only used to create the ticket directory and is
  ///   mainly meant for tests.
  TicketCommand({
    required super.ggLog,
    String? rootPath,
    DirectoryFactory? directoryFactory,
    super.name = 'ticket',
    super.description = 'Create a ticket folder and save ticket data as JSON.',
    // coverage:ignore-start
  })  : rootPath = rootPath ?? WorkspaceUtils.defaultKidneyWorkspacePath(),
        directoryFactory = directoryFactory ?? Directory.new
  // coverage:ignore-end
  {
    // The ticket message is optional. A ticket might only consist of an ID.
    argParser.addOption(
      'message',
      abbr: 'm',
      help: 'Ticket description (optional).',
      mandatory: false,
    );
  }

  /// Base path that contains the `tickets` folder.
  final String rootPath;

  /// Factory to create Directory instances
  final DirectoryFactory directoryFactory;

  /// Returns [absPath] relative to the directory where the command is
  /// executed (the resolved `--input` directory).
  String _rel(String absPath, Directory executionDir) =>
      p.relative(absPath, from: executionDir.path);

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
  }) =>
      get(
        directory: directory,
        ggLog: ggLog,
      );

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    // Validate issue id ------------------------------------------------------
    if (argResults!.rest.isEmpty) {
      throw UsageException(
        'Missing issue id parameter.',
        usage,
      );
    }

    final issueId = argResults!.rest.first;

    // The description might be null if the user did not pass --message / -m.
    final String description = (argResults!['message'] as String?) ?? '';

    // Build the directory path for the ticket (always under the workspace
    // root, independent from the execution directory).
    final ticketsPath = path.join(rootPath, kidneyTicketFolder, issueId);
    final dir = directoryFactory(ticketsPath);
    final ticketFile = File(path.join(ticketsPath, '.ticket'));

    if (dir.existsSync() && ticketFile.existsSync()) {
      ggLog(
        red(
          'Error: Ticket $issueId already exists at '
          '${_rel(ticketsPath, directory)}',
        ),
      );
      return;
    }

    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    // Write the .ticket file as JSON.
    final data = <String, String>{
      'issue_id': issueId,
      'description': description,
    };
    ticketFile.writeAsStringSync(jsonEncode(data));

    final relPath = _rel(ticketsPath, directory);

    ggLog(green('Created ticket $issueId at $relPath'));
    ggLog('Execute "${blue('cd $relPath')}" '
        'to enter the ticket workspace.');
  }
}
