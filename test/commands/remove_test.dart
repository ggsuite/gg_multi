// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:kidney_core/src/commands/remove.dart';

import '../rm_console_colors_helper.dart';

// A fake Directory class for testing
// purposes that always reports non-existence.
class _FakeDirectory extends Fake implements Directory {
  final String _path;
  _FakeDirectory(this._path);
  @override
  String get path => _path;
  @override
  bool existsSync() => false;
}

void main() {
  group('RemoveCommand', () {
    late Directory tempDir;
    late Directory masterWs;
    late CommandRunner<void> runner;
    final messages = <String>[];

    void ggLog(String message) {
      messages.add(rmConsoleColors(message));
    }

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('remove_test_');
      masterWs = Directory(
        path.join(
          tempDir.path,
          'kidney_ws_master',
        ),
      )..createSync(recursive: true);
      runner = CommandRunner<void>('test', 'RemoveCommand Test')
        ..addCommand(
          RemoveCommand(
            ggLog: ggLog,
            rootPath: tempDir.path,
          ),
        );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('deletes repo when only in master workspace', () async {
      // Arrange
      final repoDir = Directory(
        path.join(
          masterWs.path,
          'project',
        ),
      )..createSync(recursive: true);

      // Act
      await runner.run(['remove', 'project']);

      // Assert
      expect(repoDir.existsSync(), isFalse);
      expect(
        messages,
        contains('Deleted repository project from master workspace.'),
      );
    });

    test('lists feature branches when in multiple workspaces', () async {
      // Arrange: repo in master and a feature workspace
      final featureWs = Directory(
        path.join(
          tempDir.path,
          'kidney_ws_feature1',
        ),
      )..createSync(recursive: true);
      Directory(path.join(masterWs.path, 'featProj'))
          .createSync(recursive: true);
      Directory(path.join(featureWs.path, 'featProj'))
          .createSync(recursive: true);

      // Act
      await runner.run(['remove', 'featProj']);

      // Assert: not deleted
      expect(
        Directory(path.join(masterWs.path, 'featProj')).existsSync(),
        isTrue,
      );
      expect(
        messages,
        contains('This repo is used by the following feature branches:'),
      );
      expect(messages, contains(' - kidney_ws_feature1'));
      expect(messages, contains('Please remove these branches first.'));
    });

    test('notifies when repo not found', () async {
      // Act
      await runner.run(['remove', 'noRepo']);

      // Assert
      expect(
        messages,
        contains('Repository noRepo not found in any workspace.'),
      );
    });

    test('throws UsageException when missing argument', () async {
      // Act & Assert
      expect(
        () => runner.run(['remove']),
        throwsA(isA<UsageException>()),
      );
    });

    test('logs "Root path not found" when rootPath does not exist', () async {
      // Arrange
      final nonExistingPath = path.join(tempDir.path, 'nonexistent_workspace');
      final localRunner = CommandRunner<void>('test', 'RemoveCommand Test')
        ..addCommand(
          RemoveCommand(ggLog: ggLog, rootPath: nonExistingPath),
        );

      // Act
      await localRunner.run(['remove', 'anyRepo']);

      // Assert
      expect(messages, contains('Root path not found: $nonExistingPath'));
    });

    test('logs repository folder not found when deletion target does not exist',
        () async {
      // Arrange
      // Create the kidney_ws_master workspace if not exists
      final masterWsPath = path.join(tempDir.path, 'kidney_ws_master');
      final masterDir = Directory(masterWsPath);
      if (!masterDir.existsSync()) {
        masterDir.createSync(recursive: true);
      }
      // Create a repo folder so that it gets detected in the scanning phase
      final repoFolderPath = path.join(masterWsPath, 'missingRepo');
      Directory(repoFolderPath).createSync(recursive: true);
      // Now, do not physically delete it here,
      // but inject a fake Directory for deletion
      final runnerWithFake =
          CommandRunner<void>('test', 'RemoveCommand Fake Test')
            ..addCommand(
              RemoveCommand(
                ggLog: ggLog,
                rootPath: tempDir.path,
                directoryFactory: (p) => _FakeDirectory(p),
              ),
            );

      // Act
      await runnerWithFake.run(['remove', 'missingRepo']);

      // Assert
      expect(
        messages,
        contains('Repository folder not found: $repoFolderPath'),
      );
    });

    test('deletes ticket folder when name matches ticket', () async {
      // Arrange: setup a ticket folder under tickets
      final ticketDir = Directory(
        path.join(tempDir.path, 'tickets', 'ticket1'),
      )..createSync(recursive: true);
      File(path.join(ticketDir.path, 'dummy.txt')).writeAsStringSync('data');

      // Act
      await runner.run(['remove', 'ticket1']);

      // Assert: folder is removed and log is correct
      expect(ticketDir.existsSync(), isFalse);
      expect(
        messages,
        contains('Deleted ticket ticket1 at ${ticketDir.path}'),
      );
    });
  });
}
