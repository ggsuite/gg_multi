// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:test/test.dart';
import 'package:gg_multi/src/commands/do/maintain.dart';

void main() {
  group('MaintainCommand', () {
    final messages = <String>[];

    test('should register all subcommands', () async {
      final maintainCommand = MaintainCommand(ggLog: messages.add);
      final commandsDir = Directory(
        'lib${Platform.pathSeparator}src${Platform.pathSeparator}'
        'commands${Platform.pathSeparator}do${Platform.pathSeparator}maintain',
      );
      final (subCommands, errorMessage) = await missingSubCommands(
        directory: commandsDir,
        command: maintainCommand,
      );
      expect(subCommands, isEmpty, reason: errorMessage);
    });

    test('prints help message including exec', () async {
      final runner = CommandRunner<void>(
        'test',
        'MaintainCommand Help',
      )..addCommand(MaintainCommand(ggLog: (_) {}));

      final output = await capturePrint(
        code: () async {
          await runner.run(['maintain', '--help']);
        },
      );

      expect(
        output.last,
        contains('exec'),
        reason: 'Help should mention the exec subcommand.',
      );
    });
  });
}
