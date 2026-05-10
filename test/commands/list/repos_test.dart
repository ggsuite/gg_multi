// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_multi/src/backend/constants.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:gg_multi/src/commands/list/repos.dart';

import '../../rm_console_colors_helper.dart';

void main() {
  group('ListReposCommand', () {
    late Directory tempDir;
    final messages = <String>[];

    void ggLog(String message) {
      messages.add(rmConsoleColors(message));
    }

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('list_repos_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('lists repositories correctly', () async {
      final workspacePath = path.join(tempDir.path, 'workspace_link');
      final masterPath = path.join(workspacePath, ggMultiMasterFolder);
      final repo1 = Directory(path.join(masterPath, 'json_dart'))
        ..createSync(
          recursive: true,
        );
      File(path.join(repo1.path, 'pubspec.yaml'))
          .writeAsStringSync('name: json_dart\nversion: 3.5.2');
      Directory(path.join(repo1.path, '.git')).createSync();
      File(path.join(repo1.path, '.git', 'config'))
          .writeAsStringSync('url = https://github.com/inlavigo/json_dart.git');

      final repo2 = Directory(path.join(masterPath, 'project123'))
        ..createSync();
      Directory(path.join(repo2.path, '.git')).createSync();
      File(path.join(repo2.path, '.git', 'config')).writeAsStringSync(
        'url = https://github.com/microsoft/project123.git',
      );

      final runner = CommandRunner<void>('test', 'Test ListReposCommand');
      runner.addCommand(
        ListReposCommand(
          ggLog: ggLog,
          workspacePath: masterPath,
        ),
      );
      await runner.run(['repos']);

      expect(messages, contains('json_dart v.3.5.2 (dart) from inlavigo'));
      expect(messages, contains('project123 v.1.0.0 (dart) from microsoft'));
    });

    test('handles empty master workspace directory', () async {
      final workspacePath = path.join(tempDir.path, 'workspace_empty');
      final masterPath = Directory(path.join(workspacePath, ggMultiMasterFolder))
        ..createSync(
          recursive: true,
        );
      final runner = CommandRunner<void>('test', 'Test ListReposCommand');
      runner.addCommand(
        ListReposCommand(
          ggLog: ggLog,
          workspacePath: masterPath.path,
        ),
      );
      await runner.run(['repos']);
      expect(
        messages,
        contains('No repositories found in the master workspace.'),
      );
    });

    test('prints help message when --help is passed', () async {
      final workspacePath = path.join(tempDir.path, 'workspace_help');
      final runner = CommandRunner<void>(
        'test',
        'ListReposCommand Help',
      );
      runner.addCommand(
        ListReposCommand(
          ggLog: (_) {},
          workspacePath: workspacePath,
        ),
      );
      final output = await capturePrint(
        code: () async {
          await runner.run(['repos', '--help']);
        },
      );
      expect(output.first, contains('Lists all repos'));
    });
  });
}
