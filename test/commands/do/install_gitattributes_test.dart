// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:kidney_core/src/commands/do/install_gitattributes.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../rm_console_colors_helper.dart';

void main() {
  group('DoInstallGitattributesCommand (ticket-wide)', () {
    late Directory tempDir;
    late Directory ticketsDir;
    late Directory ticketDir;
    final messages = <String>[];

    void ggLog(String msg) => messages.add(rmConsoleColors(msg));

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync(
        'do_install_gitattributes_ticket_test_',
      );
      ticketsDir = Directory(path.join(tempDir.path, 'tickets'))..createSync();
      ticketDir = Directory(path.join(ticketsDir.path, 'TICKG'))..createSync();
      for (final name in <String>['A', 'B']) {
        final repoDir = Directory(path.join(ticketDir.path, name))
          ..createSync();
        File(path.join(repoDir.path, 'pubspec.yaml')).writeAsStringSync(
          'name: $name',
        );
      }
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('fails outside any ticket folder', () async {
      final runner = CommandRunner<void>('test', 'do install-gitattributes')
        ..addCommand(
          DoInstallGitattributesCommand(ggLog: ggLog),
        );

      await expectLater(
        () async => runner.run(
          <String>['install-gitattributes', '--input', tempDir.path],
        ),
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

      final runner = CommandRunner<void>('test', 'do install-gitattributes')
        ..addCommand(
          DoInstallGitattributesCommand(ggLog: ggLog),
        );

      await runner.run(
        <String>['install-gitattributes', '--input', emptyTicket.path],
      );

      expect(
        messages,
        contains('⚠️ No repositories found in ticket EMPTY.'),
      );
    });

    test('creates .gitattributes in repositories that lack it', () async {
      final runner = CommandRunner<void>('test', 'do install-gitattributes')
        ..addCommand(
          DoInstallGitattributesCommand(ggLog: ggLog),
        );

      await runner.run(
        <String>['install-gitattributes', '--input', ticketDir.path],
      );

      for (final name in <String>['A', 'B']) {
        final file = File(
          path.join(ticketDir.path, name, '.gitattributes'),
        );
        expect(file.existsSync(), isTrue);
        expect(file.readAsStringSync(), '$gitattributesEolLine\n');
        expect(messages, contains('Created .gitattributes in $name.'));
      }

      expect(
        messages,
        contains(
          '✅ Ensured .gitattributes for all repositories in ticket TICKG.',
        ),
      );
    });

    test('leaves an existing .gitattributes with the rule untouched', () async {
      final file = File(
        path.join(ticketDir.path, 'A', '.gitattributes'),
      );
      const original = '# header\n$gitattributesEolLine\n';
      file.writeAsStringSync(original);
      final originalMtime = file.lastModifiedSync();

      final runner = CommandRunner<void>('test', 'do install-gitattributes')
        ..addCommand(
          DoInstallGitattributesCommand(ggLog: ggLog),
        );

      await runner.run(
        <String>['install-gitattributes', '--input', ticketDir.path],
      );

      expect(file.readAsStringSync(), original);
      expect(
        messages.any((m) => m == 'Created .gitattributes in A.'),
        isFalse,
      );
      expect(
        messages.any((m) => m == 'Updated .gitattributes in A.'),
        isFalse,
      );
      // File should not have been rewritten.
      expect(file.lastModifiedSync(), originalMtime);
    });

    test('appends the rule when .gitattributes exists without it', () async {
      final fileA = File(
        path.join(ticketDir.path, 'A', '.gitattributes'),
      )..writeAsStringSync('*.png binary\n');
      final fileB = File(
        path.join(ticketDir.path, 'B', '.gitattributes'),
      )..writeAsStringSync('*.png binary');

      final runner = CommandRunner<void>('test', 'do install-gitattributes')
        ..addCommand(
          DoInstallGitattributesCommand(ggLog: ggLog),
        );

      await runner.run(
        <String>['install-gitattributes', '--input', ticketDir.path],
      );

      expect(
        fileA.readAsStringSync(),
        '*.png binary\n$gitattributesEolLine\n',
      );
      expect(
        fileB.readAsStringSync(),
        '*.png binary\n$gitattributesEolLine\n',
      );
      expect(messages, contains('Updated .gitattributes in A.'));
      expect(messages, contains('Updated .gitattributes in B.'));
    });

    test('exec() is equivalent to running the command', () async {
      await DoInstallGitattributesCommand(ggLog: ggLog).exec(
        directory: ticketDir,
        ggLog: ggLog,
      );

      for (final name in <String>['A', 'B']) {
        final file = File(
          path.join(ticketDir.path, name, '.gitattributes'),
        );
        expect(file.existsSync(), isTrue);
      }
    });
  });
}
