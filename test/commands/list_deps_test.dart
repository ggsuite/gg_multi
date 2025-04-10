// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:test/test.dart';
import 'package:kidney_core/src/commands/list_deps.dart';

void main() {
  group('ListDepsCommand', () {
    late Directory tempDir;
    late String originalDir;
    final messages = <String>[];

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('list_deps_test');
      originalDir = Directory.current.path;
      Directory.current = tempDir.path;
    });

    tearDown(() {
      Directory.current = originalDir;
      tempDir.deleteSync(recursive: true);
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
      File('pubspec.yaml').writeAsStringSync(pubspecContent);
      final command = ListDepsCommand(ggLog: messages.add);
      command.run();
      expect(messages[0], 'project123 v.1.0.0 (dart)');
      expect(messages[1], contains('json_dart'));
      expect(messages[1], contains('^3.5.2'));
      expect(messages[2], contains('dev:json_serializer'));
      expect(messages[2], contains('^1.4.2'));
    });

    test('handles missing pubspec.yaml', () async {
      if (File('pubspec.yaml').existsSync()) {
        File('pubspec.yaml').deleteSync();
      }
      final command = ListDepsCommand(ggLog: messages.add);
      command.run();
      expect(
        messages,
        contains('pubspec.yaml not found in current directory.'),
      );
    });
  });
}
