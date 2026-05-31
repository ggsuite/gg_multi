// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:gg_multi/src/commands/do/push.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../rm_console_colors_helper.dart';

class MockGgCanPush extends Mock implements gg.CanPush {}

class MockGgDoPush extends Mock implements gg.DoPush {}

class FakeDirectory extends Fake implements Directory {}

void main() {
  late Directory tempDir;
  late Directory ticketsDir;
  late Directory ticketDir;
  final messages = <String>[];

  setUpAll(() {
    registerFallbackValue(FakeDirectory());
  });

  void ggLog(String msg) => messages.add(rmConsoleColors(msg));

  setUp(() {
    messages.clear();
    tempDir = Directory.systemTemp.createTempSync(
      'do_push_ticket_test_',
    );
    ticketsDir = Directory(path.join(tempDir.path, 'tickets'))..createSync();
    ticketDir = Directory(path.join(ticketsDir.path, 'TICKP'))..createSync();
    // Create repositories with pubspec.yaml so SortedProcessingList finds
    // them
    final aDir = Directory(path.join(ticketDir.path, 'A'))..createSync();
    File(path.join(aDir.path, 'pubspec.yaml')).writeAsStringSync('name: A');
    final bDir = Directory(path.join(ticketDir.path, 'B'))..createSync();
    File(path.join(bDir.path, 'pubspec.yaml')).writeAsStringSync('name: B');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('DoPushCommand (ticket-wide)', () {
    test('fails outside any ticket folder', () async {
      final runner = CommandRunner<void>('test', 'do push ticket')
        ..addCommand(
          DoPushCommand(
            ggLog: ggLog,
          ),
        );
      await expectLater(
        () async => await runner.run(['push', '--input', tempDir.path]),
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
      final runner = CommandRunner<void>('test', 'do push ticket')
        ..addCommand(
          DoPushCommand(
            ggLog: ggLog,
          ),
        );
      await runner.run(['push', '--input', emptyTicket.path]);
      expect(
        messages,
        contains('⚠️ No repos in this ticket'),
      );
    });

    test('pushes all repos successfully (verbose)', () async {
      final mockGgCanPush = MockGgCanPush();
      final mockGgDoPush = MockGgDoPush();

      when(
        () => mockGgCanPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async {});

      final runner = CommandRunner<void>('test', 'do push ticket')
        ..addCommand(
          DoPushCommand(
            ggLog: ggLog,
            ggCanPush: mockGgCanPush,
            ggDoPush: mockGgDoPush,
          ),
        );
      await runner.run([
        'push',
        '--input',
        ticketDir.path,
        '--verbose',
      ]);

      // Status printer message
      expect(
        messages.any((m) => m.contains('Pushing repos')),
        isTrue,
      );

      // Pre-push list
      expect(messages, contains('Pushing the following repos:'));
      expect(messages, contains(' - A'));
      expect(messages, contains(' - B'));

      // Per-repo verbose logs
      expect(
        messages,
        contains('A:'),
      );
      expect(
        messages,
        contains('B:'),
      );

      // Summary
      expect(
        messages,
        contains('✅ All repos pushed'),
      );
    });

    test('aborts on first repo that fails', () async {
      final mockGgCanPush = MockGgCanPush();
      final mockGgDoPush = MockGgDoPush();

      when(
        () => mockGgCanPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((invocation) async {
        final repoDir = invocation.namedArguments[#directory] as Directory;
        if (path.basename(repoDir.path) == 'B') {
          throw Exception('Failed to push B');
        }
      });

      final runner = CommandRunner<void>('test', 'do push ticket')
        ..addCommand(
          DoPushCommand(
            ggLog: ggLog,
            ggCanPush: mockGgCanPush,
            ggDoPush: mockGgDoPush,
          ),
        );
      await expectLater(
        () async => await runner.run([
          'push',
          '--input',
          ticketDir.path,
          '--verbose',
        ]),
        throwsA(isA<Exception>()),
      );
      expect(
        messages,
        contains('❌ Failed to push B: Exception: Failed to push B'),
      );
      expect(messages, contains('❌ Push failed in:'));
      expect(messages.any((m) => m.contains(' - B')), isTrue);
    });

    test('uses quiet taskLog when verbose is false', () async {
      final mockGgCanPush = MockGgCanPush();
      final mockGgDoPush = MockGgDoPush();

      when(
        () => mockGgCanPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async {});

      final localMessages = <String>[];
      void localLog(String msg) => localMessages.add(rmConsoleColors(msg));

      final command = DoPushCommand(
        ggLog: localLog,
        ggCanPush: mockGgCanPush,
        ggDoPush: mockGgDoPush,
      );

      await command.get(
        directory: ticketDir,
        ggLog: localLog,
        force: false,
        verbose: false,
      );

      expect(
        localMessages.last,
        contains(
          '✅ Pushing repos',
        ),
      );
    });
  });
}
