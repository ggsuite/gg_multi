// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:test/test.dart';
import 'package:kidney_core/src/commands/list/organizations.dart';

void main() {
  group('ListOrganizationsCommand', () {
    late Directory tempDir;
    late Directory masterDir;
    final messages = <String>[];

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('list_org_test');
      masterDir = Directory(
        '${tempDir.path}${Platform.pathSeparator}kidney_ws_master',
      )..createSync(recursive: true);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('lists organizations uniquely sorted', () async {
      final masterPath = masterDir.path;
      final repo1 = Directory('$masterPath${Platform.pathSeparator}repo1')
        ..createSync();
      File('${repo1.path}${Platform.pathSeparator}pubspec.yaml')
          .writeAsStringSync('name: repo1\nversion: 3.0.0');
      Directory('${repo1.path}${Platform.pathSeparator}.git').createSync();
      File('${repo1.path}${Platform.pathSeparator}.git'
              '${Platform.pathSeparator}config')
          .writeAsStringSync('url = https://github.com/inlavigo/repo1.git');

      final repo2 = Directory('$masterPath${Platform.pathSeparator}repo2')
        ..createSync();
      File('${repo2.path}${Platform.pathSeparator}pubspec.yaml')
          .writeAsStringSync('name: repo2\nversion: 2.5.0');
      Directory('${repo2.path}${Platform.pathSeparator}.git').createSync();
      File('${repo2.path}${Platform.pathSeparator}.git'
              '${Platform.pathSeparator}config')
          .writeAsStringSync('url = https://github.com/microsoft/repo2.git');

      final repo3 = Directory('$masterPath${Platform.pathSeparator}repo3')
        ..createSync();
      File('${repo3.path}${Platform.pathSeparator}pubspec.yaml')
          .writeAsStringSync('name: repo3\nversion: 1.0.0');
      Directory('${repo3.path}${Platform.pathSeparator}.git').createSync();
      File('${repo3.path}${Platform.pathSeparator}.git'
              '${Platform.pathSeparator}config')
          .writeAsStringSync('url = https://github.com/inlavigo/repo3.git');

      final runner = CommandRunner<void>(
        'test',
        'Test ListOrganizationsCommand',
      );
      runner.addCommand(
        ListOrganizationsCommand(
          ggLog: messages.add,
          workspacePath: masterDir.path,
        ),
      );
      await runner.run(['organizations']);

      expect(
        messages,
        contains('inlavigo -- https://github.com/orgs/inlavigo/'),
      );
      expect(
        messages,
        contains('microsoft -- https://github.com/orgs/microsoft/'),
      );
    });

    test('handles unknown organization from invalid git config', () async {
      final masterPath = masterDir.path;
      final repo = Directory('$masterPath${Platform.pathSeparator}repo_unknown')
        ..createSync();
      File('${repo.path}${Platform.pathSeparator}pubspec.yaml')
          .writeAsStringSync('name: repo_unknown\nversion: 1.0.0');
      Directory('${repo.path}${Platform.pathSeparator}.git').createSync();
      File('${repo.path}${Platform.pathSeparator}.git'
              '${Platform.pathSeparator}config')
          .writeAsStringSync('invalid config content');

      final runner = CommandRunner<void>(
        'test',
        'Test ListOrganizationsCommand',
      );
      runner.addCommand(
        ListOrganizationsCommand(
          ggLog: messages.add,
          workspacePath: masterDir.path,
        ),
      );
      await runner.run(['organizations']);

      // The repository organization should be 'unknown'
      expect(messages, contains('unknown'));
    });

    test(
        'should print "No organizations found." '
        'if master workspace is empty', () async {
      final runner = CommandRunner<void>(
        'test',
        'Test ListOrganizationsCommand',
      );
      runner.addCommand(
        ListOrganizationsCommand(
          ggLog: messages.add,
          workspacePath: masterDir.path,
        ),
      );
      await runner.run(['organizations']);
      expect(messages, contains('No organizations found.'));
    });

    test('prints help message when --help is passed', () async {
      final runner = CommandRunner<void>(
        'test',
        'ListOrganizationsCommand Help',
      );
      runner.addCommand(
        ListOrganizationsCommand(
          ggLog: (_) {},
          workspacePath: masterDir.path,
        ),
      );
      final output = await capturePrint(
        code: () async {
          await runner.run(['organizations', '--help']);
        },
      );
      expect(output.first, contains('Lists all organizations'));
    });
  });
}
