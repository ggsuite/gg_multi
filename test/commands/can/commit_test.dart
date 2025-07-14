// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:gg/gg.dart' as gg;
import 'package:kidney_core/src/backend/constants.dart';
import 'package:kidney_core/src/commands/can/commit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../rm_console_colors_helper.dart';

class MockGgCanCommit extends Mock implements gg.CanCommit {}

void main() {
  group('CanCommitCommand', () {
    late Directory tempDir;
    late Directory ticketDir;
    late CommandRunner<void> runner;
    final messages = <String>[];
    late MockGgCanCommit mockGgCanCommit;

    void ggLog(String message) {
      messages.add(rmConsoleColors(message));
    }

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('can_commit_test_');
      ticketDir = Directory(path.join(tempDir.path, kidneyTicketFolder, 'T1'))
        ..createSync(recursive: true);
      mockGgCanCommit = MockGgCanCommit();
      runner = CommandRunner<void>('test', 'Test CanCommitCommand')
        ..addCommand(
          CanCommitCommand(ggLog: ggLog),
        );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('throws when not inside a ticket folder', () async {
      // Execute outside of a ticket folder
      final nonTicketDir = Directory(path.join(tempDir.path, 'outside'))
        ..createSync(recursive: true);
      final localRunner = CommandRunner<void>('test', 'Test CanCommitCommand')
        ..addCommand(
          CanCommitCommand(ggLog: ggLog),
        );

      Directory.current = nonTicketDir;
      await expectLater(
        () async => await localRunner.run(['commit']),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Not inside a ticket folder.'),
          ),
        ),
      );
      expect(
        messages,
        contains('This command must be run inside a ticket folder.'),
      );
    });

    test('logs warning when ticket folder has no repositories', () async {
      Directory.current = ticketDir;
      await runner.run(['commit']);
      expect(messages, contains('No repositories found in ticket T1.'));
    });

    test('successfully checks all repositories in ticket folder', () async {
      // Mock gg.CanCommit to succeed
      when(
        () => mockGgCanCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      // Replace the real gg.CanCommit with the mock in a local runner
      final localRunner = CommandRunner<void>('test', 'Test CanCommitCommand')
        ..addCommand(
          CanCommitCommand(ggLog: ggLog),
        );

      Directory.current = ticketDir;
      await localRunner.run(['commit']);

      expect(
        messages,
        contains('Checking if repo1 in ticket T1 can be committed...'),
      );
      expect(
        messages,
        contains('Checking if repo2 in ticket T1 can be committed...'),
      );
      expect(
        messages,
        contains('✅ repo1 in ticket T1 can be committed.'),
      );
      expect(
        messages,
        contains('✅ repo2 in ticket T1 can be committed.'),
      );
      expect(
        messages,
        contains('All repositories in ticket T1 can be committed.'),
      );
    });

    test('throws when some repositories fail the commit check', () async {
      // Create some repositories inside the ticket folder
      final repo1 = Directory(path.join(ticketDir.path, 'repo1'))..createSync();
      final repo2 = Directory(path.join(ticketDir.path, 'repo2'))..createSync();

      // Mock gg.CanCommit to succeed for repo1 and fail for repo2
      when(
        () => mockGgCanCommit.exec(
          directory: repo1,
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockGgCanCommit.exec(
          directory: repo2,
          ggLog: any(named: 'ggLog'),
        ),
      ).thenThrow(Exception('Failed to commit repo2'));

      // Replace the real gg.CanCommit with the mock in a local runner
      final localRunner = CommandRunner<void>('test', 'Test CanCommitCommand')
        ..addCommand(
          CanCommitCommand(ggLog: ggLog),
        );

      Directory.current = ticketDir;
      await expectLater(
        localRunner.run(['commit']),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Some repositories in ticket T1 cannot be committed.'),
          ),
        ),
      );

      expect(
        messages,
        contains('Checking if repo1 in ticket T1 can be committed...'),
      );
      expect(
        messages,
        contains('Checking if repo2 in ticket T1 can be committed...'),
      );
      expect(
        messages,
        contains('✅ repo1 in ticket T1 can be committed.'),
      );
      expect(
        messages,
        contains('❌ repo2 in ticket T1 cannot be committed: '
            'Exception: Failed to commit repo2'),
      );
    });
  });
}
