// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg/gg.dart' as gg;
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;

import '../../backend/workspace_utils.dart';

/// Command to push changes across all repositories in the current ticket.
class DoPushCommand extends DirCommand<void> {
  /// Constructor
  DoPushCommand({
    required super.ggLog,
    super.name = 'push',
    super.description =
        'Pushes changes across all repositories in the current ticket.',
    gg.CanPush? ggCanPush,
    gg.DoPush? ggDoPush,
    SortedProcessingList? sortedProcessingList,
  })  : _ggDoPush = ggDoPush ?? gg.DoPush(ggLog: ggLog),
        _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog) {
    _addArgs();
  }

  /// Instance of gg DoPush to perform the push action
  final gg.DoPush _ggDoPush;

  /// Sorted processing of repositories within a ticket
  final SortedProcessingList _sortedProcessingList;

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    bool? force,
    bool? verbose,
  }) =>
      get(
        directory: directory,
        ggLog: ggLog,
        force: force,
        verbose: verbose,
      );

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    bool? force,
    bool? verbose,
  }) async {
    // Read verbose flag from CLI if not provided programmatically.
    verbose ??= argResults?['verbose'] as bool? ?? false;

    // Detect if we are inside a ticket folder
    final String? ticketPath = WorkspaceUtils.detectTicketPath(
      path.absolute(directory.path),
    );
    if (ticketPath == null) {
      ggLog(red('This command must be executed inside a ticket folder.'));
      throw Exception('Not inside a ticket folder');
    }

    final ticketDir = Directory(ticketPath);
    final ticketName = path.basename(ticketDir.path);

    // Collect all repository directories
    // in the ticket using SortedProcessingList
    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (nodes.isEmpty) {
      ggLog(yellow('⚠️ No repositories found in ticket $ticketName.'));
      return;
    }

    // List repositories that will be pushed ---------------------------------
    final repoNames =
        nodes.map((node) => path.basename(node.directory.path)).toList();

    final GgLog taskLog = verbose ? ggLog : <String>[].add;

    ggLog(yellow('Pushing the following repos:'));
    for (final name in repoNames) {
      ggLog(yellow(' - $name'));
    }

    // Perform the push wrapped in a status printer --------------------------
    await GgStatusPrinter<void>(
      message: 'Pushing repos',
      ggLog: ggLog,
    ).run(() async {
      await _pushingRepos(
        nodes: nodes,
        ggLog: taskLog,
        ticketName: ticketName,
        force: force ?? false,
      );
    });
  }

  Future<void> _pushingRepos({
    required List<Node> nodes,
    required GgLog ggLog,
    required String ticketName,
    required bool force,
  }) async {
    final failedRepos = <String>[];

    for (final node in nodes) {
      final repoDir = node.directory;
      final repoName = path.basename(repoDir.path);

      ggLog(yellow('Pushing $repoName in ticket $ticketName...'));

      try {
        await _ggDoPush.exec(
          directory: repoDir,
          ggLog: ggLog,
          force: force,
        );
      } catch (e) {
        ggLog(red('❌ Failed to push $repoName: $e'));
        failedRepos.add(repoName);
      }
    }

    // Summarize the results ----------------------------------------------
    if (failedRepos.isEmpty) {
      ggLog(
        '✅ All repositories in ticket '
        '$ticketName pushed successfully.',
      );
    } else {
      ggLog(
        red(
          '❌ Failed to push the following repositories in '
          'ticket $ticketName:',
        ),
      );
      for (final repoName in failedRepos) {
        ggLog(red(' - $repoName'));
      }
      throw Exception(
        'Failed to push some repositories in ticket $ticketName',
      );
    }
  }

  // Adds command line arguments
  void _addArgs() {
    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Do a force push.',
      defaultsTo: false,
      negatable: true,
    );
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'Show detailed log output.',
      defaultsTo: false,
      negatable: true,
    );
  }
}

/// Mock for [DoPushCommand]
class MockDoPushCommand extends MockDirCommand<void> implements DoPushCommand {}
