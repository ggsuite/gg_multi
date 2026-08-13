// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_multi/src/commands/do/upgrade.dart';
import 'package:test/test.dart';

void main() {
  group('UpgradeCommand', () {
    final messages = <String>[];

    test('should register all subcommands', () async {
      // The subcommand implementations live in gg_multi_commit (deps)
      // and gg_multi_workspace (ocean), so the expected set is pinned
      // here instead of being derived from a directory listing.
      final upgradeCommand = UpgradeCommand(ggLog: messages.add);
      // 'master' is the legacy alias of the ocean subcommand.
      expect(
        upgradeCommand.subcommands.keys,
        unorderedEquals(['deps', 'ocean', 'master']),
      );
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
        contains('deps'),
        reason: 'Help should mention the deps subcommand.',
      );
    });
  });
}
