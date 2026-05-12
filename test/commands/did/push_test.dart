// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:gg_multi/src/commands/did/push.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../rm_console_colors_helper.dart';

class MockGgDidPush extends Mock implements gg.DidPush {}

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
    tempDir = Directory.systemTemp.createTempSync('did_push_ticket_test_');
    ticketsDir = Directory(path.join(tempDir.path, 'tickets'))..createSync();
    ticketDir = Directory(path.join(ticketsDir.path, 'TICKDP'))..createSync();
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

  group('DidPushCommand (ticket-wide)', () {
    test('fails outside any ticket folder', () async {
      final runner = CommandRunner<void>('test', 'did push ticket')
        ..addCommand(
          DidPushCommand(
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
      final runner = CommandRunner<void>('test', 'did push ticket')
        ..addCommand(
          DidPushCommand(
            ggLog: ggLog,
          ),
        );
      await runner.run(['push', '--input', emptyTicket.path]);
      expect(
        messages,
        contains('⚠️ No repositories found in ticket EMPTY.'),
      );
    });

    test('checks all repos successfully', () async {
      final mockGgDidPush = MockGgDidPush();

      when(
        () => mockGgDidPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => true);

      final runner = CommandRunner<void>('test', 'did push ticket')
        ..addCommand(
          DidPushCommand(
            ggLog: ggLog,
            ggDidPush: mockGgDidPush,
          ),
        );
      await runner.run(['push', '--input', ticketDir.path]);
      expect(
        messages,
        contains('✅ All repositories in ticket TICKDP were pushed.'),
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
      final mockGgDidPush = MockGgDidPush();

      when(
        () => mockGgDidPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((invocation) async {
        final repoDir = invocation.namedArguments[#directory] as Directory;
        if (path.basename(repoDir.path) == 'B') {
          throw Exception('Failed did push for B');
        }
        return false;
      });

      final runner = CommandRunner<void>('test', 'did push ticket')
        ..addCommand(
          DidPushCommand(
            ggLog: ggLog,
            ggDidPush: mockGgDidPush,
          ),
        );
      await expectLater(
        () async => await runner.run(['push', '--input', ticketDir.path]),
        throwsA(isA<Exception>()),
      );
      expect(
        messages,
        contains('❌ B was not pushed: Exception: Failed did push for B'),
      );
    });
  });
}
