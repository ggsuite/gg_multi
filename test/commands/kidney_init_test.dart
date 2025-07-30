// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:kidney_core/src/backend/constants.dart';
import 'package:kidney_core/src/commands/kidney_init.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as path;

import '../rm_console_colors_helper.dart';

void main() {
  group('InitCommand', () {
    late Directory tempDir;
    final messages = <String>[];

    void ggLog(String message) {
      messages.add(rmConsoleColors(message));
    }

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('init_command_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should create master workspace if not exists', () async {
      final runner = CommandRunner<void>('test', 'InitCommand Test')
        ..addCommand(
          InitCommand(
            ggLog: ggLog,
            rootPath: tempDir.path,
          ),
        );
      final wsPath = path.join(tempDir.path, kidneyMasterFolder);
      expect(Directory(wsPath).existsSync(), isFalse);

      await runner.run(['init']);
      expect(messages.any((m) => m.contains('initialized at')), isTrue);
      expect(Directory(wsPath).existsSync(), isTrue);
    });

    test('should not recreate if already exists, and log accordingly',
        () async {
      final wsPath = path.join(tempDir.path, kidneyMasterFolder);
      Directory(wsPath).createSync(recursive: true);
      final runner = CommandRunner<void>('test', 'InitCommand Test')
        ..addCommand(
          InitCommand(
            ggLog: ggLog,
            rootPath: tempDir.path,
          ),
        );

      await runner.run(['init']);

      expect(messages[0], contains('Master workspace already exists at:'));
      expect(messages[0], contains(kidneyMasterFolder));
      expect(Directory(wsPath).existsSync(), isTrue);
    });

    test('should not allow init inside non-empty directory', () async {
      // Arrange:
      final nonEmptyDir = Directory(path.join(tempDir.path, 'not_empty'));
      nonEmptyDir.createSync(recursive: true);
      File(path.join(nonEmptyDir.path, 'some_file.txt'))
          .writeAsStringSync('dummy');
      final runner = CommandRunner<void>('test', 'InitCommand Test')
        ..addCommand(
          InitCommand(
            ggLog: ggLog,
            rootPath: nonEmptyDir.path,
          ),
        );
      // Act
      await runner.run(['init']);
      // Assert
      expect(
        messages,
        contains(
          'The directory must be empty to initialize a workspace.',
        ),
      );
      expect(
        Directory(path.join(nonEmptyDir.path, kidneyMasterFolder)).existsSync(),
        isFalse,
      );
    });

    test('should not allow init inside an existing workspace (nested)',
        () async {
      // Arrange:
      // Create parent workspace
      final parentWs = Directory(path.join(tempDir.path, 'parent'))
        ..createSync();
      final masterWs = Directory(path.join(parentWs.path, kidneyMasterFolder))
        ..createSync();
      // Create child directory inside parent
      final childDir = Directory(path.join(masterWs.path, 'child'))
        ..createSync();
      final runner = CommandRunner<void>('test', 'InitCommand Nested')
        ..addCommand(
          InitCommand(
            ggLog: ggLog,
            rootPath: childDir.path,
          ),
        );
      // Directory is empty; master exists in ancestor
      await runner.run(['init']);
      expect(
        messages,
        contains(
          'Cannot initialize a new workspace '
          'inside an existing Kidney workspace.',
        ),
      );
      // No child/master folder created
      expect(
        Directory(path.join(childDir.path, kidneyMasterFolder)).existsSync(),
        isFalse,
      );
    });

    test('prints help when --help is passed', () async {
      final runner = CommandRunner<void>('test', 'InitCommand Help')
        ..addCommand(
          InitCommand(
            ggLog: ggLog,
            rootPath: tempDir.path,
          ),
        );

      expect(
        () async {
          await runner.run(['init', '--help']);
        },
        returnsNormally,
      );
    });
  });
}
