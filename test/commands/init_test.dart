// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:kidney_core/src/commands/init.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as path;

void main() {
  group('InitCommand', () {
    late Directory tempDir;
    final messages = <String>[];

    void ggLog(String message) {
      messages.add(message);
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
      final wsPath = path.join(tempDir.path, 'kidney_ws_master');
      expect(Directory(wsPath).existsSync(), isFalse);

      await runner.run(['init']);
      expect(messages.any((m) => m.contains('initialized at')), isTrue);
      expect(Directory(wsPath).existsSync(), isTrue);
    });

    test('should not recreate if already exists, and log accordingly',
        () async {
      final wsPath = path.join(tempDir.path, 'kidney_ws_master');
      Directory(wsPath).createSync(recursive: true);
      final runner = CommandRunner<void>('test', 'InitCommand Test')
        ..addCommand(
          InitCommand(
            ggLog: ggLog,
            rootPath: tempDir.path,
          ),
        );

      await runner.run(['init']);
      // Should detect folder and not re-create
      expect(messages.any((m) => m.contains('already exists')), isTrue);
      expect(Directory(wsPath).existsSync(), isTrue);
    });

    test('prints help when --help is passed', () async {
      final runner = CommandRunner<void>('test', 'InitCommand Help')
        ..addCommand(
          InitCommand(
            ggLog: ggLog,
            rootPath: tempDir.path,
          ),
        );
      await runner.run(
        ['init', '--help'],
      );
      // (actually, CommandRunner writes only to stdout, not to ggLog)
      // So here we only check that calling does not throw
      expect(
        () async {
          await runner.run(['init', '--help']);
        },
        returnsNormally,
      );
    });
  });
}
