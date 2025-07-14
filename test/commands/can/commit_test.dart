// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:kidney_core/src/commands/can/commit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:gg/gg.dart';

import '../../rm_console_colors_helper.dart';

class FakeCanCommit extends Fake implements CanCommit {
  FakeCanCommit({List<bool>? results}) : _results = results ?? [];

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
    tempDir = Directory.systemTemp.createTempSync('can_commit_ticket_test_');
    ticketsDir = Directory(path.join(tempDir.path, 'tickets'))..createSync();
    ticketDir = Directory(path.join(ticketsDir.path, 'TICK'))..createSync();
    Directory(path.join(ticketDir.path, 'A')).createSync();
    Directory(path.join(ticketDir.path, 'B')).createSync();
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
            executionPath: tempDir.path,
          ),
        );
      await runner.run(['commit']);
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
            executionPath: emptyTicket.path,
          ),
        );
      await runner.run(['commit']);
      expect(
        messages,
        contains('No repositories found in ticket EMPTY.'),
      );
    });

    test('commits all repos successfully', () async {
      final fakeCommit = FakeCanCommit(results: [true, true]);
      final runner = CommandRunner<void>('test', 'can commit ticket')
        ..addCommand(
          CanCommitCommand(
            ggLog: ggLog,
            executionPath: ticketDir.path,
            ggCanCommit: fakeCommit,
          ),
        );
      await runner.run(['commit']);
      expect(
        messages,
        contains('All repositories in ticket TICK can be committed.'),
      );
      expect(
        messages,
        contains('Checking if A in ticket TICK can be committed...'),
      );
      expect(
        messages,
        contains('Checking if B in ticket TICK can be committed...'),
      );
    });

    test('aborts on first repo that fails', () async {
      final fakeCommit = FakeCanCommit(results: [true, false, true]);
      final runner = CommandRunner<void>('test', 'can commit ticket')
        ..addCommand(
          CanCommitCommand(
            ggLog: ggLog,
            executionPath: ticketDir.path,
            ggCanCommit: fakeCommit,
          ),
        );
      await expectLater(
        () async => await runner.run(['commit']),
        throwsA(
          isA<Exception>(),
        ),
      );
      expect(
        messages,
        contains('Cannot commit B: Exception: '
            '${path.join(ticketDir.path, 'B')} failed'),
      );
      expect(messages.any((m) => m.contains('All repositories')), isFalse);
    });
  });
}
