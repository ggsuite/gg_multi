// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:test/test.dart';
import 'package:kidney_core/src/commands/list.dart';

void main() {
  group('ListCommand interactive', () {
    late Directory tempDir;
    late String originalDir;
    final messages = <String>[];

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('list_test');
      originalDir = Directory.current.path;
      Directory.current = tempDir.path;
    });

    tearDown(() {
      Directory.current = originalDir;
      tempDir.deleteSync(recursive: true);
    });

    test('chooses repos', () async {
      final masterDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}kidney_ws_master',
      );
      masterDir.createSync();
      final repoDir = Directory(
        '${masterDir.path}${Platform.pathSeparator}dummy_repo',
      );
      repoDir.createSync();
      File('${repoDir.path}${Platform.pathSeparator}pubspec.yaml')
          .writeAsStringSync('name: dummy_repo\nversion: 1.2.3');
      final gitDir = Directory(
        '${repoDir.path}${Platform.pathSeparator}.git',
      );
      gitDir.createSync();
      File('${gitDir.path}${Platform.pathSeparator}config')
          .writeAsStringSync('url = https://github.com/testorg/dummy_repo.git');

      final listCommand = ListCommand(
        ggLog: messages.add,
        inputProvider: () => 'r',
      );
      await listCommand.run();
      expect(
        messages,
        contains('dummy_repo v.1.2.3 (dart) from testorg'),
      );
    });

    test('chooses organizations', () async {
      final masterDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}kidney_ws_master',
      );
      masterDir.createSync();
      // Repo 1
      final repo1 = Directory(
        '${masterDir.path}${Platform.pathSeparator}repo1',
      );
      repo1.createSync();
      File('${repo1.path}${Platform.pathSeparator}pubspec.yaml')
          .writeAsStringSync('name: repo1\nversion: 2.0.0');
      final gitDir1 = Directory(
        '${repo1.path}${Platform.pathSeparator}.git',
      );
      gitDir1.createSync();
      File('${gitDir1.path}${Platform.pathSeparator}config')
          .writeAsStringSync('url = https://github.com/testorg/repo1.git');

      // Repo 2
      final repo2 = Directory(
        '${masterDir.path}${Platform.pathSeparator}repo2',
      );
      repo2.createSync();
      final gitDir2 = Directory(
        '${repo2.path}${Platform.pathSeparator}.git',
      );
      gitDir2.createSync();
      File('${gitDir2.path}${Platform.pathSeparator}config')
          .writeAsStringSync('url = https://github.com/anotherorg/repo2.git');

      final listCommand = ListCommand(
        ggLog: messages.add,
        inputProvider: () => 'o',
      );
      await listCommand.run();
      expect(
        messages,
        contains('anotherorg -- https://github.com/orgs/anotherorg/'),
      );
      expect(
        messages,
        contains('testorg -- https://github.com/orgs/testorg/'),
      );
    });

    test('chooses deps when pubspec.yaml exists', () async {
      final pubspecFile = File(
        '${tempDir.path}${Platform.pathSeparator}pubspec.yaml',
      );
      pubspecFile.writeAsStringSync('''
name: project123
version: 1.0.0
dependencies:
  json_dart: ^3.5.2
dev_dependencies:
  json_serializer: ^1.4.2
''');
      final listCommand = ListCommand(
        ggLog: messages.add,
        inputProvider: () => 'd',
      );
      await listCommand.run();
      expect(messages[0], 'project123 v.1.0.0 (dart)');
      expect(messages[1], contains('json_dart'));
      expect(messages[1], contains('^3.5.2'));
      expect(messages[2], contains('dev:json_serializer'));
      expect(messages[2], contains('^1.4.2'));
    });

    test('handles invalid choice', () async {
      final listCommand = ListCommand(
        ggLog: messages.add,
        inputProvider: () => 'invalid',
      );
      await listCommand.run();
      expect(messages, contains('Invalid choice.'));
    });
  });
}
