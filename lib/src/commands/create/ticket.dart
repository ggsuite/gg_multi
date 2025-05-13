// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;

/// Typedef for creating Directory instances (for testing).
typedef DirectoryFactory = Directory Function(String path);

/// Command to create a ticket folder and save ticket data as JSON.
class TicketCommand extends Command<void> {
  /// Constructor with optional root path and directory factory.
  TicketCommand({
    required this.ggLog,
    String? rootPath,
    DirectoryFactory? directoryFactory,
  })  : rootPath = rootPath ?? Directory.current.path,
        directoryFactory = directoryFactory ?? Directory.new {
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
    final ticketsPath = path.join(rootPath, 'tickets', issueId);
    final dir = directoryFactory(ticketsPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    // Write the .ticket file as JSON.
    final file = File(path.join(ticketsPath, '.ticket'));
    final data = <String, String>{
      'issue_id': issueId,
      'description': description,
    };
    file.writeAsStringSync(jsonEncode(data));

    ggLog('Created ticket $issueId at $ticketsPath');
  }
}
