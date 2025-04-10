// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:test/test.dart';
import 'package:kidney_core/src/commands/list/deps.dart';

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
      final command = ListDepsCommand(
        ggLog: messages.add,
        pubspecPath: pubspecPath,
      );
      command.run();
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
      final command = ListDepsCommand(
        ggLog: messages.add,
        pubspecPath: pubspecPath,
      );
      command.run();
      expect(
        messages,
        contains('pubspec.yaml not found in current directory.'),
      );
    });

    test('handles invalid pubspec content', () async {
      final pubspecPath =
          '${tempDir.path}${Platform.pathSeparator}pubspec.yaml';
      File(pubspecPath).writeAsStringSync('invalid pubspec content');
      final command = ListDepsCommand(
        ggLog: messages.add,
        pubspecPath: pubspecPath,
      );
      command.run();
      expect(messages.isNotEmpty, isTrue);
      expect(messages[0], startsWith('Error parsing pubspec.yaml:'));
    });
  });
}
