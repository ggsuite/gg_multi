// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:gg/gg.dart' as gg;
import 'package:kidney_core/src/backend/constants.dart';
import 'package:kidney_core/src/commands/can/push.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../rm_console_colors_helper.dart';

class MockGgCanPush extends Mock implements gg.CanPush {}

void main() {
  group('CanPushCommand', () {
    late Directory tempDir;
    late Directory ticketDir;
    late CommandRunner<void> runner;
    final messages = <String>[];
    late MockGgCanPush mockGgCanPush;

    void ggLog(String message) {
      messages.add(rmConsoleColors(message));
    }

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('can_push_test_');
      ticketDir = Directory(path.join(tempDir.path, kidneyTicketFolder, 'T1'))
        ..createSync(recursive: true);
      mockGgCanPush = MockGgCanPush();
      runner = CommandRunner<void>('test', 'Test CanPushCommand')
        ..addCommand(
          CanPushCommand(ggLog: ggLog),
        );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('throws when not inside a ticket folder', () async {
      // Execute outside of a ticket folder
      final nonTicketDir = Directory(path.join(tempDir.path, 'outside'))
        ..createSync(recursive: true);
      final localRunner = CommandRunner<void>('test', 'Test CanPushCommand')
        ..addCommand(
          CanPushCommand(ggLog: ggLog),
        );

      Directory.current = nonTicketDir;
      await expectLater(
        localRunner.run(['push']),
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
      await runner.run(['push']);
      expect(messages, contains('No repositories found in ticket T1.'));
    });

    test('successfully checks all repositories in ticket folder', () async {
      // Mock gg.CanPush to succeed
      when(
        () => mockGgCanPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      // Replace the real gg.CanPush with the mock in a local runner
      final localRunner = CommandRunner<void>('test', 'Test CanPushCommand')
        ..addCommand(
          CanPushCommand(ggLog: ggLog),
        );

      Directory.current = ticketDir;
      await localRunner.run(['push']);

      expect(
        messages,
        contains('Checking if repo1 in ticket T1 can be pushed...'),
      );
      expect(
        messages,
        contains('Checking if repo2 in ticket T1 can be pushed...'),
      );
      expect(
        messages,
        contains('✅ repo1 in ticket T1 can be pushed.'),
      );
      expect(
        messages,
        contains('✅ repo2 in ticket T1 can be pushed.'),
      );
      expect(
        messages,
        contains('All repositories in ticket T1 can be pushed.'),
      );
    });

    test('throws when some repositories fail the push check', () async {
      // Create some repositories inside the ticket folder
      final repo1 = Directory(path.join(ticketDir.path, 'repo1'))..createSync();
      final repo2 = Directory(path.join(ticketDir.path, 'repo2'))..createSync();

      // Mock gg.CanPush to succeed for repo1 and fail for repo2
      when(
        () => mockGgCanPush.exec(
          directory: repo1,
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockGgCanPush.exec(
          directory: repo2,
          ggLog: any(named: 'ggLog'),
        ),
      ).thenThrow(Exception('Failed to push repo2'));

      // Replace the real gg.CanPush with the mock in a local runner
      final localRunner = CommandRunner<void>('test', 'Test CanPushCommand')
        ..addCommand(
          CanPushCommand(ggLog: ggLog),
        );

      Directory.current = ticketDir;
      await expectLater(
        localRunner.run(['push']),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Some repositories in ticket T1 cannot be pushed.'),
          ),
        ),
      );

      expect(
        messages,
        contains('Checking if repo1 in ticket T1 can be pushed...'),
      );
      expect(
        messages,
        contains('Checking if repo2 in ticket T1 can be pushed...'),
      );
      expect(
        messages,
        contains('✅ repo1 in ticket T1 can be pushed.'),
      );
      expect(
        messages,
        contains('❌ repo2 in ticket T1 cannot be pushed: '
            'Exception: Failed to push repo2'),
      );
    });
  });
}
