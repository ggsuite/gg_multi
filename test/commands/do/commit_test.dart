// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:gg_multi/src/commands/do/commit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../rm_console_colors_helper.dart';

class MockGgCanCommit extends Mock implements gg.CanCommit {}

class MockGgDoCommit extends Mock implements gg.DoCommit {}

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
    tempDir = Directory.systemTemp.createTempSync('do_commit_ticket_test_');
    ticketsDir = Directory(path.join(tempDir.path, 'tickets'))..createSync();
    ticketDir = Directory(path.join(ticketsDir.path, 'TICKC'))..createSync();
    // Create repositories with pubspec.yaml for SortedProcessingList
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

  group('DoCommitCommand (ticket-wide)', () {
    test('fails outside any ticket folder', () async {
      final runner = CommandRunner<void>('test', 'do commit ticket')
        ..addCommand(
          DoCommitCommand(
            ggLog: ggLog,
          ),
        );
      await expectLater(
        () async => await runner.run(['commit', '--input', tempDir.path]),
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
      final runner = CommandRunner<void>('test', 'do commit ticket')
        ..addCommand(
          DoCommitCommand(
            ggLog: ggLog,
          ),
        );
      await runner.run(['commit', '--input', emptyTicket.path]);
      expect(
        messages,
        contains('⚠️ No repositories found in ticket EMPTY.'),
      );
    });

    test('commits all repos successfully', () async {
      final mockGgCanCommit = MockGgCanCommit();
      final mockGgDoCommit = MockGgDoCommit();

      when(
        () => mockGgCanCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          logType: any(named: 'logType'),
          updateChangeLog: any(named: 'updateChangeLog'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async {});

      final runner = CommandRunner<void>('test', 'do commit ticket')
        ..addCommand(
          DoCommitCommand(
            ggLog: ggLog,
            ggCanCommit: mockGgCanCommit,
            ggDoCommit: mockGgDoCommit,
          ),
        );
      await runner.run(
        ['commit', '--input', ticketDir.path, '--message', 'Test commit'],
      );
      expect(
        messages,
        contains('✅ All repositories in ticket TICKC committed successfully.'),
      );
      expect(
        messages,
        contains('A:'),
      );
      expect(
        messages,
        contains('B:'),
      );
    });

    test('aborts on first repo that fails', () async {
      final mockGgCanCommit = MockGgCanCommit();
      final mockGgDoCommit = MockGgDoCommit();

      when(
        () => mockGgCanCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          logType: any(named: 'logType'),
          updateChangeLog: any(named: 'updateChangeLog'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((invocation) async {
        final repoDir = invocation.namedArguments[#directory] as Directory;
        if (path.basename(repoDir.path) == 'B') {
          throw Exception('Failed to commit B');
        }
      });

      final runner = CommandRunner<void>('test', 'do commit ticket')
        ..addCommand(
          DoCommitCommand(
            ggLog: ggLog,
            ggCanCommit: mockGgCanCommit,
            ggDoCommit: mockGgDoCommit,
          ),
        );
      await expectLater(
        () async => await runner.run(
          ['commit', '--input', ticketDir.path, '--message', 'Test commit'],
        ),
        throwsA(isA<Exception>()),
      );
      expect(
        messages,
        contains('❌ Failed to commit B: Exception: Failed to commit B'),
      );
      expect(
        messages,
        contains(
          '❌ Failed to commit the following repositories in ticket TICKC:',
        ),
      );
      expect(messages.any((m) => m.contains(' - B')), isTrue);
    });
  });
}
