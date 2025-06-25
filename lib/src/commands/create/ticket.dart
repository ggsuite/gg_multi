// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;
import '../../backend/constants.dart';
import '../../backend/workspace_utils.dart';
import 'package:path/path.dart' as p;

/// Typedef for creating Directory instances (for testing).
typedef DirectoryFactory = Directory Function(String path);

/// Command to create a ticket folder and save ticket data as JSON.
class TicketCommand extends Command<void> {
  /// Constructor with optional root path and directory factory.
  TicketCommand({
    required this.ggLog,
    String? rootPath,
    DirectoryFactory? directoryFactory,
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

  /// Log function
  final GgLog ggLog;

  /// Base path to create tickets folder
  final String rootPath;

  /// Factory to create Directory instances
  final DirectoryFactory directoryFactory;

  String _rel(String absPath) => p.relative(absPath, from: rootPath);

  @override
  String get name => 'ticket';

  @override
  String get description =>
      'Create a ticket folder and save ticket data as JSON.';

  @override
  Future<void> run() async {
    // Validate issue id
    if (argResults!.rest.isEmpty) {
      throw UsageException(
        'Missing issue id parameter.',
        usage,
      );
    }
    final issueId = argResults!.rest.first;
    // The description might be null if the user did not pass --message / -m
    final String description = (argResults!['message'] as String?) ?? '';

    // Build the directory path for the ticket.
    final ticketsPath = path.join(rootPath, kidneyTicketFolder, issueId);
    final dir = directoryFactory(ticketsPath);
    final ticketFile = File(path.join(ticketsPath, '.ticket'));

    if (dir.existsSync() && ticketFile.existsSync()) {
      ggLog(
        red('Error: Ticket $issueId already exists at ${_rel(ticketsPath)}'),
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

    ggLog(green('Created ticket $issueId at ${_rel(ticketsPath)}'));
    ggLog('Execute "cd ${_rel(ticketsPath)}" '
        'to enter the ticket workspace.');
  }
}
