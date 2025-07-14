// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:kidney_core/src/commands/can/push.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:gg/gg.dart';

import '../../rm_console_colors_helper.dart';

class FakeCanPush extends Fake implements CanPush {
  FakeCanPush({List<bool>? results}) : _results = results ?? [];

  final List<bool> _results;
  int _idx = 0;

  @override
  Future<void> exec({
    required Directory directory,
    required Function ggLog,
    bool? force,
    bool? saveState,
  }) async {
    if (_idx < _results.length && !_results[_idx]) {
      _idx++;
      throw Exception('${directory.path} failed');
    }
    _idx++;
    return;
  }
}

void main() {
  late Directory tempDir;
  late Directory ticketsDir;
  late Directory ticketDir;
  final messages = <String>[];

  void ggLog(String msg) => messages.add(rmConsoleColors(msg));

  setUp(() {
    messages.clear();
    tempDir = Directory.systemTemp.createTempSync('can_push_ticket_test_');
    ticketsDir = Directory(path.join(tempDir.path, 'tickets'))..createSync();
    ticketDir = Directory(path.join(ticketsDir.path, 'TICKP'))..createSync();
    Directory(path.join(ticketDir.path, 'A')).createSync();
    Directory(path.join(ticketDir.path, 'B')).createSync();
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('CanPushCommand (ticket-wide)', () {
    test('fails outside any ticket folder', () async {
      final runner = CommandRunner<void>('test', 'can push ticket')
        ..addCommand(
          CanPushCommand(
            ggLog: ggLog,
            executionPath: tempDir.path,
          ),
        );
      await runner.run(['push']);
      expect(
        messages,
        contains('This command must be executed inside a ticket folder.'),
      );
    });

    test('logs when there are no repositories', () async {
      final emptyTicket = Directory(path.join(ticketsDir.path, 'EMPTY'))
        ..createSync();
      final runner = CommandRunner<void>('test', 'can push ticket')
        ..addCommand(
          CanPushCommand(
            ggLog: ggLog,
            executionPath: emptyTicket.path,
          ),
        );
      await runner.run(['push']);
      expect(
        messages,
        contains('No repositories found in ticket EMPTY.'),
      );
    });

    test('pushes all repos successfully', () async {
      final fakePush = FakeCanPush(results: [true, true]);
      final runner = CommandRunner<void>('test', 'can push ticket')
        ..addCommand(
          CanPushCommand(
            ggLog: ggLog,
            executionPath: ticketDir.path,
            ggCanPush: fakePush,
          ),
        );
      await runner.run(['push']);
      expect(
        messages,
        contains('All repositories in ticket TICKP can be pushed.'),
      );
      expect(
        messages,
        contains('Checking if A in ticket TICKP can be pushed...'),
      );
      expect(
        messages,
        contains('Checking if B in ticket TICKP can be pushed...'),
      );
    });

    test('aborts on first repo that fails', () async {
      final fakePush = FakeCanPush(results: [true, false, true]);
      final runner = CommandRunner<void>('test', 'can push ticket')
        ..addCommand(
          CanPushCommand(
            ggLog: ggLog,
            executionPath: ticketDir.path,
            ggCanPush: fakePush,
          ),
        );
      await expectLater(
        () async => await runner.run(['push']),
        throwsA(isA<Exception>()),
      );
      expect(
        messages,
        contains('Cannot push B: Exception: '
            '${path.join(ticketDir.path, 'B')} failed'),
      );
      expect(messages.any((m) => m.contains('All repositories')), isFalse);
    });
  });
}
