// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_multi/src/backend/constants.dart';
import 'package:gg_multi/src/commands/do/rm/ticket.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('RemoveTicketCommand', () {
    late Directory tempDir; // workspace root
    late Directory ticketDir;
    final messages = <String>[];
    final coloredMessages = <String>[];
    final gitCalls = <String>[];

    void ggLog(String message) {
      coloredMessages.add(message);
      messages.add(rmControls(message));
    }

    Future<ProcessResult> processRunner(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
    }) async {
      gitCalls.add(
        '${path.basename(workingDirectory!)}: ${arguments.join(' ')}',
      );
      return ProcessResult(0, 0, '', '');
    }

    CommandRunner<void> runnerAt(String rootPath) {
      return CommandRunner<void>('test', 'RemoveTicketCommand Test')
        ..addCommand(
          RemoveTicketCommand(
            ggLog: ggLog,
            rootPath: rootPath,
            processRunner: processRunner,
          ),
        );
    }

    Directory repo(String org, String name) {
      final dir = Directory(path.join(ticketDir.path, org, name))
        ..createSync(recursive: true);
      File(path.join(dir.path, 'pubspec.yaml'))
          .writeAsStringSync('name: $name\nversion: 1.0.0\n');
      return dir;
    }

    setUp(() {
      messages.clear();
      coloredMessages.clear();
      gitCalls.clear();
      tempDir = Directory.systemTemp.createTempSync('rm_ticket_test_');
      ticketDir = Directory(
        path.join(tempDir.path, ggMultiTicketFolder, 'T88'),
      )..createSync(recursive: true);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('describes itself', () {
      final command = RemoveTicketCommand(ggLog: ggLog, rootPath: '/tmp');
      expect(command.name, 'ticket');
      expect(
        command.description,
        'Move the current ticket to the trash and delete its remote branches',
      );
    });

    test('refuses outside a ticket folder', () async {
      await expectLater(
        runnerAt(tempDir.path).run(['ticket']),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'message',
            contains('must be called inside a ticket folder'),
          ),
        ),
      );
    });

    test(
        'deletes the remote branches, moves the whole ticket to the trash '
        'and prints the way to the workspace root in blue', () async {
      repo('ggsuite', 'a');
      repo('ggsuite', 'b');
      File(path.join(ticketDir.path, 'T88.code-workspace'))
          .writeAsStringSync('{}');

      await runnerAt(ticketDir.path).run(['ticket']);

      expect(gitCalls, [
        'a: push origin --delete T88',
        'b: push origin --delete T88',
      ]);

      final trash = path.join(tempDir.path, ggMultiTrashFolder, 'T88');
      expect(
        Directory(path.join(trash, 'ggsuite', 'a')).existsSync(),
        isTrue,
      );
      expect(
        Directory(path.join(trash, 'ggsuite', 'b')).existsSync(),
        isTrue,
      );
      expect(File(path.join(trash, 'T88.code-workspace')).existsSync(), isTrue);
      expect(ticketDir.existsSync(), isFalse);

      expect(
        messages.join('\n'),
        contains('Change to the workspace root with:'),
      );
      expect(coloredMessages.last, cCmd('  cd ${tempDir.absolute.path}'));
    });

    test('--no-delete-remote-branch keeps the remote branches', () async {
      repo('ggsuite', 'a');

      await runnerAt(ticketDir.path)
          .run(['ticket', '--no-delete-remote-branch']);

      expect(gitCalls, isEmpty);
      expect(
        messages.join('\n'),
        contains('Kept remote branch T88 for a.'),
      );
      expect(ticketDir.existsSync(), isFalse);
    });

    test('works from a sub-folder of the ticket', () async {
      final repoDir = repo('ggsuite', 'a');
      final subDir = Directory(path.join(repoDir.path, 'lib'))
        ..createSync(recursive: true);

      await runnerAt(subDir.path).run(['ticket']);

      expect(ticketDir.existsSync(), isFalse);
      expect(
        Directory(
          path.join(tempDir.path, ggMultiTrashFolder, 'T88', 'ggsuite', 'a'),
        ).existsSync(),
        isTrue,
      );
    });
  });
}
