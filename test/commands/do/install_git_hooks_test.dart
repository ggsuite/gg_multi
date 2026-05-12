// @license
// Copyright (c) 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_multi/src/commands/do/install_git_hooks.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../rm_console_colors_helper.dart';

void main() {
  group('DoInstallGitHooksCommand (ticket-wide)', () {
    late Directory tempDir;
    late Directory ticketsDir;
    late Directory ticketDir;
    final messages = <String>[];

    void ggLog(String msg) => messages.add(rmConsoleColors(msg));

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync(
        'do_install_git_hooks_ticket_test_',
      );
      ticketsDir = Directory(path.join(tempDir.path, 'tickets'))..createSync();
      ticketDir = Directory(path.join(ticketsDir.path, 'TICKH'))..createSync();
      // Create repositories with pubspec.yaml so SortedProcessingList
      // detects them as Dart packages.
      for (final name in <String>['A', 'B']) {
        final repoDir = Directory(path.join(ticketDir.path, name))
          ..createSync();
        File(path.join(repoDir.path, 'pubspec.yaml')).writeAsStringSync(
          'name: $name',
        );
        // Create a .git directory so the command will install hooks.
        Directory(path.join(repoDir.path, '.git')).createSync();
      }
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('fails outside any ticket folder', () async {
      final runner = CommandRunner<void>('test', 'do install-git-hooks')
        ..addCommand(
          DoInstallGitHooksCommand(ggLog: ggLog),
        );

      await expectLater(
        () async => runner.run(
          <String>['install-git-hooks', '--input', tempDir.path],
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            'Exception: Not inside a ticket folder',
          ),
        ),
      );

      expect(
        messages,
        contains('This command must be executed inside a ticket folder.'),
      );
    });

    test('logs when there are no repositories', () async {
      final emptyTicket = Directory(path.join(ticketsDir.path, 'EMPTY'))
        ..createSync();

      final runner = CommandRunner<void>('test', 'do install-git-hooks')
        ..addCommand(
          DoInstallGitHooksCommand(ggLog: ggLog),
        );

      await runner.run(
        <String>['install-git-hooks', '--input', emptyTicket.path],
      );

      expect(
        messages,
        contains('⚠️ No repos in this ticket'),
      );
    });

    test('installs pre-push and verify_push.dart for all repos', () async {
      final runner = CommandRunner<void>('test', 'do install-git-hooks')
        ..addCommand(
          DoInstallGitHooksCommand(ggLog: ggLog),
        );

      await runner.run(
        <String>['install-git-hooks', '--input', ticketDir.path],
      );

      for (final name in <String>['A', 'B']) {
        final repoDir = path.join(ticketDir.path, name);
        final prePush = File(
          path.join(repoDir, '.git', 'hooks', 'pre-push'),
        );
        final verifyPush = File(
          path.join(repoDir, '.gg', 'verify_push.dart'),
        );

        expect(prePush.existsSync(), isTrue);
        expect(verifyPush.existsSync(), isTrue);

        // Ensure files are not empty so we know something was written.
        expect(prePush.lengthSync(), greaterThan(0));
        expect(verifyPush.lengthSync(), greaterThan(0));
      }

      expect(
        messages,
        contains(
          '✅ Installed git hooks for all repositories in ticket TICKH.',
        ),
      );
    });

    test('skips repositories without a .git directory', () async {
      final repoDir = Directory(path.join(ticketDir.path, 'C'))..createSync();
      File(path.join(repoDir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: C',
      );

      final runner = CommandRunner<void>('test', 'do install-git-hooks')
        ..addCommand(
          DoInstallGitHooksCommand(ggLog: ggLog),
        );

      await runner.run(
        <String>['install-git-hooks', '--input', ticketDir.path],
      );

      final prePush = File(
        path.join(repoDir.path, '.git', 'hooks', 'pre-push'),
      );
      final verifyPush = File(
        path.join(repoDir.path, '.gg', 'verify_push.dart'),
      );

      expect(prePush.existsSync(), isFalse);
      expect(verifyPush.existsSync(), isFalse);
      expect(
        messages,
        contains(
          'Skipping C because no .git directory was found.',
        ),
      );
    });
  });
}
