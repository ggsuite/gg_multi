// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:kidney_core/src/commands/add.dart';
import 'package:kidney_core/src/backend/git_handler.dart';

import '../rm_console_colors_helper.dart';

// Create a mock for GitCloner
class MockGitCloner extends Mock implements GitHandler {}

typedef RepoFetcher = Future<http.Response> Function(Uri uri);

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

    setUp(() {
      mockGitCloner = MockGitCloner();
      logMessages = [];
      when(() => mockGitCloner.cloneRepo(any(), any()))
          .thenAnswer((_) async {});
      tempDir = Directory.systemTemp.createTempSync('add_test');
      masterWorkspacePath = path.join(tempDir.path, 'kidney_ws_master');
      Directory(masterWorkspacePath).createSync(recursive: true);
      runner = CommandRunner<void>('test', 'Test for AddCommand');
      runner.addCommand(
        AddCommand(
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: masterWorkspacePath,
        ),
      );
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
          'Added repository kidney_core from https://github.com/ggsuite/kidney_core.git',
        ]),
      );
    });

    test(
        'should clone repositories when '
        'target is an organization URL', () async {
      final orgRunner = CommandRunner<void>('test', 'Test for AddCommand Org');
      orgRunner.addCommand(
        AddCommand(
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: masterWorkspacePath,
          repoFetcher: (uri) async {
            final expectedApi =
                Uri.parse('https://api.github.com/orgs/myorganization/repos');
            expect(uri, equals(expectedApi));
            final fakeRepos = [
              {
                'name': 'repo1',
                'clone_url': 'https://github.com/myorganization/repo1.git',
              },
              {
                'name': 'repo2',
                'clone_url': 'https://github.com/myorganization/repo2.git',
              }
            ];
            return http.Response(jsonEncode(fakeRepos), 200);
          },
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

    test('should throw exception when API returns error status', () async {
      final orgRunner = CommandRunner<void>(
        'test',
        'Test for AddCommand Org Error',
      );
      orgRunner.addCommand(
        AddCommand(
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: masterWorkspacePath,
          repoFetcher: (uri) async {
            final expectedApi =
                Uri.parse('https://api.github.com/orgs/errororg/repos');
            expect(uri, equals(expectedApi));
            return http.Response('Not found', 404);
          },
        ),
      );
      const orgUrl = 'https://github.com/errororg';
      expect(
        () => orgRunner.run(['add', orgUrl]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'toString',
            contains('Failed to fetch repositories for '
                'organization errororg: Not found'),
          ),
        ),
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
          workspacePath: masterWorkspacePath,
          repoFetcher: (uri) async {
            return http.Response('[]', 200);
          },
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
          path.join(tempDir.path, 'tickets', 'TICKET'),
        )..createSync(recursive: true);
        final originalCwd = Directory.current;
        Directory.current = ticketDir;
        try {
          // Act
          await runner.run(['add', repoName]);
        } finally {
          // Restore cwd
          Directory.current = originalCwd;
        }

        // Assert: ensure the target file has been copied
        final copiedFileInTicket = File(
          path.join(ticketDir.path, repoName, 'target.txt'),
        );
        expect(copiedFileInTicket.existsSync(), isTrue);
        expect(
          logMessages,
          equals([
            'Added repository $repoName to ticket workspace.',
          ]),
        );
      },
    );

    // New test to cover error when master workspace missing repository
    test('logs error when repo not found in master workspace', () async {
      // Arrange: use clone stub that does nothing (no directory creation)
      // Setup ticket workspace and change cwd
      final ticketDir = Directory(
        path.join(tempDir.path, 'tickets', 'TICKET-MISSING'),
      )..createSync(recursive: true);
      final originalCwd = Directory.current;
      Directory.current = ticketDir;
      try {
        // Act: attempt to add a repo that hasn't been cloned
        await runner.run(['add', 'nonexistent']);
        // Assert: error message logged about missing repo in master
        expect(
          logMessages,
          contains('Repository nonexistent not found in master workspace.'),
        );
      } finally {
        // Restore cwd
        Directory.current = originalCwd;
      }
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
      final ticketDir = Directory(path.join(tempDir.path, 'tickets', 'ALREADY'))
        ..createSync(recursive: true);
      final destination = Directory(path.join(ticketDir.path, repoName));
      destination.createSync(
        recursive: true,
      ); // repo already exists in the ticket workspace
      File(path.join(destination.path, 'foo.txt')).writeAsStringSync('hi');
      final originalCwd = Directory.current;
      Directory.current = ticketDir;
      try {
        await runner.run(['add', repoName]);

        expect(
          logMessages,
          contains('$repoName already exists in ticket workspace.'),
        );
      } finally {
        Directory.current = originalCwd;
      }
    });
  });
}
