// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights
// Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_multi/src/commands/do/merge.dart';
import 'package:gg_multi/src/commands/do/publish.dart';
import 'package:test/test.dart';

void main() {
  final messages = <String>[];

  setUp(messages.clear);

  group('DoMergeCommand', () {
    test('is a publish command running in merge mode', () {
      final command = DoMergeCommand(ggLog: messages.add);
      expect(command, isA<DoPublishCommand>());
      expect(command.name, 'merge');
      expect(command.mergeOnly, isTrue);
      expect(command.description, contains('without publishing'));
    });

    test('offers --force to bypass the localized-refs guard', () {
      final command = DoMergeCommand(ggLog: messages.add);
      expect(command.argParser.options.keys, contains('force'));
    });

    test('can be added to a command runner', () {
      final runner = CommandRunner<void>('test', 'test')
        ..addCommand(DoMergeCommand(ggLog: messages.add));
      expect(runner.commands.keys, contains('merge'));
    });

    test('the mock can be used', () {
      expect(MockDoMergeCommand(), isA<DoMergeCommand>());
    });
  });
}
