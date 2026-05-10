// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_multi/src/backend/constants.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as path;
import 'package:gg_multi/src/commands/list/deps.dart';

void main() {
  group('ListDepsCommand', () {
    late Directory tempDir;
    late Directory masterWorkspace;
    final messages = <String>[];

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('list_deps_test');
      masterWorkspace = Directory(path.join(tempDir.path, ggMultiMasterFolder))
        ..createSync(recursive: true);
      // Create a project folder 'project123' inside master workspace
      final projectDir =
          Directory(path.join(masterWorkspace.path, 'project123'))
            ..createSync(recursive: true);
      const pubspecContent = '''
name: project123
version: 1.0.0
dependencies:
  json_dart: ^3.5.2
dev_dependencies:
  json_serializer: ^1.4.2
''';
      File(path.join(projectDir.path, 'pubspec.yaml'))
          .writeAsStringSync(pubspecContent);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('lists dependencies from project pubspec.yaml', () async {
      final runner = CommandRunner<void>('test', 'Test ListDepsCommand');
      runner.addCommand(
        ListDepsCommand(
          ggLog: messages.add,
          workspacePath: masterWorkspace.path,
        ),
      );

      await runner.run(['deps', 'project123', '--depth=1']);

      expect(messages[0], 'project123 v.1.0.0 (dart)');
      expect(messages.any((msg) => msg.contains('json_dart')), isTrue);
      expect(messages.any((msg) => msg.contains('^3.5.2')), isTrue);
      expect(
        messages.any((msg) => msg.contains('dev:json_serializer')),
        isTrue,
      );
      expect(messages.any((msg) => msg.contains('^1.4.2')), isTrue);
    });

    test('prints help message when --help is passed', () async {
      final runner = CommandRunner<void>('test', 'Test ListDepsCommand');
      runner.addCommand(
        ListDepsCommand(
          ggLog: messages.add,
          workspacePath: masterWorkspace.path,
        ),
      );
      final output = await capturePrint(
        code: () async {
          await runner.run(['deps', '--help']);
        },
      );
      expect(output.first, contains('Lists dependencies and dev_dependencies'));
    });

    test('throws UsageException when target repository parameter is missing',
        () async {
      final runner = CommandRunner<void>('test', 'Test Missing Target');
      runner.addCommand(
        ListDepsCommand(
          ggLog: messages.add,
          workspacePath: masterWorkspace.path,
        ),
      );
      await expectLater(runner.run(['deps']), throwsA(isA<UsageException>()));
    });
  });
}
