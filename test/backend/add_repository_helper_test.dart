// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'package:kidney_core/src/backend/add_repository_helper.dart';
import 'package:kidney_core/src/backend/git_handler.dart';

import '../rm_console_colors_helper.dart';

// Mock for GitCloner using mocktail
class MockGitCloner extends Mock implements GitHandler {}

// Dummy implementation for repoFetcher in tests
typedef RepoFetcher = Future<http.Response> Function(Uri uri);

void main() {
  // Common variables used in tests
  late List<String> logs;
  late Directory tempWorkspace;
  late String workspacePath;

  // Setup a simple ggLog function that appends messages to logs list
  void ggLog(String message) {
    logs.add(rmConsoleColors(message));
  }

  setUp(() {
    logs = [];
    // Use a temporary directory for the workspace
    tempWorkspace = Directory.systemTemp.createTempSync('dummy_workspace_test');
    workspacePath = tempWorkspace.path;
  });

  tearDown(() {
    if (tempWorkspace.existsSync()) {
      tempWorkspace.deleteSync(recursive: true);
    }
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
          force: false,
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
        expect(logs, contains('Added repository repo from $expectedRepoUrl'));
      });

      test('Processes repository URL that already ends with .git', () async {
        const targetArg = 'https://github.com/user/repo.git';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        Future<http.Response> repoFetcher(Uri uri) async {
          fail('repoFetcher should not be called for repository URL branch');
        }

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          repoFetcher: repoFetcher,
          workspacePath: workspacePath,
          force: false,
        );

        final expectedDestination = path.join(workspacePath, 'repo');
        verify(() => mockGitCloner.cloneRepo(targetArg, expectedDestination))
            .called(1);
        expect(logs, contains('Added repository repo from $targetArg'));
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
          force: false,
        );

        // Verify cloneRepo called for each repository
        for (final repo in repoList) {
          final repoName = repo['name']!;
          final cloneUrl = repo['clone_url']!;
          final destination = path.join(workspacePath, repoName);
          verify(() => mockGitCloner.cloneRepo(cloneUrl, destination))
              .called(1);
          expect(logs, contains('Added repository $repoName from $cloneUrl'));
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
          force: false,
        );

        // Expect ggLog to log that no repositories were found
        expect(logs, contains('No repositories found for organization myorg'));

        // Verify no calls to cloneRepo
        verifyNever(() => mockGitCloner.cloneRepo(any(), any()));
      });

      test('Throws exception for HTTP organization URL with invalid status',
          () async {
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
            force: false,
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

        Future<http.Response> repoFetcher(Uri uri) async {
          fail('repoFetcher should not be called for SSH URL branch');
        }

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          repoFetcher: repoFetcher,
          workspacePath: workspacePath,
          force: false,
        );

        final expectedDestination = path.join(workspacePath, 'repo');
        verify(() => mockGitCloner.cloneRepo(targetArg, expectedDestination))
            .called(1);
        expect(logs, contains('Added repository repo from $targetArg'));
      });
    });

    test('Processes Azure SSH URL correctly', () async {
      const targetArg =
          'git@ssh.dev.azure.com:v3/goeranhegenberg/project123/project123.git';
      final mockGitCloner = MockGitCloner();
      when(() => mockGitCloner.cloneRepo(any(), any()))
          .thenAnswer((_) async {});

      Future<http.Response> repoFetcher(Uri uri) async {
        fail('repoFetcher should not be called for SSH URL branch');
      }

      await addRepositoryHelper(
        targetArg: targetArg,
        ggLog: ggLog,
        gitCloner: mockGitCloner,
        repoFetcher: repoFetcher,
        workspacePath: workspacePath,
        force: false,
      );

      final expectedDestination = path.join(workspacePath, 'project123');
      verify(() => mockGitCloner.cloneRepo(targetArg, expectedDestination))
          .called(1);
      expect(logs, contains('Added repository project123 from $targetArg'));
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
          force: false,
        );

        const expectedRepoUrl = 'https://github.com/user/repo.git';
        final expectedDestination = path.join(workspacePath, 'repo');
        verify(
          () => mockGitCloner.cloneRepo(
            expectedRepoUrl,
            expectedDestination,
          ),
        ).called(1);
        expect(logs, contains('Added repository repo from $expectedRepoUrl'));
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
          force: false,
        );

        const expectedRepoUrl = 'https://github.com/repo/repo.git';
        final expectedDestination = path.join(workspacePath, 'repo');
        verify(
          () => mockGitCloner.cloneRepo(
            expectedRepoUrl,
            expectedDestination,
          ),
        ).called(1);
        expect(logs, contains('Added repository repo from $expectedRepoUrl'));
      });
    });

    group('Invalid HTTP URL with empty path segments', () {
      test('Throws exception for invalid organization URL', () async {
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
            force: false,
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

      test(
          'Throws exception for invalid organization URL '
          'with whitespace in path', () async {
        const targetArg = 'http://github.com/ ';
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
            force: false,
          ),
          throwsA(
            predicate(
              (e) => e.toString().contains(
                    'Invalid organization URL provided: http://github.com/',
                  ),
            ),
          ),
        );
      });
    });

    group('Force flag behavior', () {
      test('force clone: deletes existing directory before cloning', () async {
        const repoName = 'repo';
        final destination = path.join(workspacePath, repoName);
        Directory(destination).createSync(recursive: true);
        File(path.join(destination, 'dummy.txt')).writeAsStringSync('data');

        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        await addRepositoryHelper(
          targetArg: 'repo',
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          repoFetcher: (uri) async => http.Response('{}', 200),
          workspacePath: workspacePath,
          force: true,
        );

        verify(
          () => mockGitCloner.cloneRepo(
            'https://github.com/repo/repo.git',
            any(),
          ),
        ).called(1);
      });

      test('non-force: logs already added if destination exists', () async {
        const repoName = 'repo';
        final destination = path.join(workspacePath, repoName);
        Directory(destination).createSync(recursive: true);
        File(path.join(destination, 'dummy.txt')).writeAsStringSync('data');

        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        await addRepositoryHelper(
          targetArg: 'repo',
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          repoFetcher: (uri) async => http.Response('{}', 200),
          workspacePath: workspacePath,
          force: false,
        );

        verifyNever(() => mockGitCloner.cloneRepo(any(), any()));
        expect(logs, contains('repo already added.'));
      });
    });

    test('uses fallback organization when primary clone fails', () async {
      // Arrange: write .organizations file in workspace
      final orgFile = File(path.join(workspacePath, '.organizations'));
      const fallbackOrgName = 'fallbackOrg';
      const fallbackOrgUrl = 'https://github.com/fallbackOrg';
      orgFile.writeAsStringSync(jsonEncode({fallbackOrgName: fallbackOrgUrl}));

      // Given a plain repo name (targetArg), the initial github URL...
      const repoName = 'test';
      const primaryUrl = 'https://github.com/$repoName/$repoName.git';
      const fallbackUrl = '$fallbackOrgUrl/$repoName.git';
      final destination = path.join(workspacePath, repoName);

      final mockGitCloner = MockGitCloner();
      // First attempt fails (default github)
      when(() => mockGitCloner.cloneRepo(primaryUrl, any()))
          .thenThrow(Exception('Primary clone failure'));
      // Second attempt (fallback) succeeds
      when(() => mockGitCloner.cloneRepo(fallbackUrl, any()))
          .thenAnswer((_) async {});

      var callbackExecuted = false;
      Future<void> onRepoAdded(String name) async {
        expect(name, equals(repoName));
        callbackExecuted = true;
      }

      // Act
      await addRepositoryHelper(
        targetArg: repoName,
        ggLog: ggLog,
        gitCloner: mockGitCloner,
        repoFetcher: (uri) async => http.Response('{}', 200),
        workspacePath: workspacePath,
        force: false,
        onRepoAdded: onRepoAdded,
      );

      // Assert: fallbackUrl was used
      verify(() => mockGitCloner.cloneRepo(primaryUrl, destination)).called(1);
      verify(() => mockGitCloner.cloneRepo(fallbackUrl, destination)).called(1);
      // The repo was reported as added from the fallback URL
      expect(
        logs,
        contains(
          'Added repository $repoName from $fallbackUrl',
        ),
      );
      expect(
        callbackExecuted,
        isTrue,
        reason: 'onRepoAdded should be executed when fallback url is used.',
      );
    });

    test('logs error when primary and all fallback organization clones fail',
        () async {
      // Arrange: add at least one org for fallback, all fail
      final orgFile = File(path.join(workspacePath, '.organizations'));
      const fallbackOrgName = 'fallbackOrg';
      const fallbackOrgUrl = 'https://github.com/fallbackOrg';
      orgFile.writeAsStringSync(jsonEncode({fallbackOrgName: fallbackOrgUrl}));

      const repoName = 'fallbackRepo';
      const primaryUrl = 'https://github.com/$repoName/$repoName.git';
      const fallbackUrl = '$fallbackOrgUrl/$repoName.git';

      final mockGitCloner = MockGitCloner();
      // Both primary and fallback throw an error
      when(() => mockGitCloner.cloneRepo(primaryUrl, any()))
          .thenThrow(Exception('Primary clone fail'));
      when(() => mockGitCloner.cloneRepo(fallbackUrl, any()))
          .thenThrow(Exception('Fallback fail'));

      await addRepositoryHelper(
        targetArg: repoName,
        ggLog: ggLog,
        gitCloner: mockGitCloner,
        repoFetcher: (uri) async => http.Response('{}', 200),
        workspacePath: workspacePath,
        force: false,
      );

      expect(
        logs,
        contains('Failed to clone repository $repoName '
            'from any known organizations.'),
      );
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

    test('returns repo name for Azure DevOps SSH URL with .git', () {
      final repoName = extractRepoName(
        'git@ssh.dev.azure.com:v3/goeranhegenberg/project123/project123.git',
      );
      expect(repoName, equals('project123'));
    });

    test('returns repo name for Azure DevOps SSH URL without .git', () {
      final repoName = extractRepoName(
        'git@ssh.dev.azure.com:v3/goeranhegenberg/project123/project123',
      );
      expect(repoName, equals('project123'));
    });
  });

  group('getPubspecFromWorkspace', () {
    test('returns null and logs error when pubspec.yaml parsing fails', () {
      final tempDir = Directory.systemTemp.createTempSync('pubspec_fail_test');
      final wsPath = tempDir.path;
      final projectDir = Directory(path.join(wsPath, 'bad_project'))
        ..createSync(recursive: true);
      final pubspecFile = File(path.join(projectDir.path, 'pubspec.yaml'));
      pubspecFile.writeAsStringSync('invalid content');

      final List<String> localLogs = [];
      final result = getPubspecFromWorkspace(
        targetArg: 'bad_project',
        workspacePath: wsPath,
        ggLog: (msg) => localLogs.add(msg),
      );
      expect(result, isNull);
      expect(
        localLogs.any((msg) => msg.contains('Error parsing pubspec.yaml:')),
        isTrue,
      );
      tempDir.deleteSync(recursive: true);
    });

    test('returns null and logs message when pubspec.yaml not found', () {
      final tempDir =
          Directory.systemTemp.createTempSync('nosuch_project_test');
      final wsPath = tempDir.path;
      final List<String> localLogs = [];
      final result = getPubspecFromWorkspace(
        targetArg: 'nosuch_project',
        workspacePath: wsPath,
        ggLog: (msg) => localLogs.add(msg),
      );
      expect(result, isNull);
      expect(
        localLogs.first,
        contains(
          'pubspec.yaml not found in project nosuch_project in workspace',
        ),
      );
      tempDir.deleteSync(recursive: true);
    });
  });

  test('calls onRepoAdded callback when repo already exists and is non-empty',
      () async {
    // Arrange
    const repoName = 'existing_repo';
    final destination = path.join(workspacePath, repoName);
    final repoDir = Directory(destination)..createSync(recursive: true);
    File(path.join(repoDir.path, 'dummy.txt')).writeAsStringSync('data');

    final mockGitCloner = MockGitCloner();
    // cloneRepo should NOT be called because repo already present
    when(() => mockGitCloner.cloneRepo(any(), any())).thenAnswer((_) async {});

    var callbackExecuted = false;
    Future<void> onRepoAdded(String name) async {
      expect(name, equals(repoName));
      callbackExecuted = true;
    }

    // Act
    await addRepositoryHelper(
      targetArg: repoName,
      ggLog: ggLog,
      gitCloner: mockGitCloner,
      repoFetcher: (uri) async => http.Response('{}', 200),
      workspacePath: workspacePath,
      force: false,
      onRepoAdded: onRepoAdded,
    );

    // Assert
    expect(
      callbackExecuted,
      isTrue,
      reason: 'onRepoAdded should be executed when repo already exists.',
    );
    expect(logs, contains('$repoName already added.'));
    verifyNever(() => mockGitCloner.cloneRepo(any(), any()));
  });

  test('calls onRepoAdded even when repo is freshly cloned', () async {
    // Arrange
    const repoName = 'fresh_repo';
    final mockGitCloner = MockGitCloner();
    when(() => mockGitCloner.cloneRepo(any(), any())).thenAnswer((_) async {});
    bool callbackExecuted = false;
    Future<void> callback(String name) async {
      expect(name, repoName);
      callbackExecuted = true;
    }

    Future<http.Response> repoFetcher(Uri uri) async =>
        http.Response('{}', 200);

    // Act
    await addRepositoryHelper(
      targetArg: repoName,
      ggLog: ggLog,
      gitCloner: mockGitCloner,
      repoFetcher: repoFetcher,
      workspacePath: workspacePath,
      force: true,
      onRepoAdded: callback,
    );

    // Assert
    expect(callbackExecuted, isTrue);
    verify(
      () => mockGitCloner.cloneRepo(
        'https://github.com/fresh_repo/fresh_repo.git',
        any(),
      ),
    ).called(1);
    expect(
      logs,
      contains('Added repository fresh_repo from '
          'https://github.com/fresh_repo/fresh_repo.git'),
    );
  });
}
