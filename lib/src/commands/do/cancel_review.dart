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
import 'package:gg_localize_refs/gg_localize_refs.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;

import '../../backend/status_utils.dart';
import '../../backend/workspace_utils.dart';

/// Typedef for running processes (for injection & tests).
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

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

/// Command to revert review preparation and relocalize repos to local paths.
class DoCancelReviewCommand extends DirCommand<void> {
  /// Creates a new cancel review command.
  DoCancelReviewCommand({
    required super.ggLog,
    super.name = 'cancel-review',
    super.description =
        'Set dependencies back to local paths and commits the changes.',
    ChangeRefsToLocal? localizeRefs,
    SortedProcessingList? sortedProcessingList,
    gg.DoCommit? ggDoCommit,
    ProcessRunner? processRunner,
  })  : _localizeRefs = localizeRefs ?? ChangeRefsToLocal(ggLog: ggLog),
        _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog),
        _ggDoCommit = ggDoCommit ?? gg.DoCommit(ggLog: ggLog),
        _processRunner = processRunner ?? _defaultProcessRunner {
    _addArgs();
  }

  /// Localizes refs to local path dependencies.
  final ChangeRefsToLocal _localizeRefs;

  /// Provides repositories in dependency order.
  final SortedProcessingList _sortedProcessingList;

  /// Commits changes in each repository.
  final gg.DoCommit _ggDoCommit;

  /// Process runner used to invoke language-specific install commands.
  final ProcessRunner _processRunner;

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
    bool? verbose,
  }) =>
      get(
        directory: directory,
        ggLog: ggLog,
        verbose: verbose,
      );

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
    bool? verbose,
  }) async {
    verbose ??= argResults?['verbose'] as bool? ?? false;

    final String? ticketPath = WorkspaceUtils.detectTicketPath(
      path.absolute(directory.path),
    );
    if (ticketPath == null) {
      ggLog(red('This command must be executed inside a ticket folder.'));
      throw Exception('Not inside a ticket folder');
    }

    final ticketDir = Directory(ticketPath);
    final ticketName = path.basename(ticketDir.path);

    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (nodes.isEmpty) {
      ggLog(yellow('⚠️ No repositories found in ticket $ticketName.'));
      return;
    }

    final GgLog taskLog = verbose ? ggLog : <String>[].add;

    await GgStatusPrinter<void>(
      message: 'Setting dependencies back to local paths and committing',
      ggLog: ggLog,
    ).run(
      () async => _relocalizeAndCommitAll(
        ticketName: ticketName,
        nodes: nodes,
        ggLog: taskLog,
      ),
    );
  }

  /// Re-localizes all repos and commits the changes without pushing.
  Future<void> _relocalizeAndCommitAll({
    required String ticketName,
    required List<Node> nodes,
    required GgLog ggLog,
  }) async {
    for (final node in nodes) {
      final repoDir = node.directory;
      final repoName = path.basename(repoDir.path);

      try {
        await _localizeRefs.get(directory: repoDir, ggLog: ggLog);
        ggLog(green('Localized refs to local paths for $repoName'));
        StatusUtils.setStatus(
          repoDir,
          StatusUtils.statusLocalized,
          ggLog: ggLog,
        );
      } catch (e) {
        ggLog(
          red(
            'Failed to localize refs to local paths for $repoName: $e',
          ),
        );
        throw Exception(
          'Failed to cancel review for some repositories in ticket '
          '$ticketName',
        );
      }

      // node_modules will be stale after rewriting package.json — refresh.
      await _refreshTypeScriptDependencies(
        repoDir: repoDir,
        repoName: repoName,
        ticketName: ticketName,
        ggLog: ggLog,
      );

      try {
        await _ggDoCommit.exec(
          directory: repoDir,
          ggLog: ggLog,
          message: 'kidney: changed references to local',
          force: true,
        );
        ggLog(green('Committed $repoName'));
      } catch (e) {
        ggLog(red('Failed to commit $repoName: $e'));
        throw Exception(
          'Failed to cancel review for some repositories in ticket '
          '$ticketName',
        );
      }
    }

    ggLog(
      '✅ All repositories in ticket $ticketName were '
      'localized back to local paths and committed.',
    );
  }

  /// Adds command line arguments for this command.
  void _addArgs() {
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'Show detailed log output.',
      defaultsTo: false,
      negatable: true,
    );
  }

  /// Runs the package manager's install command for TypeScript projects so
  /// that node_modules reflects the freshly-rewritten local path
  /// dependencies. Dart packages are skipped because pub resolves lazily.
  Future<void> _refreshTypeScriptDependencies({
    required Directory repoDir,
    required String repoName,
    required String ticketName,
    required GgLog ggLog,
  }) async {
    final gg.ProjectType projectType;
    try {
      projectType = gg.detectProjectType(repoDir);
    } catch (_) {
      return;
    }
    if (projectType != gg.ProjectType.typescript) return;

    final pm = gg.detectTypeScriptPackageManager(repoDir);
    final result = await _processRunner(
      pm.executable,
      <String>['install'],
      workingDirectory: repoDir.path,
    );
    final cmd = '${pm.executable} install';
    if (result.exitCode == 0) {
      ggLog(green('Executed $cmd in $repoName.'));
    } else {
      ggLog(
        red(
          'Failed to execute $cmd in $repoName: ${result.stderr}',
        ),
      );
      throw Exception(
        'Failed to cancel review for some repositories in ticket '
        '$ticketName',
      );
    }
  }
}

/// Mock for [DoCancelReviewCommand]
class MockDoCancelReviewCommand extends MockDirCommand<void>
    implements DoCancelReviewCommand {}
