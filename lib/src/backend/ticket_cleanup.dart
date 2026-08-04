// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;

import 'git_snapshot.dart';
import 'trash.dart';

/// Moves everything a finished ticket leaves behind into
/// `<root>/.trash/<ticket>` and removes the ticket folder afterwards.
///
/// Shared by `do publish` (when the user accepts the cleanup offer after
/// every repo is published) and `do rm ticket` (the explicit way to close a
/// ticket later). The repositories are never deleted outright — they move to
/// the trash **as they are**, feature branches, restored overrides and
/// uncommitted leftovers included, so nothing is lost. The
/// `<ticket>.code-workspace` file travels along, so reopening the closed
/// ticket in VS Code is still possible from the trash.
///
/// Every repository in [repoDirs] is moved — also when its remote feature
/// branch is kept ([deleteRemoteBranch] is false), because the ticket folder
/// goes away either way and a repo left inside it would be lost. A failure
/// while trashing a single repo is reported and the remaining ones are still
/// processed; the ticket folder is only removed when nothing was left
/// behind.
///
/// After the ticket folder is gone the caller's shell sits in a deleted
/// directory, so the command to change to the workspace root is printed in
/// blue.
Future<void> cleanUpTicket({
  required Directory ticketDir,
  required List<Directory> repoDirs,
  required bool deleteRemoteBranch,
  required GgLog ggLog,
  required GgLog taskLog,
  ProcessRunner? processRunner,
}) async {
  final runner = processRunner ?? _defaultProcessRunner;
  final ticketName = path.basename(ticketDir.path);
  var allMoved = true;

  for (final repoDir in repoDirs) {
    final repoName = path.basename(repoDir.path);

    try {
      if (deleteRemoteBranch) {
        await _deleteRemoteBranch(
          repoDir: repoDir,
          branchName: ticketName,
          ggLog: taskLog,
          processRunner: runner,
        );
      } else {
        taskLog(cDetail('✓ Kept remote branch $ticketName for $repoName.'));
      }

      if (repoDir.existsSync()) {
        final target = await Trash.moveFromTicket(
          source: repoDir,
          ticketDir: ticketDir,
        );
        // Moving a repo out of the ticket is destructive from the
        // user's point of view — it disappears from where they worked.
        // So it is a warning, not a detail, and it goes to ggLog: a
        // non-verbose run must not swallow it.
        ggLog(
          cWarn(
            '⚠️ Moved repository $repoName of ticket $ticketName '
            'to $target.',
          ),
        );
      }
    } catch (e) {
      allMoved = false;
      ggLog(
        cError(
          'Failed to move repository $repoName of ticket $ticketName to '
          'the trash: $e',
        ),
      );
    }
  }

  // The VS Code workspace describes a ticket that no longer exists — it
  // belongs to the trashed repos, so it follows them.
  final workspaceFile = File(
    path.join(ticketDir.path, '$ticketName.code-workspace'),
  );
  if (workspaceFile.existsSync()) {
    try {
      final target = await Trash.moveFromTicket(
        source: workspaceFile,
        ticketDir: ticketDir,
      );
      ggLog(cWarn('⚠️ Moved ${path.basename(target)} to $target.'));
    } catch (e) {
      allMoved = false;
      ggLog(
        cError('Failed to move the VS Code workspace of $ticketName: $e'),
      );
    }
  }

  if (!allMoved) {
    ggLog(
      cWarn(
        'Ticket $ticketName was not deleted because not everything could '
        'be moved to the trash.',
      ),
    );
    return;
  }

  // The workspace root is the grandparent of `<root>/tickets/<ticket>` —
  // resolved before the deletion, while the path still exists.
  final workspaceRoot = ticketDir.absolute.parent.parent.path;

  if (ticketDir.existsSync()) {
    ticketDir.deleteSync(recursive: true);
    ggLog(cWarn('⚠️ Deleted ticket folder ${ticketDir.path}.'));
  }

  // The shell of the caller now sits inside a deleted folder — hand them
  // the way out.
  ggLog(cAction('\nChange to the workspace root with:'));
  ggLog(cCmd('  cd $workspaceRoot'));
}

/// Deletes the remote feature branch [branchName] for [repoDir].
Future<void> _deleteRemoteBranch({
  required Directory repoDir,
  required String branchName,
  required GgLog ggLog,
  required ProcessRunner processRunner,
}) async {
  final repoName = path.basename(repoDir.path);
  final result = await processRunner(
    'git',
    <String>['push', 'origin', '--delete', branchName],
    workingDirectory: repoDir.path,
  );

  if (result.exitCode != 0) {
    // The branch might have been deleted already, e.g. directly on GitHub.
    // Then there is nothing left to do and nothing to complain about.
    final stderr = '${result.stderr}';
    if (stderr.contains('remote ref does not exist')) {
      ggLog(
        cWarn('Remote branch $branchName for $repoName is already deleted.'),
      );
      return;
    }

    throw Exception(
      cError(
        'Failed to delete remote branch $branchName for $repoName: '
        '$stderr',
      ),
    );
  }

  ggLog(cDetail('Deleted remote branch $branchName for $repoName.'));
}

/// Runs system processes with shell support.
// coverage:ignore-start
Future<ProcessResult> _defaultProcessRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  return Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: true,
  );
}
// coverage:ignore-end
