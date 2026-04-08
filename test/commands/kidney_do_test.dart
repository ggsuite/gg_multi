// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:kidney_core/src/commands/kidney_do.dart';
import 'package:test/test.dart';

void main() {
  group('DoCommand', () {
    late Directory tempDir;
    final messages = <String>[];

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('do_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should show all sub commands', () async {
      final doCommand = Do(ggLog: messages.add);
      // Update the directory path to use the correct path separator
      final commandsDir = Directory(
        'lib${Platform.pathSeparator}src${Platform.pathSeparator}'
        'commands${Platform.pathSeparator}do',
      );
      final (subCommands, errorMessage) = await missingSubCommands(
        directory: commandsDir,
        command: doCommand,
        additionalSubCommands: [
          'commit',
          'push',
          'publish',
          'review',
          'install-git-hooks',
          'cancel-review',
        ],
      );

      expect(subCommands, isEmpty, reason: errorMessage);
    });

    test('prints help message when --help is passed', () async {
      final runner = CommandRunner<void>(
        'test',
        'DoCommand Help',
      );
      runner.addCommand(
        Do(ggLog: (_) {}),
      );
      final output = await capturePrint(
        code: () async {
          await runner.run(['do', '--help']);
        },
      );
      expect(
        output.first,
        contains('Perform actions like committing, pushing or '
            'reviewing across ticket repositories.'),
      );
    });
  });
}
