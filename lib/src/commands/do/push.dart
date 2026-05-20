// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_one/gg_one.dart' as gg;
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;

import '../../backend/parallel.dart';
import '../../backend/workspace_utils.dart';

/// Default number of parallel push workers.
const int _defaultMaxParallel = 4;

/// Command to push changes across all repositories in the current ticket.
///
/// Each repository is pushed in its own worker (up to `-j N`, default 4),
/// with a short [GgStatusPrinter] status line per repo. With `--verbose`,
/// the underlying `gg do push` output is forwarded and prefixed with the
/// repo name so parallel output remains attributable. Failures do not stop
/// other workers — all failed repos are reported in a summary at the end,
/// and the command then throws.
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
    int? maxParallel,
  }) =>
      get(
        directory: directory,
        ggLog: ggLog,
        force: force,
        verbose: verbose,
        maxParallel: maxParallel,
      );

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    bool? force,
    bool? verbose,
    int? maxParallel,
  }) async {
    // Read flags from CLI when not provided programmatically.
    verbose ??= argResults?['verbose'] as bool? ?? false;
    force ??= argResults?['force'] as bool? ?? false;
    maxParallel ??= int.tryParse(
          (argResults?['jobs'] as String?) ?? '',
        ) ??
        _defaultMaxParallel;
    if (maxParallel < 1) {
      maxParallel = 1;
    }

    // Detect if we are inside a ticket folder
    final String? ticketPath = WorkspaceUtils.detectTicketPath(
      path.absolute(directory.path),
    );
    if (ticketPath == null) {
      ggLog(red('This command must be executed inside a ticket folder.'));
      throw Exception('Not inside a ticket folder');
    }

    final ticketDir = Directory(ticketPath);

    // Collect all repository directories in the ticket using
    // SortedProcessingList.
    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (nodes.isEmpty) {
      ggLog(yellow('⚠️ No repos in this ticket'));
      return;
    }

    // List repositories that will be pushed.
    final repoNames =
        nodes.map((node) => path.basename(node.directory.path)).toList();

    ggLog(yellow('Pushing the following repos:'));
    for (final name in repoNames) {
      ggLog(yellow(' - $name'));
    }

    // Verbose sub-output is only forwarded when --verbose is set.
    final GgLog taskLog = verbose ? ggLog : <String>[].add;

    // In parallel mode the CR-overwrite of GgStatusPrinter would garble
    // lines from other workers, so force the multi-line variant.
    final bool useCarriageReturn = maxParallel == 1;

    final failures = <String, Object>{};

    await runWithLimit<Node>(nodes, maxParallel, (node) async {
      final repoDir = node.directory;
      final repoName = path.basename(repoDir.path);

      final printer = GgStatusPrinter<void>(
        message: 'Pushing: $repoName',
        ggLog: ggLog,
        useCarriageReturn: useCarriageReturn,
      );

      try {
        await printer.run(
          () => _ggDoPush.exec(
            directory: repoDir,
            ggLog: prefixedLog('[$repoName] ', taskLog),
            force: force,
          ),
        );
      } catch (e) {
        failures[repoName] = e;
      }
    });

    if (failures.isEmpty) {
      ggLog(green('✅ All repos pushed'));
      return;
    }

    ggLog(
      red('❌ ${failures.length} of ${nodes.length} repos failed to push:'),
    );
    for (final entry in failures.entries) {
      ggLog(red(' - ${entry.key}: ${entry.value}'));
    }
    throw Exception('Failed to push: ${failures.keys.join(', ')}');
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
      help: 'Show detailed log output of the underlying »gg do push« calls.',
      defaultsTo: false,
      negatable: true,
    );
    argParser.addOption(
      'jobs',
      abbr: 'j',
      help: 'Maximum number of repositories pushed in parallel.',
      defaultsTo: '$_defaultMaxParallel',
    );
  }
}

/// Mock for [DoPushCommand]
class MockDoPushCommand extends MockDirCommand<void> implements DoPushCommand {}
