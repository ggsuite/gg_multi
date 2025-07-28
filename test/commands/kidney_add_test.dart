// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:kidney_core/src/backend/constants.dart';
import 'package:kidney_core/src/backend/git_platform.dart';
import 'package:kidney_core/src/backend/organization.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:kidney_core/src/commands/kidney_add.dart';
import 'package:kidney_core/src/backend/git_handler.dart';

import '../rm_console_colors_helper.dart';

// Create a mock for GitCloner
class MockGitCloner extends Mock implements GitHandler {}

class MockGitHubPlatform extends Mock implements GitHubPlatform {}

void main() {
  group('AddCommand', () {
    late MockGitCloner mockGitCloner;
    late List<String> logMessages;
    late CommandRunner<void> runner;
    late Directory tempDir;
    late String masterWorkspacePath;

    void ggLog(String message) {
      logMessages.add(rmConsoleColors(message));
    }

    void createRunner({
      String? executionPath,
      Future<void> Function(String repoPath)? localizeRefsFn,
    }) {
      runner = CommandRunner<void>('test', 'Test for AddCommand');
      runner.addCommand(
        AddCommand(
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          masterWorkspacePath: masterWorkspacePath,
          executionPath: executionPath ?? Directory.current.path,
        ),
      );
    }

    setUp(() {
      mockGitCloner = MockGitCloner();
      logMessages = [];
      when(() => mockGitCloner.cloneRepo(any(), any()))
          .thenAnswer((_) async {});
      tempDir = Directory.systemTemp.createTempSync('add_test');
      masterWorkspacePath = path.join(tempDir.path, kidneyMasterFolder);
      Directory(masterWorkspacePath).createSync(recursive: true);
      createRunner();
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should clone single repository when target is a repo name', () async {
      await runner.run(['add', 'myrepo']);
      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/myrepo/myrepo.git',
          any(),
        ),
      ).called(1);
      expect(
        logMessages,
        equals([
          'Added repository myrepo from https://github.com/myrepo/myrepo.git',
        ]),
      );

      // Integration check: .organizations file correctly updated
      final orgFile = File(path.join(masterWorkspacePath, '.organizations'));
      expect(orgFile.existsSync(), isTrue);
      final orgMap = (jsonDecode(orgFile.readAsStringSync()) as List<dynamic>)
          .map((e) => Organization.fromMap(e as Map<String, dynamic>))
          .toList();
      expect(orgMap.first.url, 'https://github.com/myrepo/');
    });

    test(
        'should clone single repository when target is in username/repo format',
        () async {
      await runner.run(['add', 'testuser/testrepo']);
      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/testuser/testrepo.git',
          any(),
        ),
      ).called(1);
      expect(
        logMessages,
        equals([
          'Added repository testrepo from '
              'https://github.com/testuser/testrepo.git',
        ]),
      );
    });

    test(
        'should clone single repository when target '
        'is a full repository URL with .git', () async {
      const repoUrl = 'https://gitlab.com/someuser/somerepo.git';
      await runner.run(['add', repoUrl]);
      verify(() => mockGitCloner.cloneRepo(repoUrl, any())).called(1);
      expect(
        logMessages,
        equals([
          'Added repository somerepo from $repoUrl',
        ]),
      );
    });

    test(
        'should clone single repository '
        'when target is a git SSH URL', () async {
      const repoUrl = 'git@github.com:ggsuite/kidney_core.git';
      await runner.run(['add', repoUrl]);
      verify(
        () => mockGitCloner.cloneRepo(
          repoUrl,
          any(),
        ),
      ).called(1);
      expect(
        logMessages,
        equals([
          'Added repository kidney_core from $repoUrl',
        ]),
      );
    });

    test(
        'should clone single repository when '
        'target is a URL without .git', () async {
      const urlWithoutGit = 'https://github.com/ggsuite/kidney_core';
      await runner.run(['add', urlWithoutGit]);
      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/ggsuite/kidney_core.git',
          any(),
        ),
      ).called(1);
      expect(
        logMessages,
        equals([
          'Added repository kidney_core from '
              'https://github.com/ggsuite/kidney_core.git',
        ]),
      );
    });

    test(
        'should clone single repository '
        'when target is a URL with trailing #', () async {
      const urlWithHash = 'https://github.com/ggsuite/kidney_core#';
      await runner.run(['add', urlWithHash]);
      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/ggsuite/kidney_core.git',
          any(),
        ),
      ).called(1);
      expect(
        logMessages,
        equals([
          'Added repository kidney_core from '
              'https://github.com/ggsuite/kidney_core.git',
        ]),
      );
    });

    test(
        'should clone repositories when '
        'target is an organization URL', () async {
      final repoList = [
        {
          'name': 'repo1',
          'clone_url': 'https://github.com/myorganization/repo1.git',
        },
        {
          'name': 'repo2',
          'clone_url': 'https://github.com/myorganization/repo2.git',
        },
      ];

      final mockGitHubPlatform = MockGitHubPlatform();
      when(
        () => mockGitHubPlatform.fetchOrgRepos(
          any(),
          client: any(named: 'client'),
        ),
      ).thenAnswer((_) async => repoList);

      final orgRunner = CommandRunner<void>('test', 'Test for AddCommand Org');
      orgRunner.addCommand(
        AddCommand(
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          gitHubPlatform: mockGitHubPlatform,
          masterWorkspacePath: masterWorkspacePath,
        ),
      );
      const orgUrl = 'https://github.com/myorganization';
      await orgRunner.run(['add', orgUrl]);
      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/myorganization/repo1.git',
          any(),
        ),
      ).called(1);
      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/myorganization/repo2.git',
          any(),
        ),
      ).called(1);
      expect(
        logMessages,
        containsAllInOrder([
          'Added repository repo1 from '
              'https://github.com/myorganization/repo1.git',
          'Added repository repo2 from '
              'https://github.com/myorganization/repo2.git',
        ]),
      );
    });

    test('should throw UsageException when target parameter is missing',
        () async {
      expect(
        () => runner.run(['add']),
        throwsA(isA<UsageException>()),
      );
    });

    test('should throw exception when invalid organization URL is provided',
        () async {
      final invalidRunner = CommandRunner<void>(
        'test',
        'Test for AddCommand Invalid Org',
      );
      invalidRunner.addCommand(
        AddCommand(
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          masterWorkspacePath: masterWorkspacePath,
        ),
      );
      const invalidOrgUrl = 'https://github.com/';
      expect(
        () => invalidRunner.run(['add', invalidOrgUrl]),
        throwsA(isA<Exception>()),
      );
    });

    test(
        'should log already added when destination '
        'exists and --force not provided', () async {
      // Arrange: create an existing non-empty directory
      const repoName = 'kidney_core';
      final destination = path.join(masterWorkspacePath, repoName);
      Directory(destination).createSync(recursive: true);
      File(path.join(destination, 'dummy.txt')).writeAsStringSync('data');

      await runner.run(['add', 'git@github.com:ggsuite/kidney_core.git']);

      verifyNever(() => mockGitCloner.cloneRepo(any(), any()));
      expect(logMessages, contains('$repoName already added.'));
    });

    test(
        'should force clone repository when --force '
        'is provided even if destination exists', () async {
      // Arrange: create an existing non-empty directory
      const repoName = 'kidney_core';
      final destination = path.join(masterWorkspacePath, repoName);
      Directory(destination).createSync(recursive: true);
      File(path.join(destination, 'dummy.txt')).writeAsStringSync('data');

      await runner
          .run(['add', 'git@github.com:ggsuite/kidney_core.git', '--force']);

      verify(() => mockGitCloner.cloneRepo(any(), any())).called(1);
    });

    test(
      'copies repo into ticket workspace',
      () async {
        // Arrange: create a repo with a file and a symbolic link
        const repoName = 'testRepo';
        final repoDir = Directory(
          path.join(masterWorkspacePath, repoName),
        )..createSync(recursive: true);
        // Create a file inside the repo
        final fileInRepo = File(path.join(repoDir.path, 'target.txt'));
        fileInRepo.writeAsStringSync('content');

        // Setup ticket workspace and change cwd
        final ticketDir = Directory(
          path.join(tempDir.path, kidneyTicketFolder, 'TICKET'),
        )..createSync(recursive: true);
        createRunner(executionPath: ticketDir.path);

        // Act
        await runner.run(['add', repoName]);

        // Assert: ensure the target file has been copied
        final copiedFileInTicket = File(
          path.join(ticketDir.path, repoName, 'target.txt'),
        );
        expect(copiedFileInTicket.existsSync(), isTrue);
        expect(
          logMessages,
          contains(
            'Added repository $repoName to ticket workspace.',
          ),
        );
      },
    );

    // New test to cover error when master workspace missing repository
    test('logs error when repo not found in master workspace', () async {
      // Arrange: use clone stub that does nothing (no directory creation)
      // Setup ticket workspace and change cwd
      final ticketDir = Directory(
        path.join(tempDir.path, kidneyTicketFolder, 'TICKET-MISSING'),
      )..createSync(recursive: true);
      createRunner(executionPath: ticketDir.path);

      // Act: attempt to add a repo that hasn't been cloned
      await runner.run(['add', 'nonexistent']);
      // Assert: error message logged about missing repo in master
      expect(
        logMessages,
        contains('Repository nonexistent not found in master workspace.'),
      );
    });

    // Added test to cover: logs gray message
    // if repository already exists in ticket workspace
    test('logs already exists in ticket workspace if copied before', () async {
      // Arrange: create the repo in master
      const repoName = 'someGreyRepo';
      final repoDir = Directory(path.join(masterWorkspacePath, repoName))
        ..createSync(recursive: true);
      File(path.join(repoDir.path, 'foo.txt')).writeAsStringSync('hi');

      // Prepare ticket workspace and change cwd
      final ticketDir = Directory(
        path.join(tempDir.path, kidneyTicketFolder, 'ALREADY'),
      )..createSync(recursive: true);
      createRunner(executionPath: ticketDir.path);
      final destination = Directory(path.join(ticketDir.path, repoName));
      destination.createSync(
        recursive: true,
      ); // repo already exists in the ticket workspace
      File(path.join(destination.path, 'foo.txt')).writeAsStringSync('hi');

      await runner.run(['add', repoName]);

      expect(
        logMessages,
        contains('$repoName already exists in ticket workspace.'),
      );
    });

    // Test: when localizeRefs fails in ticket copy, error branch is logged
    test('logs error when localizeRefs fails in ticket workspace', () async {
      // Arrange: create the repo in master
      const repoName = 'buggyRepo';
      final repoDir = Directory(path.join(masterWorkspacePath, repoName))
        ..createSync(recursive: true);
      File(path.join(repoDir.path, 'file.txt')).writeAsStringSync('hello');
      final ticketDir = Directory(
        path.join(tempDir.path, kidneyTicketFolder, 'REFFAIL'),
      )..createSync(recursive: true);
      // Use a localizeRefs function that throws
      Future<void> failingLocalizeRefs(String repoPath) async {
        throw Exception('mock localize error');
      }

      createRunner(
        executionPath: ticketDir.path,
        localizeRefsFn: failingLocalizeRefs,
      );
      await runner.run(['add', repoName]);
      expect(
        logMessages,
        contains(
          'Failed to localize refs for REFFAIL: Exception: An error occurred: '
          'Exception: No project root found. No files were changed.',
        ),
      );
    });

    test('clones multiple repositories when multiple targets provided',
        () async {
      // Arrange
      when(() => mockGitCloner.cloneRepo(any(), any()))
          .thenAnswer((_) async {});
      // Act
      await runner.run(['add', 'repoA', 'repoB']);
      // Assert: two distinct cloneRepo calls
      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/repoA/repoA.git',
          any(),
        ),
      ).called(1);
      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/repoB/repoB.git',
          any(),
        ),
      ).called(1);
      // And logs for both
      expect(
        logMessages,
        contains('Added repository repoA from '
            'https://github.com/repoA/repoA.git'),
      );
      expect(
        logMessages,
        contains('Added repository repoB from '
            'https://github.com/repoB/repoB.git'),
      );
    });
  });
}
