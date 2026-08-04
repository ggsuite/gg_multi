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
import 'package:gg_multi/src/commands/do/upgrade.dart';

void main() {
  group('UpgradeCommand', () {
    final messages = <String>[];

    test('should register all subcommands', () async {
      final upgradeCommand = UpgradeCommand(ggLog: messages.add);
      final commandsDir = Directory(
        'lib${Platform.pathSeparator}src${Platform.pathSeparator}'
        'commands${Platform.pathSeparator}do${Platform.pathSeparator}upgrade',
      );
      final (subCommands, errorMessage) = await missingSubCommands(
        directory: commandsDir,
        command: upgradeCommand,
      );
      expect(subCommands, isEmpty, reason: errorMessage);
    });

    test('prints help message including ocean', () async {
      final runner = CommandRunner<void>(
        'test',
        'UpgradeCommand Help',
      )..addCommand(UpgradeCommand(ggLog: (_) {}));

      final output = await capturePrint(
        code: () async {
          await runner.run(['upgrade', '--help']);
        },
      );

      expect(
        output.last,
        contains('ocean'),
        reason: 'Help should mention the ocean subcommand.',
      );

      expect(
        output.last,
        contains('dependencies'),
        reason: 'Help should mention the dependencies subcommand.',
      );
    });
  });
}
