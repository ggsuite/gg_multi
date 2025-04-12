// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:kidney_core/src/commands/list/deps.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:test/test.dart';

void main() {
  group('ListDepsCommand', () {
    late Directory tempDir;
    final messages = <String>[];

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('list_deps_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('lists dependencies from pubspec.yaml', () async {
      const pubspecContent = '''
name: project123
version: 1.0.0
dependencies:
  json_dart: ^3.5.2
dev_dependencies:
  json_serializer: ^1.4.2
''';
      final pubspecPath =
          '${tempDir.path}${Platform.pathSeparator}pubspec.yaml';
      File(pubspecPath).writeAsStringSync(pubspecContent);

      // Use CommandRunner to run the command
      final runner = CommandRunner<void>('test', 'Test ListDepsCommand');
      runner.addCommand(
        ListDepsCommand(
          ggLog: messages.add,
          pubspecPath: pubspecPath,
        ),
      );
      await runner.run(['deps']);

      expect(messages[0], 'project123 v.1.0.0 (dart)');
      expect(messages[1], contains('json_dart'));
      expect(messages[1], contains('^3.5.2'));
      expect(messages[2], contains('dev:json_serializer'));
      expect(messages[2], contains('^1.4.2'));
    });

    test('handles missing pubspec.yaml', () async {
      final pubspecPath =
          '${tempDir.path}${Platform.pathSeparator}pubspec.yaml';
      if (File(pubspecPath).existsSync()) {
        File(pubspecPath).deleteSync();
      }

      final runner = CommandRunner<void>('test', 'Test ListDepsCommand');
      runner.addCommand(
        ListDepsCommand(
          ggLog: messages.add,
          pubspecPath: pubspecPath,
        ),
      );
      await runner.run(['deps']);

      expect(
        messages,
        contains('pubspec.yaml not found in current directory.'),
      );
    });

    test('handles invalid pubspec content', () async {
      final pubspecPath =
          '${tempDir.path}${Platform.pathSeparator}pubspec.yaml';
      File(pubspecPath).writeAsStringSync('invalid pubspec content');

      final runner = CommandRunner<void>('test', 'Test ListDepsCommand');
      runner.addCommand(
        ListDepsCommand(
          ggLog: messages.add,
          pubspecPath: pubspecPath,
        ),
      );
      await runner.run(['deps']);

      expect(messages.isNotEmpty, isTrue);
      expect(messages[0], startsWith('Error parsing pubspec.yaml:'));
    });

    test('prints help message when --help is passed', () async {
      final runner = CommandRunner<void>(
        'test',
        'ListDepsCommand Help',
      );
      // Provide a dummy pubspec path; help should not require reading it
      runner.addCommand(
        ListDepsCommand(
          ggLog: (_) {},
          pubspecPath: '${tempDir.path}${Platform.pathSeparator}pubspec.yaml',
        ),
      );
      final output = await capturePrint(
        code: () async {
          await runner.run(['deps', '--help']);
        },
      );
      expect(
        output.first,
        contains('Lists dependencies and dev_dependencies'),
      );
    });
  });
}
