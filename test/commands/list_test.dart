// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:kidney_core/src/backend/constants.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:kidney_core/src/commands/list.dart';

void main() {
  group('ListCommand', () {
    late Directory tempDir;
    late Directory masterDir;
    final messages = <String>[];

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('list_test');
      masterDir = Directory(
        path.join(tempDir.path, kidneyMasterFolder),
      )..createSync(recursive: true);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should show all sub commands', () async {
      final listCommand = ListCommand(
        ggLog: messages.add,
        workspacePath: masterDir.path,
      );
      // Update the directory path to use the correct path separator
      final commandsDir = Directory(
        path.join('lib', 'src', 'commands', 'list'),
      );
      final (subCommands, errorMessage) = await missingSubCommands(
        directory: commandsDir,
        command: listCommand,
      );

      expect(subCommands, isEmpty, reason: errorMessage);
    });

    test('prints help message when --help is passed', () async {
      final runner = CommandRunner<void>(
        'test',
        'ListCommand Help',
      );
      runner.addCommand(
        ListCommand(
          ggLog: (_) {},
          workspacePath: masterDir.path,
        ),
      );
      final output = await capturePrint(
        code: () async {
          await runner.run(['list', '--help']);
        },
      );
      expect(
        output.first,
        contains('List repos, organizations, or dependencies'),
      );
    });
  });
}
