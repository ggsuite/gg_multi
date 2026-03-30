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
import '../../../backend/constants.dart';
import '../../../backend/workspace_utils.dart';
import 'package:path/path.dart' as p;

/// Typedef for creating Directory instances (for testing).
typedef DirectoryFactory = Directory Function(String path);

/// Command to create a ticket folder and save ticket data as JSON.
class TicketCommand extends DirCommand<void> {
  /// Constructor with optional workspace [rootPath] and [directoryFactory].
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
    // The ticket message
    argParser.addOption(
      'message',
      abbr: 'm',
      help: 'Ticket description.',
      mandatory: true,
    );
  }

  /// Base path that contains the `tickets` folder.
  final String rootPath;

  /// Factory to create Directory instances
  final DirectoryFactory directoryFactory;

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

    final relPath = p.relative(ticketsPath, from: directory.path);

    if (dir.existsSync() && ticketFile.existsSync()) {
      ggLog(
        red(
          'Error: Ticket $issueId already exists at '
          '$relPath',
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

    ggLog('✅ Created ticket $issueId');
    ggLog(
      yellow('Execute the following command to enter the ticket workspace:'),
    );
    ggLog(blue('cd $relPath'));
  }
}
