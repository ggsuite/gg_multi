// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_multi/src/commands/gg_multi_can.dart';
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
      // The subcommand implementations live in gg_multi_commit and
      // gg_multi_do_publish, so the expected set is pinned here instead
      // of being derived from a directory listing.
      final canCommand = Can(ggLog: messages.add);
      expect(
        canCommand.subcommands.keys,
        unorderedEquals(['commit', 'push', 'publish', 'review']),
      );
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
        contains('Perform checks on the ticket'),
      );
    });
  });
}
