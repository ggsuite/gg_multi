// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:test/test.dart';
import 'package:kidney_core/src/commands/add.dart';
import 'package:kidney_core/src/commands/add/organization.dart';
import 'package:kidney_core/src/backend/constants.dart';
import 'package:path/path.dart' as path;
import '../../rm_console_colors_helper.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kidney_core/src/backend/git_handler.dart';

// A dummy GitHandler mock
class MockGitCloner extends Mock implements GitHandler {}

dynamic readOrganizationsFile(String ws) {
  final file = File(path.join(ws, '.organizations'));
  return file.existsSync() ? jsonDecode(file.readAsStringSync()) : null;
}

void main() {
  group('kidney_core add organization', () {
    late Directory tempDir;
    late Directory masterDir;
    late String masterWorkspacePath;
    late List<String> logMessages;
    late CommandRunner<void> runner;
    late MockGitCloner mockGitCloner;
    void ggLog(String message) => logMessages.add(rmConsoleColors(message));

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('addorg_test_');
      masterDir = Directory(path.join(tempDir.path, kidneyMasterFolder))
        ..createSync(recursive: true);
      masterWorkspacePath = masterDir.path;
      logMessages = [];
      mockGitCloner = MockGitCloner();
      runner = CommandRunner<void>('test', 'add organization')
        ..addCommand(
          AddCommand(
            ggLog: ggLog,
            gitCloner: mockGitCloner,
            masterWorkspacePath: masterWorkspacePath,
          ),
        );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('adds new organization by name', () async {
      await runner.run(['add', 'organization', 'myorg']);
      final fileObj = File(path.join(masterWorkspacePath, '.organizations'));
      expect(fileObj.existsSync(), isTrue);
      final orgs = readOrganizationsFile(masterWorkspacePath);
      expect(orgs['myorg'], 'https://github.com/myorg/');
      expect(
        logMessages,
        contains('Added organization myorg.'),
      );
      verifyNever(() => mockGitCloner.cloneRepo(any(), any()));
    });

    test('does not add organization twice', () async {
      // First add
      await runner.run(['add', 'organization', 'myorg']);
      final orgs1 = readOrganizationsFile(masterWorkspacePath);
      expect(orgs1['myorg'], isNotNull);
      logMessages.clear();
      // Second add
      await runner.run(['add', 'organization', 'myorg']);
      final orgs2 = readOrganizationsFile(masterWorkspacePath);
      expect(orgs2, orgs1, reason: 'Should not change .organizations');
      expect(
        logMessages,
        contains('Organization myorg already exists.'),
      );
    });

    test('adds organization by URL', () async {
      await runner.run([
        'add',
        'organization',
        'https://gitlab.com/foo/',
      ]);
      final orgs = readOrganizationsFile(masterWorkspacePath);
      expect(orgs['foo'], 'https://gitlab.com/foo/');
      expect(
        logMessages,
        contains('Added organization foo.'),
      );
    });

    test('throws UsageException when missing parameter', () async {
      await expectLater(
        () => runner.run(['add', 'organization']),
        throwsA(isA<UsageException>()),
      );
    });

    test('does not add org if org name cannot be determined', () async {
      await runner.run([
        'add',
        'organization',
        'notAValidUrl', // this becomes https://github.com/notAValidUrl
      ]);
      final orgs = readOrganizationsFile(masterWorkspacePath);
      expect(orgs.containsKey('notAValidUrl'), isTrue);

      final badRunner = CommandRunner<void>('test', 'bad org')
        ..addCommand(
          AddOrganizationCommand(
            ggLog: ggLog,
            workspacePath: masterWorkspacePath,
          ),
        );
      await badRunner.run(['organization', '!!??!!']);
      expect(
        logMessages.last,
        contains('Could not determine organization name'),
      );
    });

    test('AddOrganizationCommand throws UsageException for missing arg',
        () async {
      final cmdRunner = CommandRunner<void>('test', 'single org')
        ..addCommand(
          AddOrganizationCommand(
            ggLog: ggLog,
            workspacePath: masterWorkspacePath,
          ),
        );
      await expectLater(
        () => cmdRunner.run(['organization']),
        throwsA(isA<UsageException>()),
      );
    });
  });
}
