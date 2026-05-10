// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_multi/src/commands/gg_multi_did.dart';
import 'package:test/test.dart';

void main() {
  group('DidCommand', () {
    late Directory tempDir;
    final messages = <String>[];

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('did_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should show all sub commands', () async {
      final didCommand = Did(ggLog: messages.add);
      final commandsDir = Directory(
        'lib${Platform.pathSeparator}src${Platform.pathSeparator}'
        'commands${Platform.pathSeparator}did',
      );
      final (subCommands, errorMessage) = await missingSubCommands(
        directory: commandsDir,
        command: didCommand,
      );

      expect(subCommands, isEmpty, reason: errorMessage);
    });

    test('prints help message when --help is passed', () async {
      final runner = CommandRunner<void>(
        'test',
        'DidCommand Help',
      );
      runner.addCommand(
        Did(ggLog: (_) {}),
      );
      final output = await capturePrint(
        code: () async {
          await runner.run(['did', '--help']);
        },
      );
      expect(
        output.first,
        contains('Checks if you already committed or pushed'),
      );
    });
  });
}
