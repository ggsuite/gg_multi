// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:kidney_core/src/commands/remove.dart';

void main() {
  group('RemoveCommand', () {
    late Directory tempDir;
    late Directory masterWs;
    late CommandRunner<void> runner;
    final messages = <String>[];

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
            ggLog: messages.add,
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
        contains('This repo is used by the following feature '
            'branches:'),
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
  });
}
