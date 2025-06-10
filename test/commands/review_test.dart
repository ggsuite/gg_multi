// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as path;
import 'package:args/command_runner.dart';
import 'package:kidney_core/src/commands/review.dart';

import '../rm_console_colors_helper.dart';

String Function(String) get basename => path.basename;

typedef Calls = List<Map<String, Object?>>;

Future<ProcessResult> fakeProcSuccess(
  String exe,
  List<String> args, {
  String? workingDirectory,
}) async =>
    ProcessResult(0, 0, '', '');

void main() {
  group('ReviewCommand', () {
    late Directory tempDir;
    late List<String> logMessages;

    void ggLog(String message) {
      logMessages.add(rmConsoleColors(message));
    }

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('review_test_');
      logMessages = <String>[];
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('fails outside any ticket folder', () async {
      final runner = CommandRunner<void>('test', 'test review')
        ..addCommand(
          ReviewCommand(
            ggLog: ggLog,
            executionPath: tempDir.path,
            processRunner: fakeProcSuccess,
          ),
        );
      await runner.run(['review']);
      expect(
        logMessages,
        contains('Review must be executed inside a ticket folder.'),
      );
    });

    test('shows uncommitted changes warning for repos', () async {
      final ticket = Directory(path.join(tempDir.path, 'tickets', 'T2'))
        ..createSync(recursive: true);
      final repo1 = Directory(path.join(ticket.path, 'repo1'))..createSync();
      // repo2 is not used, only repo1 used in checks
      // final repo2 = Directory(path.join(ticket.path, 'repo2'))..createSync();

      final calls = <Map<String, Object?>>[];
      Future<ProcessResult> runner(
        String exe,
        List<String> args, {
        String? workingDirectory,
      }) async {
        calls.add({
          'exe': exe,
          'args': args,
          'dir': workingDirectory,
        });
        if (exe == 'git' && (args as List)[0] == 'status') {
          if (workingDirectory == repo1.path) {
            return ProcessResult(100, 0, ' M foo', ''); // modified
          } else {
            return ProcessResult(200, 0, '', '');
          }
        }
        return ProcessResult(0, 0, '', '');
      }

      final runnerCmd = CommandRunner<void>('test', 'review')
        ..addCommand(
          ReviewCommand(
            ggLog: ggLog,
            executionPath: ticket.path,
            processRunner: runner,
          ),
        );
      await runnerCmd.run(['review']);
      expect(
        logMessages,
        contains('Uncommitted changes found in the following repos:'),
      );
      expect(logMessages.any((m) => m.contains('repo1')), isTrue);
      expect(logMessages.last, contains('Please commit or stash your changes'));
    });

    test(
        'runs unlocalize-refs then localize-refs --git '
        'then PR create when all clean', () async {
      final ticket = Directory(path.join(tempDir.path, 'tickets', 'T1'))
        ..createSync(recursive: true);
      Directory(path.join(ticket.path, 'A')).createSync();
      Directory(path.join(ticket.path, 'B')).createSync();
      final calls = <Map<String, Object?>>[];
      Future<ProcessResult> runner(
        String exe,
        List<String> args, {
        String? workingDirectory,
      }) async {
        calls.add({
          'exe': exe,
          'args': args,
          'dir': workingDirectory,
        });
        // Simulate uncommitted check: clean
        if (exe == 'git' && (args as List)[0] == 'status') {
          return ProcessResult(1, 0, '', '');
        }
        // Simulate unlocalize-refs
        if (exe == 'gg_localize_refs' &&
            (args as List).first == 'unlocalize-refs') {
          return ProcessResult(2, 0, '', '');
        }
        // Simulate localize-refs --git
        if (exe == 'gg_localize_refs' &&
            ((args as List).first == 'localize-refs')) {
          return ProcessResult(4, 0, '', '');
        }
        // Simulate PR create
        if (exe == 'gh' && (args as List).take(2).join(' ') == 'pr create') {
          return ProcessResult(3, 0, '', '');
        }
        return ProcessResult(0, 0, '', '');
      }

      final runnerCmd = CommandRunner<void>('test', 'review')
        ..addCommand(
          ReviewCommand(
            ggLog: ggLog,
            executionPath: ticket.path,
            processRunner: runner,
          ),
        );
      await runnerCmd.run(['review']);

      expect(
        calls.where(
          (c) => c['exe'] == 'git' && (c['args'] as List)[0] == 'status',
        ),
        hasLength(2),
      );
      expect(
        calls.where(
          (c) =>
              c['exe'] == 'gg_localize_refs' &&
              (c['args'] as List).first == 'unlocalize-refs',
        ),
        hasLength(2),
      );
      expect(
        calls.where(
          (c) =>
              c['exe'] == 'gg_localize_refs' &&
              (c['args'] as List).first == 'localize-refs',
        ),
        hasLength(2),
      );
      expect(
        calls.where((c) => c['exe'] == 'gh'),
        hasLength(2),
      );
      expect(
        logMessages,
        contains('Unlocalized refs for A'),
      );
      expect(
        logMessages,
        contains('Unlocalized refs for B'),
      );
      expect(
        logMessages,
        contains('Localized refs for A'),
      );
      expect(
        logMessages,
        contains('Localized refs for B'),
      );
      expect(
        logMessages,
        contains('Created PR for A'),
      );
      expect(
        logMessages,
        contains('Created PR for B'),
      );
    });

    test('logs failure of unlocalize-refs and continues', () async {
      final ticket = Directory(path.join(tempDir.path, 'tickets', 'T4'))
        ..createSync(recursive: true);
      Directory(path.join(ticket.path, 'C')).createSync();

      final calls = <Map<String, Object?>>[];
      Future<ProcessResult> runner(
        String exe,
        List<String> args, {
        String? workingDirectory,
      }) async {
        calls.add({
          'exe': exe,
          'args': args,
          'dir': workingDirectory,
        });
        if (exe == 'git' && (args as List)[0] == 'status') {
          return ProcessResult(1, 0, '', '');
        }
        if (exe == 'gg_localize_refs' &&
            (args as List).first == 'unlocalize-refs') {
          return ProcessResult(2, 1, '', 'broken!');
        }
        // PR create never called if unlocalize-refs fails
        return ProcessResult(0, 0, '', '');
      }

      final runnerCmd = CommandRunner<void>('test', 'review')
        ..addCommand(
          ReviewCommand(
            ggLog: ggLog,
            executionPath: ticket.path,
            processRunner: runner,
          ),
        );
      await runnerCmd.run(['review']);
      expect(
        logMessages.last,
        contains('Failed to unlocalize refs for C: Exception: broken!'),
      );
      // There should not be any message about "Created PR for C".
      expect(logMessages.any((m) => m.contains('Created PR for C')), isFalse);
    });

    test('logs failure of gh pr create and continues', () async {
      final ticket = Directory(path.join(tempDir.path, 'tickets', 'T6'))
        ..createSync(recursive: true);
      Directory(path.join(ticket.path, 'D')).createSync();

      final calls = <Map<String, Object?>>[];
      Future<ProcessResult> runner(
        String exe,
        List<String> args, {
        String? workingDirectory,
      }) async {
        calls.add({
          'exe': exe,
          'args': args,
          'dir': workingDirectory,
        });
        if (exe == 'git' && (args as List)[0] == 'status') {
          return ProcessResult(1, 0, '', '');
        }
        if (exe == 'gg_localize_refs') {
          // Always succeed for either unlocalize-refs or localize-refs
          return ProcessResult(2, 0, '', '');
        }
        if (exe == 'gh') {
          return ProcessResult(3, 1, '', 'badpr!');
        }
        return ProcessResult(0, 0, '', '');
      }

      final runnerCmd = CommandRunner<void>('test', 'review')
        ..addCommand(
          ReviewCommand(
            ggLog: ggLog,
            executionPath: ticket.path,
            processRunner: runner,
          ),
        );
      await runnerCmd.run(['review']);
      expect(
        logMessages.last,
        contains('Failed to create PR for D: Exception: badpr!'),
      );
      // There should not be any green message about "Created PR for D".
      expect(logMessages.any((m) => m.contains('Created PR for D')), isFalse);
    });

    test('logs no repositories found when ticket folder is empty', () async {
      // Create the empty ticket directory under tickets
      final ticket = Directory(path.join(tempDir.path, 'tickets', 'T_empty'))
        ..createSync(recursive: true);
      // No repo directories inside ticket directory
      final runner = CommandRunner<void>('test', 'test review')
        ..addCommand(
          ReviewCommand(
            ggLog: ggLog,
            executionPath: ticket.path,
            processRunner: fakeProcSuccess,
          ),
        );
      await runner.run(['review']);
      expect(
        logMessages,
        contains(
          'No repositories found in ticket T_empty.',
        ),
      );
    });
  });
}
