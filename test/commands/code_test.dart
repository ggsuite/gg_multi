// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:kidney_core/src/commands/code.dart';
import '../rm_console_colors_helper.dart';

void main() {
  group('CodeCommand', () {
    late Directory tempRoot;
    late List<String> messages;
    late List<List<String>> launched;
    late CommandRunner<void> runner;

    Future<ProcessResult> fakeRun(String exe, List<String> args) async {
      launched.add([exe, ...args]);
      return ProcessResult(0, 0, '', '');
    }

    void ggLog(String m) => messages.add(rmConsoleColors(m));

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('code_test_');
      messages = [];
      launched = [];
      runner = CommandRunner<void>('test', 'test')
        ..addCommand(
          CodeCommand(
            ggLog: ggLog,
            rootPath: tempRoot.path,
            processRunner: fakeRun,
          ),
        );
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('throws UsageException when missing args', () {
      expect(() => runner.run(['code']), throwsA(isA<UsageException>()));
    });

    test('logs not found when ticket missing', () async {
      await runner.run(['code', 'TCKT']);
      expect(
        messages,
        contains('Ticket TCKT not found at '
            '${path.join(tempRoot.path, 'tickets', 'TCKT')}'),
      );
    });

    test('logs no repos if ticket exists but empty', () async {
      Directory(path.join(tempRoot.path, 'tickets', 'T1'))
          .createSync(recursive: true);
      await runner.run(['code', 'T1']);
      expect(messages, contains('No repositories found under ticket T1.'));
    });

    test('opens all repos under a ticket', () async {
      final tdir = Directory(path.join(tempRoot.path, 'tickets', 'T2'))
        ..createSync(recursive: true);
      Directory(path.join(tdir.path, 'A')).createSync();
      Directory(path.join(tdir.path, 'B')).createSync();
      await runner.run(['code', 'T2']);

      // must have launched twice, once for each subdir
      expect(launched.length, 2);
      // both must launch 'code', ...
      expect(launched[0][0], 'code');
      expect(launched[1][0], 'code');
      expect(
        messages,
        contains('Opened A at ${path.join(tdir.path, 'A')}'),
      );
      expect(
        messages,
        contains('Opened B at ${path.join(tdir.path, 'B')}'),
      );
    });

    test('opens single repo when specified', () async {
      final tdir = Directory(path.join(tempRoot.path, 'tickets', 'T3'))
        ..createSync(recursive: true);
      Directory(path.join(tdir.path, 'MyRepo')).createSync();
      await runner.run(['code', 'T3/MyRepo']);

      expect(launched.length, 1);
      expect(
        launched[0],
        ['code', path.join(tdir.path, 'MyRepo')],
      );
      expect(
        messages,
        contains('Opened MyRepo at ${path.join(tdir.path, 'MyRepo')}'),
      );
    });

    test('logs error when specified repo missing', () async {
      final tdir = Directory(path.join(tempRoot.path, 'tickets', 'T4'))
        ..createSync(recursive: true);
      await runner.run(['code', 'T4/NoRepo']);
      expect(
        messages,
        contains('Repository NoRepo not found in ticket T4 at '
            '${path.join(tdir.path, 'NoRepo')}'),
      );
      expect(launched, isEmpty);
    });

    test('handles --help without throwing', () async {
      await runner.run(['code', '--help']);
    });

    test('throws UsageException on bad format', () {
      expect(
        () => runner.run(['code', 'too/many/parts']),
        throwsA(isA<UsageException>()),
      );
    });
  });
}
