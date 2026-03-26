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
import 'package:path/path.dart' as path;

import '../../backend/workspace_utils.dart';

/// Typedef for running processes (for injection & tests).
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

/// Default process runner that uses the system's `Process.run`
// coverage:ignore-start
Future<ProcessResult> _defaultProcessRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) =>
    Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: true,
    );
// coverage:ignore-end

/// Command to check if all repos in the ticket can be reviewed.
class CanReviewCommand extends DirCommand<void> {
  /// Constructor
  CanReviewCommand({
    required super.ggLog,
    super.name = 'review',
    super.description =
        'Checks if all repositories in the current ticket can be reviewed.',
    SortedProcessingList? sortedProcessingList,
    ProcessRunner? processRunner,
  })  : _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog),
        _processRunner = processRunner ?? _defaultProcessRunner;

  /// Instance of SortedProcessingList
  final SortedProcessingList _sortedProcessingList;

  /// The process runner
  final ProcessRunner _processRunner;

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
    // Step 1: Detect ticket folder
    final String? ticketPath = WorkspaceUtils.detectTicketPath(
      path.absolute(directory.path),
    );
    if (ticketPath == null) {
      ggLog(red('This command must be executed inside a ticket folder.'));
      throw Exception('Not inside a ticket folder');
    }

    final ticketDir = Directory(ticketPath);
    final ticketName = path.basename(ticketDir.path);

    // Get sorted repos
    final subs = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (subs.isEmpty) {
      ggLog(yellow('⚠️ No repositories found in ticket $ticketName.'));
      return;
    }

    // Step 3: Check for uncommitted changes
    final uncommitted = <String>[];
    for (final repo in subs) {
      final repoDir = repo.directory;
      final result = await _processRunner(
        'git',
        ['status', '--porcelain'],
        workingDirectory: repoDir.path,
      );
      if (result.stdout.toString().trim().isNotEmpty) {
        uncommitted.add(path.basename(repoDir.path));
      }
    }
    if (uncommitted.isNotEmpty) {
      ggLog(yellow('Uncommitted changes found in the following repos:'));
      for (final name in uncommitted) {
        ggLog(yellow(' - $name'));
      }
      throw Exception('Uncommitted changes found');
    }

    // All successful
    ggLog('✅ All repositories in ticket $ticketName can be reviewed.');
  }
}

/// Mock for [CanReviewCommand]
class MockCanReviewCommand extends MockDirCommand<void>
    implements CanReviewCommand {}
