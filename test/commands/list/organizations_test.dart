// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:gg_multi/src/backend/constants.dart';
import 'package:test/test.dart';
import 'package:gg_multi/src/commands/list/organizations.dart';
import 'package:path/path.dart' as path;

import '../../rm_console_colors_helper.dart';

void main() {
  group('ListOrganizationsCommand', () {
    late Directory tempDir;
    late Directory masterDir;
    final messages = <String>[];

    void ggLog(String message) {
      messages.add(rmConsoleColors(message));
    }

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('list_org_test');
      masterDir = Directory(path.join(tempDir.path, ggMultiMasterFolder))
        ..createSync(recursive: true);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('lists organizations uniquely sorted', () async {
      final masterPath = masterDir.path;
      final repo1 = Directory(path.join(masterPath, 'repo1'))..createSync();
      File(path.join(repo1.path, 'pubspec.yaml'))
          .writeAsStringSync('name: repo1\nversion: 3.0.0');
      Directory(path.join(repo1.path, '.git')).createSync();
      File(path.join(repo1.path, '.git', 'config'))
          .writeAsStringSync('url = https://github.com/inlavigo/repo1.git');

      final repo2 = Directory(path.join(masterPath, 'repo2'))..createSync();
      File(path.join(repo2.path, 'pubspec.yaml'))
          .writeAsStringSync('name: repo2\nversion: 2.5.0');
      Directory(path.join(repo2.path, '.git')).createSync();
      File(path.join(repo2.path, '.git', 'config'))
          .writeAsStringSync('url = https://github.com/microsoft/repo2.git');

      final repo3 = Directory(path.join(masterPath, 'repo3'))..createSync();
      File(path.join(repo3.path, 'pubspec.yaml'))
          .writeAsStringSync('name: repo3\nversion: 1.0.0');
      Directory(path.join(repo3.path, '.git')).createSync();
      File(path.join(repo3.path, '.git', 'config'))
          .writeAsStringSync('url = https://github.com/inlavigo/repo3.git');

      final runner = CommandRunner<void>(
        'test',
        'Test ListOrganizationsCommand',
      );
      runner.addCommand(
        ListOrganizationsCommand(
          ggLog: ggLog,
          workspacePath: masterPath,
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
      final repo = Directory(path.join(masterPath, 'repo_unknown'))
        ..createSync();
      File(path.join(repo.path, 'pubspec.yaml'))
          .writeAsStringSync('name: repo_unknown\nversion: 1.0.0');
      Directory(path.join(repo.path, '.git')).createSync();
      File(path.join(repo.path, '.git', 'config'))
          .writeAsStringSync('invalid config content');

      final runner = CommandRunner<void>(
        'test',
        'Test ListOrganizationsCommand',
      );
      runner.addCommand(
        ListOrganizationsCommand(
          ggLog: ggLog,
          workspacePath: masterPath,
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
          ggLog: ggLog,
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
