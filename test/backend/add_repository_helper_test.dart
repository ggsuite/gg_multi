// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';

import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'package:kidney_core/src/backend/add_repository_helper.dart';
import 'package:kidney_core/src/backend/git_cloner.dart';

// Mock for GitCloner using mocktail
class MockGitCloner extends Mock implements GitCloner {}

// Dummy implementation for repoFetcher in tests
typedef RepoFetcher = Future<http.Response> Function(Uri uri);

void main() {
  // Common variables used in tests
  late List<String> logs;
  late String workspacePath;

  // Setup a simple ggLog function that appends messages to logs list
  void ggLog(String message) {
    logs.add(message);
  }

  setUp(() {
    logs = [];
    // For testing, we use a dummy workspace path
    workspacePath = 'dummy_workspace';
  });

  group('addRepositoryHelper', () {
    group('HTTP target', () {
      test('Processes repository URL and cleans trailing #', () async {
        // This test covers the branch when
        // targetArg starts with http and is a repository URL
        const targetArg = 'http://github.com/user/repo#';
        final mockGitCloner = MockGitCloner();
        // Stub cloneRepo to complete normally
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        // Dummy repoFetcher that should never be used in this branch
        Future<http.Response> repoFetcher(Uri uri) async {
          fail('repoFetcher should not be called for repository URL branch');
        }

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          repoFetcher: repoFetcher,
          workspacePath: workspacePath,
        );

        // The URL should have the trailing '#' removed and appended with .git
        const expectedRepoUrl = 'http://github.com/user/repo.git';
        final expectedDestination = path.join(workspacePath, 'repo');

        // Verify cloneRepo was called with correct parameters
        verify(
          () => mockGitCloner.cloneRepo(
            expectedRepoUrl,
            expectedDestination,
          ),
        ).called(1);

        // Verify ggLog contains the correct success message
        expect(logs, contains('added repository repo from $expectedRepoUrl'));
      });

      test('Processes organization URL and clones multiple repos', () async {
        // Test for the organization URL branch
        // where the URL has less than 2 path segments.
        const targetArg = 'http://github.com/myorg';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        // Build a fake repo list response with two repositories
        final repoList = [
          {'name': 'repo1', 'clone_url': 'https://github.com/myorg/repo1.git'},
          {'name': 'repo2', 'clone_url': 'https://github.com/myorg/repo2.git'},
        ];

        Future<http.Response> repoFetcher(Uri uri) async {
          // Expect the URL to be https://api.github.com/orgs/myorg/repos
          expect(
            uri.toString(),
            equals('https://api.github.com/orgs/myorg/repos'),
          );
          return http.Response(jsonEncode(repoList), 200);
        }

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          repoFetcher: repoFetcher,
          workspacePath: workspacePath,
        );

        // Verify cloneRepo called for each repository
        for (final repo in repoList) {
          final repoName = repo['name']!;
          final cloneUrl = repo['clone_url']!;
          final destination = path.join(workspacePath, repoName);
          verify(() => mockGitCloner.cloneRepo(cloneUrl, destination))
              .called(1);
          expect(logs, contains('added repository $repoName from $cloneUrl'));
        }
      });

      test('Processes organization URL with empty repo list', () async {
        // Test organization branch when no repositories are found
        const targetArg = 'http://github.com/myorg';
        final mockGitCloner = MockGitCloner();
        // Since no repos found, cloneRepo should not be called
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        Future<http.Response> repoFetcher(Uri uri) async {
          return http.Response(jsonEncode([]), 200);
        }

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          repoFetcher: repoFetcher,
          workspacePath: workspacePath,
        );

        // Expect ggLog to log that no repositories were found
        expect(logs, contains('No repositories found for organization myorg'));

        // Verify no calls to cloneRepo
        verifyNever(() => mockGitCloner.cloneRepo(any(), any()));
      });

      test('Throws exception for HTTP organization URL with invalid status',
          () async {
        // Test organization branch when repoFetcher returns error response
        const targetArg = 'http://github.com/myorg';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        Future<http.Response> repoFetcher(Uri uri) async {
          return http.Response('Error fetching repos', 404);
        }

        expect(
          () async => await addRepositoryHelper(
            targetArg: targetArg,
            ggLog: ggLog,
            gitCloner: mockGitCloner,
            repoFetcher: repoFetcher,
            workspacePath: workspacePath,
          ),
          throwsA(
            predicate(
              (e) => e.toString().contains(
                    'Failed to fetch repositories for organization myorg',
                  ),
            ),
          ),
        );
      });
    });

    group('SSH URL target', () {
      test('Processes SSH URL correctly', () async {
        const targetArg = 'git@github.com:user/repo.git';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        // Dummy repoFetcher not used in this branch
        Future<http.Response> repoFetcher(Uri uri) async {
          fail('repoFetcher should not be called for SSH URL branch');
        }

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          repoFetcher: repoFetcher,
          workspacePath: workspacePath,
        );

        final expectedDestination = path.join(workspacePath, 'repo');
        verify(() => mockGitCloner.cloneRepo(targetArg, expectedDestination))
            .called(1);
        expect(logs, contains('added repository repo from $targetArg'));
      });
    });

    group('Target containing "/" (non-http, non-SSH)', () {
      test('Processes target with slash correctly', () async {
        const targetArg = 'user/repo';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        Future<http.Response> repoFetcher(Uri uri) async {
          fail('repoFetcher should not be called for target with slash branch');
        }

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          repoFetcher: repoFetcher,
          workspacePath: workspacePath,
        );

        const expectedRepoUrl = 'https://github.com/user/repo.git';
        final expectedDestination = path.join(workspacePath, 'repo');
        verify(
          () => mockGitCloner.cloneRepo(expectedRepoUrl, expectedDestination),
        ).called(1);
        expect(logs, contains('added repository repo from $expectedRepoUrl'));
      });
    });

    group('Plain target', () {
      test('Processes plain target correctly', () async {
        const targetArg = 'repo';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        Future<http.Response> repoFetcher(Uri uri) async {
          fail('repoFetcher should not be called for plain target branch');
        }

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          repoFetcher: repoFetcher,
          workspacePath: workspacePath,
        );

        const expectedRepoUrl = 'https://github.com/repo/repo.git';
        final expectedDestination = path.join(workspacePath, 'repo');
        verify(
          () => mockGitCloner.cloneRepo(expectedRepoUrl, expectedDestination),
        ).called(1);
        expect(logs, contains('added repository repo from $expectedRepoUrl'));
      });
    });

    group('Invalid HTTP URL with empty path segments', () {
      test('Throws exception for invalid organization URL', () async {
        // When targetArg URL has no path segments
        const targetArg = 'http://github.com';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        Future<http.Response> repoFetcher(Uri uri) async {
          fail('repoFetcher should not be called when URL is invalid');
        }

        expect(
          () async => await addRepositoryHelper(
            targetArg: targetArg,
            ggLog: ggLog,
            gitCloner: mockGitCloner,
            repoFetcher: repoFetcher,
            workspacePath: workspacePath,
          ),
          throwsA(
            predicate(
              (e) => e.toString().contains(
                    'Invalid organization URL provided: http://github.com',
                  ),
            ),
          ),
        );
      });
    });
  });

  group('extractRepoName', () {
    test('returns repo name for SSH URL', () {
      final repoName = extractRepoName('git@github.com:owner/repo.git');
      expect(repoName, equals('repo'));
    });

    test('returns repo name for HTTP URL with .git', () {
      final repoName = extractRepoName('https://github.com/owner/repo.git');
      expect(repoName, equals('repo'));
    });

    test('returns repo name for HTTP URL without .git', () {
      final repoName = extractRepoName('https://github.com/owner/repo');
      expect(repoName, equals('repo'));
    });

    test('returns original string for invalid URL', () {
      final repoName = extractRepoName('not a url');
      expect(repoName, equals('not a url'));
    });
  });
}
