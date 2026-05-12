// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_multi/src/commands/do/install_gitattributes.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../rm_console_colors_helper.dart';

void main() {
  group('DoInstallGitattributesCommand (ticket-wide)', () {
    late Directory tempDir;
    late Directory ticketsDir;
    late Directory ticketDir;
    final messages = <String>[];
    late List<List<String>> processCalls;
    late List<String?> processWorkingDirs;
    late ProcessResult processResult;

    void ggLog(String msg) => messages.add(rmConsoleColors(msg));

    Future<ProcessResult> fakeRunner(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      bool runInShell = false,
    }) async {
      processCalls.add(<String>[executable, ...arguments]);
      processWorkingDirs.add(workingDirectory);
      return processResult;
    }

    DoInstallGitattributesCommand newCommand() => DoInstallGitattributesCommand(
          ggLog: ggLog,
          processRunner: fakeRunner,
        );

    setUp(() {
      messages.clear();
      processCalls = <List<String>>[];
      processWorkingDirs = <String?>[];
      processResult = ProcessResult(0, 0, '', '');
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
        Directory(path.join(repoDir.path, '.git')).createSync();
      }
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('fails outside any ticket folder', () async {
      final runner = CommandRunner<void>('test', 'do install-gitattributes')
        ..addCommand(newCommand());

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
        ..addCommand(newCommand());

      await runner.run(
        <String>['install-gitattributes', '--input', emptyTicket.path],
      );

      expect(
        messages,
        contains('⚠️ No repos in this ticket'),
      );
    });

    test('creates .gitattributes and configures merge driver', () async {
      final runner = CommandRunner<void>('test', 'do install-gitattributes')
        ..addCommand(newCommand());

      await runner.run(
        <String>['install-gitattributes', '--input', ticketDir.path],
      );

      for (final name in <String>['A', 'B']) {
        final file = File(
          path.join(ticketDir.path, name, '.gitattributes'),
        );
        expect(file.existsSync(), isTrue);
        expect(
          file.readAsStringSync(),
          '$gitattributesRequiredLines\n',
        );
        expect(messages, contains('Created .gitattributes in $name.'));
        expect(
          messages,
          contains('Configured merge.ours driver in $name.'),
        );
      }

      expect(processCalls, hasLength(2));
      for (final call in processCalls) {
        expect(call, <String>[
          'git',
          'config',
          'merge.ours.driver',
          'true',
        ]);
      }
      expect(
        processWorkingDirs,
        <String>[
          path.join(ticketDir.path, 'A'),
          path.join(ticketDir.path, 'B'),
        ],
      );

      expect(
        messages,
        contains(
          '✅ Ensured .gitattributes for all repositories in ticket TICKG.',
        ),
      );
    });

    test('leaves an existing .gitattributes with all rules untouched',
        () async {
      final file = File(
        path.join(ticketDir.path, 'A', '.gitattributes'),
      );
      const original = '# header\n'
          '* text=auto eol=lf\n'
          '.gg/.gg.json merge=ours\n'
          'pubspec.lock merge=ours\n';
      file.writeAsStringSync(original);
      final originalMtime = file.lastModifiedSync();

      final runner = CommandRunner<void>('test', 'do install-gitattributes')
        ..addCommand(newCommand());

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
      expect(file.lastModifiedSync(), originalMtime);
      // Merge driver is still configured.
      expect(
        messages,
        contains('Configured merge.ours driver in A.'),
      );
    });

    test('appends only the missing rules', () async {
      final fileA = File(
        path.join(ticketDir.path, 'A', '.gitattributes'),
      )..writeAsStringSync('*.png binary\n* text=auto eol=lf\n');
      final fileB = File(
        path.join(ticketDir.path, 'B', '.gitattributes'),
      )..writeAsStringSync('*.png binary');

      final runner = CommandRunner<void>('test', 'do install-gitattributes')
        ..addCommand(newCommand());

      await runner.run(
        <String>['install-gitattributes', '--input', ticketDir.path],
      );

      expect(
        fileA.readAsStringSync(),
        '*.png binary\n'
        '* text=auto eol=lf\n'
        '.gg/.gg.json merge=ours\n'
        'pubspec.lock merge=ours\n',
      );
      expect(
        fileB.readAsStringSync(),
        '*.png binary\n'
        '* text=auto eol=lf\n'
        '.gg/.gg.json merge=ours\n'
        'pubspec.lock merge=ours\n',
      );
      expect(messages, contains('Updated .gitattributes in A.'));
      expect(messages, contains('Updated .gitattributes in B.'));
    });

    test('skips merge driver config when .git is missing', () async {
      Directory(path.join(ticketDir.path, 'A', '.git'))
          .deleteSync(recursive: true);

      final runner = CommandRunner<void>('test', 'do install-gitattributes')
        ..addCommand(newCommand());

      await runner.run(
        <String>['install-gitattributes', '--input', ticketDir.path],
      );

      expect(
        messages,
        contains(
          'Skipping merge.ours driver config for A because no '
          '.git directory was found.',
        ),
      );
      // Only B got the git config call.
      expect(processCalls, hasLength(1));
      expect(
        processWorkingDirs,
        <String>[path.join(ticketDir.path, 'B')],
      );
    });

    test('throws when git config fails', () async {
      processResult = ProcessResult(0, 1, '', 'boom');

      final runner = CommandRunner<void>('test', 'do install-gitattributes')
        ..addCommand(newCommand());

      await expectLater(
        () async => runner.run(
          <String>['install-gitattributes', '--input', ticketDir.path],
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('git config merge.ours.driver true failed in A'),
          ),
        ),
      );

      expect(
        messages.any(
          (m) => m.contains('Failed to configure merge.ours driver in A'),
        ),
        isTrue,
      );
    });

    test('exec() is equivalent to running the command', () async {
      await newCommand().exec(
        directory: ticketDir,
        ggLog: ggLog,
      );

      for (final name in <String>['A', 'B']) {
        final file = File(
          path.join(ticketDir.path, name, '.gitattributes'),
        );
        expect(file.existsSync(), isTrue);
      }
      expect(processCalls, hasLength(2));
    });

    test('uses the real Process.run by default', () {
      // Just ensure the default constructor wires up without error.
      expect(
        () => DoInstallGitattributesCommand(ggLog: ggLog),
        returnsNormally,
      );
    });
  });
}
