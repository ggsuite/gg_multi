// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:kidney_core/src/backend/git_cloner.dart';
import 'package:kidney_core/src/commands/add_deps.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

class MockGitCloner extends Mock implements GitCloner {}

void main() {
  group('AddDepsCommand', () {
    late Directory tempDir;
    late Directory dirNoPubspec;
    late Directory dirProject;
    late List<String> logMessages;
    late MockGitCloner mockGitCloner;
    late CommandRunner<void> runner;
    late String workspacePath;

    setUp(() {
      mockGitCloner = MockGitCloner();
      logMessages = [];
      when(() => mockGitCloner.cloneRepo(any(), any()))
          .thenAnswer((_) async {});
      tempDir = Directory.systemTemp.createTempSync('add_deps_test');
      workspacePath = path.join(tempDir.path, 'kidney_ws_master');
      // Create workspace directories
      Directory(workspacePath).createSync(recursive: true);
      dirNoPubspec = Directory(path.join(workspacePath, 'no_pubspec'))
        ..createSync(recursive: true);
      dirProject = Directory(path.join(workspacePath, 'project'))
        ..createSync(recursive: true);
      runner = CommandRunner<void>('test', 'Test AddDepsCommand');
      runner.addCommand(
        AddDepsCommand(
          ggLog: logMessages.add,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
        ),
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('iterates over dependencies and dev_dependencies', () async {
      const pubspecContent = '''
name: test_project
version: 1.0.0
dependencies:
  json_dart: ^3.5.2
  http: ^0.13.0
dev_dependencies:
  json_serializer: ^1.4.2
''';
      File(path.join(dirProject.path, 'pubspec.yaml'))
          .writeAsStringSync(pubspecContent);

      await runner.run(['add-deps', 'project']);

      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/json_dart/json_dart.git',
          any(),
        ),
      ).called(1);
      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/http/http.git',
          any(),
        ),
      ).called(1);
      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/json_serializer/json_serializer.git',
          any(),
        ),
      ).called(1);

      expect(
        logMessages,
        containsAll([
          'added repository json_dart from '
              'https://github.com/json_dart/json_dart.git',
          'added repository http from '
              'https://github.com/http/http.git',
          'added repository json_serializer from '
              'https://github.com/json_serializer/json_serializer.git',
        ]),
      );
    });

    test('logs message when pubspec.yaml not found', () async {
      await runner.run(['add-deps', 'no_pubspec']);
      expect(
        logMessages,
        contains('pubspec.yaml not found in project '
            'no_pubspec in workspace $workspacePath.'),
      );
    });

    test('logs message when no dependencies found', () async {
      const pubspecContent = '''
name: test_project
version: 1.0.0
dependencies:
dev_dependencies:
''';
      File(path.join(dirNoPubspec.path, 'pubspec.yaml'))
          .writeAsStringSync(pubspecContent);
      await runner.run(['add-deps', 'no_pubspec']);
      expect(
        logMessages,
        contains('No dependencies found in pubspec.yaml '
            'for project test_project.'),
      );
    });

    test('prints help message when --help is passed', () async {
      final output = await capturePrint(
        code: () async {
          await runner.run(['add-deps', '--help']);
        },
      );
      expect(
        output.first,
        contains('Iterates over all dependencies '
            'specified in pubspec.yaml'),
      );
    });
  });
}
