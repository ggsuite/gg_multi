// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_multi/src/backend/ticket_cleanup.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory ticketDir;
  final messages = <String>[];
  final taskMessages = <String>[];

  setUp(() {
    messages.clear();
    taskMessages.clear();
    root = Directory.systemTemp.createTempSync('ticket_cleanup_test_');
    ticketDir = Directory(path.join(root.path, 'tickets', 'T1'))
      ..createSync(recursive: true);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Directory repo(String org, String name) {
    final dir = Directory(path.join(ticketDir.path, org, name))
      ..createSync(recursive: true);
    File(path.join(dir.path, 'pubspec.yaml')).writeAsStringSync('name: $name');
    return dir;
  }

  /// A process runner whose `git push origin --delete <branch>` succeeds.
  Future<ProcessResult> okRunner(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    return ProcessResult(0, 0, '', '');
  }

  group('cleanUpTicket', () {
    test(
      'deletes remote branches, moves everything to the trash, '
      'removes the ticket folder and prints the cd command in blue',
      () async {
        final repoA = repo('ggsuite', 'a');
        final repoB = repo('ggsuite', 'b');
        File(
          path.join(ticketDir.path, 'T1.code-workspace'),
        ).writeAsStringSync('{}');
        final deletedBranches = <String>[];

        await cleanUpTicket(
          ticketDir: ticketDir,
          repoDirs: [repoA, repoB],
          deleteRemoteBranch: true,
          ggLog: messages.add,
          taskLog: taskMessages.add,
          processRunner: (
            String executable,
            List<String> arguments, {
            String? workingDirectory,
            Map<String, String>? environment,
          }) async {
            deletedBranches.add(
              '${path.basename(workingDirectory!)}: '
              '${arguments.join(' ')}',
            );
            return ProcessResult(0, 0, '', '');
          },
        );

        // Both remote branches were deleted, named after the ticket.
        expect(deletedBranches, [
          'a: push origin --delete T1',
          'b: push origin --delete T1',
        ]);

        // Everything moved to the trash, the ticket folder is gone.
        final trash = path.join(root.path, '.trash', 'T1');
        expect(
          Directory(path.join(trash, 'ggsuite', 'a')).existsSync(),
          isTrue,
        );
        expect(
          Directory(path.join(trash, 'ggsuite', 'b')).existsSync(),
          isTrue,
        );
        expect(
          File(path.join(trash, 'T1.code-workspace')).existsSync(),
          isTrue,
        );
        expect(ticketDir.existsSync(), isFalse);

        final log = messages.join('\n');
        expect(log, contains('Moved repository a of ticket T1'));
        expect(log, contains('Deleted ticket folder ${ticketDir.path}.'));

        // The way out of the deleted folder is printed in blue.
        expect(log, contains('Change to the workspace root with:'));
        expect(messages.last, cCmd('  cd ${root.absolute.path}'));
      },
    );

    test('keeps the remote branches when deleteRemoteBranch is false',
        () async {
      final repoA = repo('ggsuite', 'a');
      final gitCalls = <String>[];

      await cleanUpTicket(
        ticketDir: ticketDir,
        repoDirs: [repoA],
        deleteRemoteBranch: false,
        ggLog: messages.add,
        taskLog: taskMessages.add,
        processRunner: (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
          Map<String, String>? environment,
        }) async {
          gitCalls.add(arguments.join(' '));
          return ProcessResult(0, 0, '', '');
        },
      );

      expect(gitCalls, isEmpty);
      expect(
        taskMessages.join('\n'),
        contains('Kept remote branch T1 for a.'),
      );
      // The local folder moves either way — the ticket folder goes away.
      expect(ticketDir.existsSync(), isFalse);
    });

    test('tolerates a remote branch that is already deleted', () async {
      final repoA = repo('ggsuite', 'a');

      await cleanUpTicket(
        ticketDir: ticketDir,
        repoDirs: [repoA],
        deleteRemoteBranch: true,
        ggLog: messages.add,
        taskLog: taskMessages.add,
        processRunner: (
          String executable,
          List<String> arguments, {
          String? workingDirectory,
          Map<String, String>? environment,
        }) async {
          return ProcessResult(0, 1, '', 'remote ref does not exist');
        },
      );

      expect(
        taskMessages.join('\n'),
        contains('Remote branch T1 for a is already deleted.'),
      );
      expect(ticketDir.existsSync(), isFalse);
    });

    test(
      'keeps the ticket folder when a repo could not be processed '
      'and prints no cd command',
      () async {
        final repoA = repo('ggsuite', 'a');

        await cleanUpTicket(
          ticketDir: ticketDir,
          repoDirs: [repoA],
          deleteRemoteBranch: true,
          ggLog: messages.add,
          taskLog: taskMessages.add,
          processRunner: (
            String executable,
            List<String> arguments, {
            String? workingDirectory,
            Map<String, String>? environment,
          }) async {
            return ProcessResult(0, 1, '', 'network down');
          },
        );

        final log = messages.join('\n');
        expect(
          log,
          contains('Failed to move repository a of ticket T1'),
        );
        expect(
          log,
          contains('Ticket T1 was not deleted'),
        );
        // The repo is still where it was.
        expect(repoA.existsSync(), isTrue);
        expect(ticketDir.existsSync(), isTrue);
        expect(log, isNot(contains('Change to the workspace root')));
      },
    );

    test('moves a repo that lost its folder without complaining', () async {
      // A repo dir that no longer exists (e.g. removed by hand) — the
      // cleanup skips the move and still deletes the ticket.
      final repoA = repo('ggsuite', 'a');
      repoA.deleteSync(recursive: true);

      await cleanUpTicket(
        ticketDir: ticketDir,
        repoDirs: [repoA],
        deleteRemoteBranch: true,
        ggLog: messages.add,
        taskLog: taskMessages.add,
        processRunner: okRunner,
      );

      expect(ticketDir.existsSync(), isFalse);
      expect(messages.join('\n'), isNot(contains('Failed')));
    });

    test('moves the code-workspace file when a failure keeps the ticket',
        () async {
      // The workspace file move failure path: make the trash target
      // uncreatable by occupying `.trash` with a file.
      repo('ggsuite', 'a');
      File(
        path.join(ticketDir.path, 'T1.code-workspace'),
      ).writeAsStringSync('{}');
      File(path.join(root.path, '.trash')).writeAsStringSync('blocker');

      await cleanUpTicket(
        ticketDir: ticketDir,
        repoDirs: [Directory(path.join(ticketDir.path, 'ggsuite', 'a'))],
        deleteRemoteBranch: false,
        ggLog: messages.add,
        taskLog: taskMessages.add,
        processRunner: okRunner,
      );

      final log = messages.join('\n');
      expect(log, contains('Failed to move repository a'));
      expect(log, contains('Failed to move the VS Code workspace of T1'));
      expect(log, contains('Ticket T1 was not deleted'));
      expect(ticketDir.existsSync(), isTrue);
    });
  });
}
