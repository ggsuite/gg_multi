// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:gg_multi/src/commands/can/commit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../rm_console_colors_helper.dart';

class MockGgCanCommit extends Mock implements gg.CanCommit {}

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
    tempDir = Directory.systemTemp.createTempSync('can_commit_ticket_test_');
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

  group('CanCommitCommand (ticket-wide)', () {
    test('fails outside any ticket folder', () async {
      final runner = CommandRunner<void>('test', 'can commit ticket')
        ..addCommand(
          CanCommitCommand(
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
      final runner = CommandRunner<void>('test', 'can commit ticket')
        ..addCommand(
          CanCommitCommand(
            ggLog: ggLog,
          ),
        );
      await runner.run(['commit', '--input', emptyTicket.path]);
      expect(
        messages,
        contains('⚠️ No repos in this ticket'),
      );
    });

    test('checks all repos successfully (parallel default)', () async {
      final mockGgCanCommit = MockGgCanCommit();

      when(
        () => mockGgCanCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      final runner = CommandRunner<void>('test', 'can commit ticket')
        ..addCommand(
          CanCommitCommand(
            ggLog: ggLog,
            ggCanCommit: mockGgCanCommit,
          ),
        );
      await runner.run(['commit', '--input', ticketDir.path]);
      expect(messages, contains('✅ All repos can be committed'));
      // GgStatusPrinter prints success lines per repo (with carriage-return
      // prefix when running sequentially; in parallel mode useCarriageReturn
      // is forced off, so the prefix is empty).
      expect(messages, contains('✅ Can commit: A'));
      expect(messages, contains('✅ Can commit: B'));
    });

    test('continues on failure and reports all failed repos at the end',
        () async {
      final mockGgCanCommit = MockGgCanCommit();

      when(
        () => mockGgCanCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((invocation) async {
        final repoDir = invocation.namedArguments[#directory] as Directory;
        if (path.basename(repoDir.path) == 'B') {
          throw Exception('Failed to commit B');
        }
      });

      final runner = CommandRunner<void>('test', 'can commit ticket')
        ..addCommand(
          CanCommitCommand(
            ggLog: ggLog,
            ggCanCommit: mockGgCanCommit,
          ),
        );
      await expectLater(
        () async => await runner.run(['commit', '--input', ticketDir.path]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Cannot commit: B'),
          ),
        ),
      );

      // A must still have been processed successfully despite B failing.
      expect(messages, contains('✅ Can commit: A'));
      expect(messages, contains('❌ Can commit: B'));
      expect(
        messages,
        contains('❌ 1 of 2 repos cannot be committed:'),
      );
      expect(
        messages,
        contains(' - B: Exception: Failed to commit B'),
      );
    });

    test('does not leak gg can commit sub-output without --verbose', () async {
      final mockGgCanCommit = MockGgCanCommit();

      when(
        () => mockGgCanCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((invocation) async {
        final inner = invocation.namedArguments[#ggLog] as void Function(
          String,
        );
        // Simulate noisy inner output.
        inner('Analyze');
        inner('Format');
      });

      final runner = CommandRunner<void>('test', 'can commit ticket')
        ..addCommand(
          CanCommitCommand(
            ggLog: ggLog,
            ggCanCommit: mockGgCanCommit,
          ),
        );
      await runner.run(['commit', '--input', ticketDir.path]);

      // No prefixed inner lines should appear in the captured messages.
      expect(messages, isNot(contains('[A] Analyze')));
      expect(messages, isNot(contains('[B] Format')));
    });

    test('forwards prefixed sub-output with --verbose', () async {
      final mockGgCanCommit = MockGgCanCommit();

      when(
        () => mockGgCanCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((invocation) async {
        final inner = invocation.namedArguments[#ggLog] as void Function(
          String,
        );
        inner('Analyze');
      });

      final runner = CommandRunner<void>('test', 'can commit ticket')
        ..addCommand(
          CanCommitCommand(
            ggLog: ggLog,
            ggCanCommit: mockGgCanCommit,
          ),
        );
      await runner.run([
        'commit',
        '--input',
        ticketDir.path,
        '--verbose',
      ]);

      expect(messages, contains('[A] Analyze'));
      expect(messages, contains('[B] Analyze'));
    });

    test('respects -j 1 (sequential)', () async {
      final inFlight = <String>{};
      var maxObservedInFlight = 0;
      final mockGgCanCommit = MockGgCanCommit();

      when(
        () => mockGgCanCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((invocation) async {
        final repoDir = invocation.namedArguments[#directory] as Directory;
        final name = path.basename(repoDir.path);
        inFlight.add(name);
        if (inFlight.length > maxObservedInFlight) {
          maxObservedInFlight = inFlight.length;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight.remove(name);
      });

      final runner = CommandRunner<void>('test', 'can commit ticket')
        ..addCommand(
          CanCommitCommand(
            ggLog: ggLog,
            ggCanCommit: mockGgCanCommit,
          ),
        );
      await runner.run([
        'commit',
        '--input',
        ticketDir.path,
        '-j',
        '1',
      ]);

      expect(maxObservedInFlight, equals(1));
      expect(messages, contains('✅ All repos can be committed'));
    });

    test('runs in parallel with default -j (>1 in flight observed)', () async {
      final inFlight = <String>{};
      var maxObservedInFlight = 0;
      final mockGgCanCommit = MockGgCanCommit();

      when(
        () => mockGgCanCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((invocation) async {
        final repoDir = invocation.namedArguments[#directory] as Directory;
        final name = path.basename(repoDir.path);
        inFlight.add(name);
        if (inFlight.length > maxObservedInFlight) {
          maxObservedInFlight = inFlight.length;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
        inFlight.remove(name);
      });

      final runner = CommandRunner<void>('test', 'can commit ticket')
        ..addCommand(
          CanCommitCommand(
            ggLog: ggLog,
            ggCanCommit: mockGgCanCommit,
          ),
        );
      await runner.run(['commit', '--input', ticketDir.path]);

      expect(maxObservedInFlight, greaterThan(1));
    });
  });
}
