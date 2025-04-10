// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:test/test.dart';
import 'package:kidney_core/src/commands/list/repos.dart';

void main() {
  group('ListReposCommand', () {
    late Directory tempDir;
    late Directory masterDir;
    final messages = <String>[];

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('list_repos_test');
      masterDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}kidney_ws_master',
      )..createSync(recursive: true);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('lists repositories correctly', () async {
      final masterPath = masterDir.path;
      final repo1 = Directory('$masterPath${Platform.pathSeparator}json_dart')
        ..createSync();
      File(
        '${repo1.path}${Platform.pathSeparator}pubspec.yaml',
      ).writeAsStringSync('name: json_dart\nversion: 3.5.2');
      Directory(
        '${repo1.path}${Platform.pathSeparator}.git',
      ).createSync();
      File(
        '${repo1.path}${Platform.pathSeparator}.git'
        '${Platform.pathSeparator}config',
      ).writeAsStringSync('url = https://github.com/inlavigo/json_dart.git');

      final repo2 = Directory('$masterPath${Platform.pathSeparator}project123')
        ..createSync();
      Directory(
        '${repo2.path}${Platform.pathSeparator}.git',
      ).createSync();
      File('${repo2.path}${Platform.pathSeparator}.git'
              '${Platform.pathSeparator}config')
          .writeAsStringSync(
        'url = https://github.com/microsoft/project123.git',
      );

      final runner = CommandRunner<void>('test', 'Test ListReposCommand');
      runner.addCommand(
        ListReposCommand(
          ggLog: messages.add,
          workspacePath: masterDir.path,
        ),
      );
      await runner.run(['repos']);

      expect(messages, contains('json_dart v.3.5.2 (dart) from inlavigo'));
      expect(messages, contains('project123 v.1.0.0 (dart) from microsoft'));
    });

    test('handles empty master workspace directory', () async {
      final emptyDir =
          Directory('${tempDir.path}${Platform.pathSeparator}empty_master')
            ..createSync();
      final runner = CommandRunner<void>('test', 'Test ListReposCommand');
      runner.addCommand(
        ListReposCommand(
          ggLog: messages.add,
          workspacePath: emptyDir.path,
        ),
      );
      await runner.run(['repos']);
      expect(
        messages,
        contains('No repositories found in the master workspace.'),
      );
    });
  });
}
