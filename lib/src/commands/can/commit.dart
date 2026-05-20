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

/// Default number of parallel workers.
const int _defaultMaxParallel = 4;

/// Command to check if all repos in the ticket can be committed.
///
/// Iterates over all repositories in the current ticket in parallel and runs
/// `gg can commit` on each. Short per-repo status lines are always printed
/// via [GgStatusPrinter]; the verbose sub-output of `gg can commit` is only
/// shown when `--verbose` is passed. The number of concurrent workers is
/// controlled with `-j N` (default: 4). On failure the command keeps going
/// so the user sees the full picture, and only throws at the end.
class CanCommitCommand extends DirCommand<void> {
  /// Constructor
  CanCommitCommand({
    required super.ggLog,
    super.name = 'commit',
    super.description =
        'Checks if all repositories in the current ticket can be committed.',
    gg.CanCommit? ggCanCommit,
    SortedProcessingList? sortedProcessingList,
  })  : _ggCanCommit = ggCanCommit ?? gg.CanCommit(ggLog: ggLog),
        _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog) {
    _addArgs();
  }

  /// Instance of gg CanCommit
  final gg.CanCommit _ggCanCommit;

  /// Sorted processing list for repos
  final SortedProcessingList _sortedProcessingList;

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    bool? verbose,
    int? maxParallel,
  }) =>
      get(
        directory: directory,
        ggLog: ggLog,
        verbose: verbose,
        maxParallel: maxParallel,
      );

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    bool? verbose,
    int? maxParallel,
  }) async {
    verbose ??= argResults?['verbose'] as bool? ?? false;
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
    // Collect all repository directories in the ticket via SortedProcessingList
    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (nodes.isEmpty) {
      ggLog(yellow('⚠️ No repos in this ticket'));
      return;
    }

    // Sub-output of `gg can commit` is only forwarded when --verbose is set.
    final GgLog taskLog = verbose ? ggLog : <String>[].add;

    // When running in parallel, the carriage-return trick of
    // [GgStatusPrinter] would garble lines from other workers. Force the
    // multi-line variant in that case.
    final bool useCarriageReturn = maxParallel == 1;

    final failures = <String, Object>{};

    await runWithLimit<Node>(nodes, maxParallel, (node) async {
      final repoDir = node.directory;
      final repoName = path.basename(repoDir.path);

      final printer = GgStatusPrinter<void>(
        message: 'Can commit: $repoName',
        ggLog: ggLog,
        useCarriageReturn: useCarriageReturn,
      );

      try {
        await printer.run(
          () => _ggCanCommit.exec(
            directory: repoDir,
            ggLog: prefixedLog('[$repoName] ', taskLog),
          ),
        );
      } catch (e) {
        // GgStatusPrinter already logged the ❌ line. Remember the failure
        // but do NOT rethrow here — other workers must keep running.
        failures[repoName] = e;
      }
    });

    if (failures.isEmpty) {
      ggLog(green('✅ All repos can be committed'));
      return;
    }

    ggLog(
      red(
        '❌ ${failures.length} of ${nodes.length} repos cannot be committed:',
      ),
    );
    for (final entry in failures.entries) {
      ggLog(red(' - ${entry.key}: ${entry.value}'));
    }
    throw Exception(
      'Cannot commit: ${failures.keys.join(', ')}',
    );
  }

  void _addArgs() {
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'Show detailed log output of the underlying »gg can commit« '
          'checks.',
      defaultsTo: false,
      negatable: true,
    );
    argParser.addOption(
      'jobs',
      abbr: 'j',
      help: 'Maximum number of repositories checked in parallel.',
      defaultsTo: '$_defaultMaxParallel',
    );
  }
}

/// Mock for [CanCommitCommand]
class MockCanCommitCommand extends MockDirCommand<void>
    implements CanCommitCommand {}
