// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_multi/src/backend/repo_setup.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  final messages = <String>[];

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('repo_setup_test');
    messages.clear();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Directory repoWith({bool pubspec = false, bool packageJson = false}) {
    final d = Directory(path.join(tmp.path, 'r'))..createSync(recursive: true);
    if (pubspec) {
      File(path.join(d.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
    }
    if (packageJson) {
      File(path.join(d.path, 'package.json')).writeAsStringSync('{}');
    }
    return d;
  }

  group('installRepoDependencies', () {
    final calls = <List<String>>[];

    ProcessRunner runner({int exitCode = 0}) =>
        (exe, args, {workingDirectory, runInShell = false}) async {
          calls.add(<String>[exe, ...args]);
          return ProcessResult(0, exitCode, '', 'boom');
        };

    setUp(calls.clear);

    test('runs dart pub get and logs success', () async {
      await installRepoDependencies(
        dir: repoWith(pubspec: true),
        repoName: 'r',
        ggLog: messages.add,
        processRunner: runner(),
      );
      expect(calls, [
        ['dart', 'pub', 'get'],
      ]);
      expect(
        messages.any((m) => m.contains('Executed dart pub get in r.')),
        isTrue,
      );
    });

    test('uses dart pub upgrade when upgradeDart is true', () async {
      await installRepoDependencies(
        dir: repoWith(pubspec: true),
        repoName: 'r',
        ggLog: messages.add,
        processRunner: runner(),
        upgradeDart: true,
      );
      expect(calls, [
        ['dart', 'pub', 'upgrade'],
      ]);
    });

    test('runs the TypeScript package manager install', () async {
      await installRepoDependencies(
        dir: repoWith(packageJson: true),
        repoName: 'r',
        ggLog: messages.add,
        processRunner: runner(),
      );
      expect(calls.single.last, 'install');
      expect(messages.any((m) => m.contains('install in r.')), isTrue);
    });

    test('logs a failure on a non-zero exit code', () async {
      await installRepoDependencies(
        dir: repoWith(pubspec: true),
        repoName: 'r',
        ggLog: messages.add,
        processRunner: runner(exitCode: 1),
      );
      expect(
        messages.any(
          (m) => m.contains('Failed to execute dart pub get in r: boom'),
        ),
        isTrue,
      );
    });

    test('does nothing when neither manifest exists', () async {
      await installRepoDependencies(
        dir: repoWith(),
        repoName: 'r',
        ggLog: messages.add,
        processRunner: runner(),
      );
      expect(calls, isEmpty);
      expect(messages, isEmpty);
    });
  });

  group('writeCodeWorkspaceFile', () {
    test('writes a deduplicated folder list with trailing newline', () {
      final ticketDir = Directory(path.join(tmp.path, 'my_ticket'))
        ..createSync();
      writeCodeWorkspaceFile(ticketDir, ['a', 'b', 'a']);
      final file = File(
        path.join(ticketDir.path, 'my_ticket.code-workspace'),
      );
      expect(
        file.readAsStringSync(),
        '{"folders":[{"path":"a"},{"path":"b"}]}\n',
      );
    });
  });
}
