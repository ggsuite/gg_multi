// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:path/path.dart' as path;

import '../../backend/workspace_utils.dart';

/// Command to push changes across all repositories in the current ticket.
class DoPushCommand extends DirCommand<void> {
  /// Constructor
  DoPushCommand({
    required super.ggLog,
    super.name = 'push',
    super.description = 'Push changes in all ticket repos',
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
      ggLog(cError('This command must be executed inside a ticket folder.'));
      throw Exception(cError('Not inside a ticket folder'));
    }

    final ticketDir = Directory(ticketPath);

    // Collect all repository directories
    // in the ticket using SortedProcessingList
    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (nodes.isEmpty) {
      ggLog(cWarn('⚠️ No repos in this ticket'));
      return;
    }

    // List repositories that will be pushed ---------------------------------
    final repoNames =
        nodes.map((node) => path.basename(node.directory.path)).toList();

    // Only the output of `gg do push` per repo is verbose. The repo headers
    // and the summary are what the user needs either way, so they go to
    // ggLog — a taskLog for all of it would swallow them without --verbose.
    final GgLog taskLog = verbose ? ggLog : <String>[].add;

    ggLog(cDetail('Pushing the following repos:'));
    for (final name in repoNames) {
      ggLog(cDetail(' - $name'));
    }

    await _pushingRepos(
      nodes: nodes,
      ggLog: ggLog,
      taskLog: taskLog,
      force: force ?? false,
    );
  }

  Future<void> _pushingRepos({
    required List<Node> nodes,
    required GgLog ggLog,
    required GgLog taskLog,
    required bool force,
  }) async {
    // The reason a repo failed is kept, not just its name: it is the only
    // thing that tells the user what to do next.
    final failures = <String, Object>{};

    for (final node in nodes) {
      final repoDir = node.directory;
      final repoName = path.basename(repoDir.path);

      ggLog('\n${cH1(repoName)}');

      try {
        await _ggDoPush.exec(
          directory: repoDir,
          ggLog: taskLog,
          force: force,
        );
      } catch (e) {
        ggLog(cError('✗ Failed to push $repoName: $e'));
        failures[repoName] = e;
      }
    }

    // Summarize the results ----------------------------------------------
    if (failures.isEmpty) {
      ggLog('\nAll repos pushed\n');
      return;
    }

    ggLog(cError('✗ Push failed in:'));
    for (final entry in failures.entries) {
      ggLog(cDetail(' - ${cCmd(entry.key)}: ${entry.value}'));
    }
    throw Exception(
      cError(
        'Failed to push in:\n'
        '${failures.entries.map((e) => ' - ${e.key}: ${e.value}').join('\n')}',
      ),
    );
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
