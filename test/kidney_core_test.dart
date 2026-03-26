// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:kidney_core/kidney_core.dart';
import 'package:path/path.dart';
import 'package:recase/recase.dart';
import 'package:test/test.dart';

void main() {
  final messages = <String>[];

  setUp(() {
    messages.clear();
  });

  group('KidneyCore()', () {
    // #########################################################################
    group('KidneyCore', () {
      final kidneyCore = KidneyCore(ggLog: messages.add);

      final CommandRunner<void> runner = CommandRunner<void>(
        'kidneyCore',
        'Description goes here.',
      )..addCommand(kidneyCore);

      test('should allow to run the code from command line', () async {
        await capturePrint(
          ggLog: messages.add,
          code: () async => await runner.run(['kidneyCore', 'ls', '--help']),
        );
        expect(
          messages.first,
          contains(
            'List repos, organizations, or dependencies.',
          ),
        );
      });

      // .......................................................................
      test('should show all sub commands', () async {
        // Update the directory path to use the correct path separator
        final commandsDir = Directory(
          'lib${Platform.pathSeparator}src${Platform.pathSeparator}commands',
        );
        final (subCommands, errorMessage) = await missingSubCommands(
          directory: commandsDir,
          command: kidneyCore,
        );

        expect(subCommands, isEmpty, reason: errorMessage);
      });
    });
  });
}

/// Returns a list of missing sub commands in directory
Future<(List<String> commandList, String? errorMessage)> missingSubCommands({
  required Directory directory,
  required Command<dynamic> command,
  List<String> additionalSubCommands = const [],
}) async {
  // Iterate all files in lib/src/commands
  // and check if they are added to the command runner
  // and if they are added to the help message
  final subCommands = directory
      .listSync(recursive: false)
      .where(
        (file) => file.path.endsWith('.dart'),
      )
      .map(
        (e) => basename(e.path)
            .replaceAll('.dart', '')
            .replaceAll('_', '-')
            .replaceAll('kidney-', '')
            .replaceAll('gg-', ''),
      )
      .toList()
    ..addAll(additionalSubCommands);

  final runner = CommandRunner<void>('runner', '');
  runner.addCommand(command);

  final messages = <String>[];

  await capturePrint(
    ggLog: messages.add,
    code: () => runner.run([command.name, '--help']),
  );

  final commandList = subCommands
      .where(
        (subCommand) => !hasLog(messages, subCommand),
      )
      .toList();

  final errorMessage = commandList.isNotEmpty
      ? 'The following sub commands needed to be added to '
          'class ${command.name.pascalCase}:\n'
          '- ${commandList.join(', ')}'
      : null;

  return (commandList, errorMessage);
}
