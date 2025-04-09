// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:kidney_core/src/backend/git_cloner.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'package:kidney_core/src/commands/add.dart';

// Create a mock for GitCloner
class MockGitCloner extends Mock implements GitCloner {}

void main() {
  group('AddCommand', () {
    late MockGitCloner mockGitCloner;
    late List<String> logMessages;
    late CommandRunner<void> runner;

    setUp(() {
      mockGitCloner = MockGitCloner();
      logMessages = [];
      // Simulate successful cloning for single repository cases
      when(() => mockGitCloner.cloneRepo(any(), any()))
          .thenAnswer((_) async {});
      runner = CommandRunner<void>('test', 'Test for AddCommand');
      runner.addCommand(
        AddCommand(
          ggLog: logMessages.add,
          gitCloner: mockGitCloner,
        ),
      );
    });

    test('should clone single repository when target is a repo name', () async {
      await runner.run(['add', 'myrepo']);
      // Expected URL for a repo name is 'https://github.com/myrepo/myrepo.git'
      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/myrepo/myrepo.git',
          any(),
        ),
      ).called(1);
      expect(
        logMessages,
        equals([
          'added repository myrepo from https://github.com/myrepo/myrepo.git',
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
          'added repository testrepo from '
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
          'added repository somerepo from $repoUrl',
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
          'added repository kidney_core from $repoUrl',
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
          'added repository kidney_core from '
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
          'added repository kidney_core from https://github.com/ggsuite/kidney_core.git',
        ]),
      );
    });

    test(
        'should clone repositories when '
        'target is an organization URL', () async {
      // Create a separate runner with a custom
      // repoFetcher to simulate GitHub API response
      final orgRunner = CommandRunner<void>('test', 'Test for AddCommand Org');
      orgRunner.addCommand(
        AddCommand(
          ggLog: logMessages.add,
          gitCloner: mockGitCloner,
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
          'added repository repo1 from '
              'https://github.com/myorganization/repo1.git',
          'added repository repo2 from '
              'https://github.com/myorganization/repo2.git',
        ]),
      );
    });

    test(
        'should log no repositories found when organization repo list is empty',
        () async {
      final orgRunner =
          CommandRunner<void>('test', 'Test for AddCommand Org Empty');
      orgRunner.addCommand(
        AddCommand(
          ggLog: logMessages.add,
          gitCloner: mockGitCloner,
          repoFetcher: (uri) async {
            final expectedApi =
                Uri.parse('https://api.github.com/orgs/emptyorg/repos');
            expect(uri, equals(expectedApi));
            return http.Response('[]', 200);
          },
        ),
      );
      const orgUrl = 'https://github.com/emptyorg';
      await orgRunner.run(['add', orgUrl]);
      expect(
        logMessages,
        contains('No repositories found for organization emptyorg'),
      );
    });

    test('should throw exception when API returns error status', () async {
      final orgRunner =
          CommandRunner<void>('test', 'Test for AddCommand Org Error');
      orgRunner.addCommand(
        AddCommand(
          ggLog: logMessages.add,
          gitCloner: mockGitCloner,
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
          ggLog: logMessages.add,
          gitCloner: mockGitCloner,
          repoFetcher: (uri) async {
            // This should not be called as the URL is invalid
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
  });
}
