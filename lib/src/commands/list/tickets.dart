// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'dart:convert';
import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;
import '../../backend/workspace_utils.dart';

/// Command to list all tickets and their descriptions.
class ListTicketsCommand extends Command<void> {
  /// Constructor with optional workspace path
  ListTicketsCommand({
    required this.ggLog,
    String? workspacePath,
    // coverage:ignore-start
  }) : workspacePath =
            workspacePath ?? WorkspaceUtils.defaultKidneyWorkspacePath();
  // coverage:ignore-end

  /// The logger function
  final GgLog ggLog;

  /// The resolved master workspace path
  final String workspacePath;

  @override
  String get name => 'tickets';

  @override
  String get description => 'List tickets and their descriptions.';

  @override
  Future<void> run() async {
    final ticketsDir = Directory(path.join(workspacePath, 'tickets'));
    if (!ticketsDir.existsSync()) {
      ggLog(yellow('No tickets found.'));
      return;
    }
    final subs = ticketsDir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));
    if (subs.isEmpty) {
      ggLog(yellow('No tickets found.'));
      return;
    }
    for (final d in subs) {
      final ticketName = path.basename(d.path);
      final ticketFile = File(path.join(d.path, '.ticket'));
      if (!ticketFile.existsSync()) {
        ggLog(red('Missing .ticket file for ticket $ticketName'));
        continue;
      }
      try {
        final content = ticketFile.readAsStringSync();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final desc = data['description'] as String? ?? '';
        ggLog('$ticketName    $desc'); // four spaces between name and desc
      } catch (e) {
        ggLog(red('Error parsing .ticket for ticket $ticketName: $e'));
      }
    }
  }
}
