// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_multi/src/commands/gg_multi_do.dart';
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
      // The subcommand implementations live in the gg_multi_* packages,
      // so the expected set is pinned here instead of being derived from
      // a directory listing. configure-publish is deliberately not
      // registered — `do publish` runs it automatically when needed.
      final doCommand = Do(ggLog: messages.add);
      expect(
        doCommand.subcommands.keys,
        unorderedEquals([
          'add',
          'code',
          'commit',
          'create',
          'exec',
          'import',
          'init',
          'ls',
          'publish',
          'push',
          'review',
          'rm',
          'upgrade',
        ]),
      );
    });

    test('prints help message when --help is passed', () async {
      final runner = CommandRunner<void>('test', 'DoCommand Help');
      runner.addCommand(Do(ggLog: (_) {}));
      final output = await capturePrint(
        code: () async {
          await runner.run(['do', '--help']);
        },
      );
      expect(output.first, contains('Act on all repos of the current ticket'));
    });
  });
}
