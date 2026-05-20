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
    tempDir = Directory.systemTemp.createTempSync('do_push_ticket_test_');
    ticketsDir = Directory(path.join(tempDir.path, 'tickets'))..createSync();
    ticketDir = Directory(path.join(ticketsDir.path, 'TICKP'))..createSync();
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
          DoPushCommand(ggLog: ggLog),
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
          DoPushCommand(ggLog: ggLog),
        );
      await runner.run(['push', '--input', emptyTicket.path]);
      expect(messages, contains('⚠️ No repos in this ticket'));
    });

    test('pushes all repos successfully (parallel default)', () async {
      final mockGgDoPush = MockGgDoPush();
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
            ggDoPush: mockGgDoPush,
          ),
        );
      await runner.run(['push', '--input', ticketDir.path]);

      expect(messages, contains('Pushing the following repos:'));
      expect(messages, contains(' - A'));
      expect(messages, contains(' - B'));
      expect(messages, contains('✅ Pushing: A'));
      expect(messages, contains('✅ Pushing: B'));
      expect(messages, contains('✅ All repos pushed'));
    });

    test('continues on failure and reports all failed repos at the end',
        () async {
      final mockGgDoPush = MockGgDoPush();
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
            ggDoPush: mockGgDoPush,
          ),
        );
      await expectLater(
        () async => await runner.run([
          'push',
          '--input',
          ticketDir.path,
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Failed to push: B'),
          ),
        ),
      );

      // A still succeeded.
      expect(messages, contains('✅ Pushing: A'));
      expect(messages, contains('❌ Pushing: B'));
      expect(
        messages,
        contains('❌ 1 of 2 repos failed to push:'),
      );
      expect(
        messages,
        contains(' - B: Exception: Failed to push B'),
      );
    });

    test('forwards --force to gg.DoPush', () async {
      final mockGgDoPush = MockGgDoPush();
      final forceValues = <bool?>[];
      when(
        () => mockGgDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((invocation) async {
        forceValues.add(invocation.namedArguments[#force] as bool?);
      });

      final runner = CommandRunner<void>('test', 'do push ticket')
        ..addCommand(
          DoPushCommand(
            ggLog: ggLog,
            ggDoPush: mockGgDoPush,
          ),
        );
      await runner.run([
        'push',
        '--input',
        ticketDir.path,
        '--force',
      ]);

      expect(forceValues, everyElement(isTrue));
    });

    test('does not leak gg do push sub-output without --verbose', () async {
      final mockGgDoPush = MockGgDoPush();
      when(
        () => mockGgDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((invocation) async {
        final inner = invocation.namedArguments[#ggLog] as void Function(
          String,
        );
        inner('Pushing to origin');
      });

      final runner = CommandRunner<void>('test', 'do push ticket')
        ..addCommand(
          DoPushCommand(
            ggLog: ggLog,
            ggDoPush: mockGgDoPush,
          ),
        );
      await runner.run(['push', '--input', ticketDir.path]);

      expect(messages, isNot(contains('[A] Pushing to origin')));
      expect(messages, isNot(contains('[B] Pushing to origin')));
    });

    test('forwards prefixed sub-output with --verbose', () async {
      final mockGgDoPush = MockGgDoPush();
      when(
        () => mockGgDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((invocation) async {
        final inner = invocation.namedArguments[#ggLog] as void Function(
          String,
        );
        inner('Pushing to origin');
      });

      final runner = CommandRunner<void>('test', 'do push ticket')
        ..addCommand(
          DoPushCommand(
            ggLog: ggLog,
            ggDoPush: mockGgDoPush,
          ),
        );
      await runner.run([
        'push',
        '--input',
        ticketDir.path,
        '--verbose',
      ]);

      expect(messages, contains('[A] Pushing to origin'));
      expect(messages, contains('[B] Pushing to origin'));
    });

    test('respects -j 1 (sequential)', () async {
      final inFlight = <String>{};
      var maxObservedInFlight = 0;
      final mockGgDoPush = MockGgDoPush();
      when(
        () => mockGgDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
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

      final runner = CommandRunner<void>('test', 'do push ticket')
        ..addCommand(
          DoPushCommand(
            ggLog: ggLog,
            ggDoPush: mockGgDoPush,
          ),
        );
      await runner.run([
        'push',
        '--input',
        ticketDir.path,
        '-j',
        '1',
      ]);

      expect(maxObservedInFlight, equals(1));
      expect(messages, contains('✅ All repos pushed'));
    });

    test('runs in parallel with default -j (>1 in flight observed)', () async {
      final inFlight = <String>{};
      var maxObservedInFlight = 0;
      final mockGgDoPush = MockGgDoPush();
      when(
        () => mockGgDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
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

      final runner = CommandRunner<void>('test', 'do push ticket')
        ..addCommand(
          DoPushCommand(
            ggLog: ggLog,
            ggDoPush: mockGgDoPush,
          ),
        );
      await runner.run(['push', '--input', ticketDir.path]);

      expect(maxObservedInFlight, greaterThan(1));
    });
  });
}
