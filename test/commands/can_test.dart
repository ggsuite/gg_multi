// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';

import 'package:gg_args/gg_args.dart';

import 'package:gg_capture_print/gg_capture_print.dart';

import 'package:kidney_core/src/commands/can.dart';

import 'package:test/test.dart';

void main() {
  group('CanCommand', () {
    late Directory tempDir;
    final messages = <String>[];

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('can_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should show all sub commands', () async {
      final canCommand = Can(ggLog: messages.add);
      // Update the directory path to use the correct path separator
      final commandsDir = Directory(
        'lib${Platform.pathSeparator}src${Platform.pathSeparator}'
        'commands${Platform.pathSeparator}can',
      );
      final (subCommands, errorMessage) = await missingSubCommands(
        directory: commandsDir,
        command: canCommand,
      );

      expect(subCommands, isEmpty, reason: errorMessage);
    });

    test('prints help message when --help is passed', () async {
      final runner = CommandRunner<void>(
        'test',
        'CanCommand Help',
      );
      runner.addCommand(
        Can(ggLog: (_) {}),
      );
      final output = await capturePrint(
        code: () async {
          await runner.run(['can', '--help']);
        },
      );
      expect(
        output.first,
        contains('Checks if you can commit or push for the current ticket.'),
      );
    });
  });
}
