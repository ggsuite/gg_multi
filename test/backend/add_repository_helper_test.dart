// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:gg_multi/src/backend/git_platform.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:gg_multi/src/backend/add_repository_helper.dart';
import 'package:gg_multi/src/backend/git_handler.dart';
import 'package:gg_multi/src/backend/repository.dart';

import '../rm_console_colors_helper.dart';

// Create a mock for GitCloner
class MockGitCloner extends Mock implements GitHandler {}

class MockGitHubPlatform extends Mock implements GitHubPlatform {}

class MockAzurePlatform extends Mock implements AzureDevOpsPlatform {}

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

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
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
        expect(
          logs,
          anyElement(contains('repo from $expectedRepoUrl')),
        );
      });

      test('Processes repository URL that already ends with .git', () async {
        const targetArg = 'https://github.com/user/repo.git';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
          force: false,
        );

        final expectedDestination = path.join(workspacePath, 'repo');
        verify(() => mockGitCloner.cloneRepo(targetArg, expectedDestination))
            .called(1);
        expect(logs, anyElement(contains('repo from $targetArg')));
      });

      test('Processes organization URL and clones multiple repos', () async {
        // Test for the organization URL branch
        // where the URL has less than 2 path segments.
        const targetArg = 'http://github.com/myorg';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        // Build a fake repo list response with two repositories
        final repoList = <Repository>[
          const Repository(
            name: 'repo1',
            httpsUrl: 'https://github.com/myorg/repo1.git',
          ),
          const Repository(
            name: 'repo2',
            httpsUrl: 'https://github.com/myorg/repo2.git',
          ),
        ];

        final mockGitHubPlatform = MockGitHubPlatform();
        when(
          () => mockGitHubPlatform.fetchOrgRepos(
            any(),
            client: any(named: 'client'),
          ),
        ).thenAnswer((_) async => repoList);

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          gitHubPlatform: mockGitHubPlatform,
          workspacePath: workspacePath,
          force: false,
        );

        // Verify cloneRepo called for each repository
        for (final repo in repoList) {
          final repoName = repo.name;
          final cloneUrl = repo.httpsUrl;
          final destination = path.join(workspacePath, repoName);
          verify(() => mockGitCloner.cloneRepo(cloneUrl, destination))
              .called(1);
          expect(logs, anyElement(contains('$repoName from $cloneUrl')));
        }
      });

      test('Processes organization URL with empty repo list', () async {
        // Test organization branch when no repositories are found
        const targetArg = 'http://github.com/myorg';
        final mockGitCloner = MockGitCloner();
        // Since no repos found, cloneRepo should not be called
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        final mockGitHubPlatform = MockGitHubPlatform();
        when(
          () => mockGitHubPlatform.fetchOrgRepos(
            any(),
            client: any(named: 'client'),
          ),
        ).thenAnswer((_) async => <Repository>[]);

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          gitHubPlatform: mockGitHubPlatform,
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

        expect(
          () async => await addRepositoryHelper(
            targetArg: targetArg,
            ggLog: ggLog,
            gitCloner: mockGitCloner,
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

      test('Processes Azure organization URL with project', () async {
        const targetArg = 'https://ssh.dev.azure.com/v3/myorg/myproj';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        final repoList = <Repository>[
          const Repository(
            name: 'repo1',
            httpsUrl: 'https://dev.azure.com/myorg/myproj/repo1.git',
          ),
          const Repository(
            name: 'repo2',
            httpsUrl: 'https://dev.azure.com/myorg/myproj/repo2.git',
          ),
        ];

        final mockAzurePlatform = MockAzurePlatform();
        when(
          () => mockAzurePlatform.fetchOrgRepos(
            'myorg',
            project: 'myproj',
            client: any(named: 'client'),
          ),
        ).thenAnswer((_) async => repoList);

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          azureDevOpsPlatform: mockAzurePlatform,
          workspacePath: workspacePath,
          force: false,
        );

        for (final repo in repoList) {
          final repoName = repo.name;
          final cloneUrl = repo.httpsUrl;
          final destination = path.join(workspacePath, repoName);
          verify(() => mockGitCloner.cloneRepo(cloneUrl, destination))
              .called(1);
          expect(logs, anyElement(contains('$repoName from $cloneUrl')));
        }
      });

      test('Processes Azure organization URL with empty repo list', () async {
        const targetArg = 'https://ssh.dev.azure.com/v3/myorg/myproj';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        final mockAzurePlatform = MockAzurePlatform();
        when(
          () => mockAzurePlatform.fetchOrgRepos(
            'myorg',
            project: 'myproj',
            client: any(named: 'client'),
          ),
        ).thenAnswer((_) async => <Repository>[]);

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          azureDevOpsPlatform: mockAzurePlatform,
          workspacePath: workspacePath,
          force: false,
        );

        expect(
          logs,
          contains(
            'No repositories found for organization myorg and project myproj',
          ),
        );
        verifyNever(() => mockGitCloner.cloneRepo(any(), any()));
      });

      test('Skips Azure organization if no project provided', () async {
        const targetArg = 'https://ssh.dev.azure.com/v3/myorg';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        final mockAzurePlatform = MockAzurePlatform();
        when(
          () => mockAzurePlatform.fetchOrgRepos(
            any(),
            project: any(named: 'project'),
            client: any(named: 'client'),
          ),
        ).thenThrow(ArgumentError('Project required'));

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          azureDevOpsPlatform: mockAzurePlatform,
          workspacePath: workspacePath,
          force: false,
        );

        // Since no project, it should treat as repo URL, not org
        verify(() => mockGitCloner.cloneRepo(any(), any())).called(1);
      });

      test('Handles az not installed for Azure organization URL', () async {
        const targetArg = 'https://ssh.dev.azure.com/v3/myorg/myproj';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        final mockAzurePlatform = MockAzurePlatform();
        when(
          () => mockAzurePlatform.fetchOrgRepos(
            'myorg',
            project: 'myproj',
            client: any(named: 'client'),
          ),
        ).thenThrow(
          Exception(
            'Bitte installiere die Azure CLI mit folgenden Befehlen: \n'
            '    winget install --exact --id Microsoft.AzureCLI \n'
            '    az extension add --name azure-devops',
          ),
        );

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          azureDevOpsPlatform: mockAzurePlatform,
          workspacePath: workspacePath,
          force: false,
        );

        expect(
          logs,
          contains(
            'Bitte installiere die Azure CLI mit folgenden Befehlen: \n'
            '    winget install --exact --id Microsoft.AzureCLI \n'
            '    az extension add --name azure-devops',
          ),
        );
        verifyNever(() => mockGitCloner.cloneRepo(any(), any()));
      });

      test('Rethrows non-az-install exceptions for Azure organization',
          () async {
        const targetArg = 'https://ssh.dev.azure.com/v3/myorg/myproj';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        final mockAzurePlatform = MockAzurePlatform();
        when(
          () => mockAzurePlatform.fetchOrgRepos(
            'myorg',
            project: 'myproj',
            client: any(named: 'client'),
          ),
        ).thenThrow(Exception('Other error'));

        await expectLater(
          () => addRepositoryHelper(
            targetArg: targetArg,
            ggLog: ggLog,
            gitCloner: mockGitCloner,
            azureDevOpsPlatform: mockAzurePlatform,
            workspacePath: workspacePath,
            force: false,
          ),
          throwsException,
        );

        expect(
          logs.any(
            (msg) => msg.contains(
              'Bitte installiere die Azure CLI',
            ),
          ),
          isFalse,
        );
      });
    });

    group('SSH URL target', () {
      test('Processes SSH URL correctly', () async {
        const targetArg = 'git@github.com:user/repo.git';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
          force: false,
        );

        final expectedDestination = path.join(workspacePath, 'repo');
        verify(() => mockGitCloner.cloneRepo(targetArg, expectedDestination))
            .called(1);
        expect(logs, anyElement(contains('repo from $targetArg')));
      });
    });

    test('Processes Azure SSH URL correctly', () async {
      const targetArg =
          'git@ssh.dev.azure.com:v3/goeranhegenberg/project123/project123.git';
      final mockGitCloner = MockGitCloner();
      when(() => mockGitCloner.cloneRepo(any(), any()))
          .thenAnswer((_) async {});

      await addRepositoryHelper(
        targetArg: targetArg,
        ggLog: ggLog,
        gitCloner: mockGitCloner,
        workspacePath: workspacePath,
        force: false,
      );

      final expectedDestination = path.join(workspacePath, 'project123');
      verify(() => mockGitCloner.cloneRepo(targetArg, expectedDestination))
          .called(1);
      expect(logs, anyElement(contains('project123 from $targetArg')));
    });

    group('Target containing "/" (non-http, non-SSH)', () {
      test('Processes target with slash correctly', () async {
        const targetArg = 'user/repo';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
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
        expect(logs, anyElement(contains('repo from $expectedRepoUrl')));
      });
    });

    group('Plain target', () {
      test('Processes plain target correctly', () async {
        const targetArg = 'repo';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        await addRepositoryHelper(
          targetArg: targetArg,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
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
        expect(logs, anyElement(contains('repo from $expectedRepoUrl')));
      });
    });

    group('Invalid HTTP URL with empty path segments', () {
      test('Throws exception for invalid organization URL', () async {
        const targetArg = 'http://github.com';
        final mockGitCloner = MockGitCloner();
        when(() => mockGitCloner.cloneRepo(any(), any()))
            .thenAnswer((_) async {});

        expect(
          () async => await addRepositoryHelper(
            targetArg: targetArg,
            ggLog: ggLog,
            gitCloner: mockGitCloner,
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

        expect(
          () async => await addRepositoryHelper(
            targetArg: targetArg,
            ggLog: ggLog,
            gitCloner: mockGitCloner,
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
          targetArg: repoName,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
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
          targetArg: repoName,
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
          force: false,
        );

        verifyNever(() => mockGitCloner.cloneRepo(any(), any()));
        expect(logs, contains('repo already added.'));
      });
    });

    test('prefers a known organization over the bare name guess', () async {
      // Arrange: write .organizations file in workspace
      final orgFile = File(path.join(workspacePath, '.organizations'));
      const fallbackOrgName = 'fallbackOrg';
      const fallbackOrgUrl = 'https://github.com/fallbackOrg';
      orgFile.writeAsStringSync(jsonEncode({fallbackOrgName: fallbackOrgUrl}));

      const repoName = 'test';
      const guessUrl = 'https://github.com/$repoName/$repoName.git';
      const orgUrl = '$fallbackOrgUrl/$repoName.git';
      final destination = path.join(workspacePath, repoName);

      final mockGitCloner = MockGitCloner();
      // The organization clone succeeds, so the name guess is never tried.
      when(() => mockGitCloner.cloneRepo(orgUrl, any()))
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
        workspacePath: workspacePath,
        force: false,
        onRepoAdded: onRepoAdded,
      );

      // Assert: the org url was used and the name guess was skipped.
      verify(() => mockGitCloner.cloneRepo(orgUrl, destination)).called(1);
      verifyNever(() => mockGitCloner.cloneRepo(guessUrl, any()));
      expect(logs, anyElement(contains('$repoName from $orgUrl')));
      expect(callbackExecuted, isTrue);
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

    // Act
    await addRepositoryHelper(
      targetArg: repoName,
      ggLog: ggLog,
      gitCloner: mockGitCloner,
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
      anyElement(
        contains(
          'fresh_repo from '
          'https://github.com/fresh_repo/fresh_repo.git',
        ),
      ),
    );
  });

  group('org prefix', () {
    // Creates a non-empty folder with optional manifest and git remote.
    Directory makeFolder(
      String name, {
      String? pubspecName,
      String? remoteUrl,
    }) {
      final dir = Directory(path.join(workspacePath, name))
        ..createSync(recursive: true);
      if (pubspecName != null) {
        File(path.join(dir.path, 'pubspec.yaml'))
            .writeAsStringSync('name: $pubspecName\nversion: 1.0.0\n');
      } else {
        File(path.join(dir.path, 'dummy.txt')).writeAsStringSync('x');
      }
      if (remoteUrl != null) {
        final gitDir = Directory(path.join(dir.path, '.git'))..createSync();
        File(path.join(gitDir.path, 'config'))
            .writeAsStringSync('[remote "origin"]\n\turl = $remoteUrl\n');
      }
      return dir;
    }

    // A clone stub that materializes a real Dart repo at the destination.
    MockGitCloner clonerThatCreatesRepo() {
      final cloner = MockGitCloner();
      when(() => cloner.cloneRepo(any(), any())).thenAnswer((inv) async {
        final url = inv.positionalArguments[0] as String;
        final dest = inv.positionalArguments[1] as String;
        final repo = path.basename(dest).replaceAll('.clone-tmp', '');
        final dir = Directory(dest)..createSync(recursive: true);
        File(path.join(dir.path, 'pubspec.yaml'))
            .writeAsStringSync('name: $repo\nversion: 1.0.0\n');
        final gitDir = Directory(path.join(dir.path, '.git'))..createSync();
        File(path.join(gitDir.path, 'config'))
            .writeAsStringSync('[remote "origin"]\n\turl = $url\n');
      });
      return cloner;
    }

    group('existingCloneFolder', () {
      test('finds a prefixed folder by remote url', () {
        final dir = makeFolder(
          'ggsuite_gg_foo',
          pubspecName: 'gg_foo',
          remoteUrl: 'https://github.com/ggsuite/gg_foo.git',
        );
        final result = existingCloneFolder(
          workspacePath: workspacePath,
          repoUrl: 'git@github.com:ggsuite/gg_foo.git',
          repoName: 'gg_foo',
        );
        expect(result?.path, dir.path);
      });

      test('returns null when no folder matches the remote', () {
        final result = existingCloneFolder(
          workspacePath: workspacePath,
          repoUrl: 'https://github.com/ggsuite/gg_foo.git',
          repoName: 'gg_foo',
        );
        expect(result, isNull);
      });

      test('returns a folder named exactly like the repo', () {
        final dir = makeFolder('gg_foo');
        final result = existingCloneFolder(
          workspacePath: workspacePath,
          repoUrl: 'git@github.com:ggsuite/gg_foo.git',
          repoName: 'gg_foo',
        );
        expect(result?.path, dir.path);
      });

      test('allows a side-by-side clone next to a prefixed sibling', () {
        // A prefixed folder of another org must not block the new clone.
        makeFolder(
          'other_gg_foo',
          pubspecName: 'gg_foo',
          remoteUrl: 'https://github.com/other/gg_foo.git',
        );
        final result = existingCloneFolder(
          workspacePath: workspacePath,
          repoUrl: 'https://github.com/ggsuite/gg_foo.git',
          repoName: 'gg_foo',
        );
        expect(result, isNull);
      });

      test('matches by name only, ignoring the org, when requested', () {
        // A plain add does not know the org; any folder with that package
        // name counts as present even if the guessed url differs.
        final dir = makeFolder('ggsuite_gg_foo', pubspecName: 'gg_foo');
        final result = existingCloneFolder(
          workspacePath: workspacePath,
          repoUrl: 'https://github.com/gg_foo/gg_foo.git',
          repoName: 'gg_foo',
          matchByNameOnly: true,
        );
        expect(result?.path, dir.path);
      });
    });

    group('stagingCloneFolder', () {
      test('returns the plain folder when it is free', () {
        final result = stagingCloneFolder(workspacePath, 'gg_foo');
        expect(path.basename(result.path), 'gg_foo');
      });

      test('returns the plain folder when it exists but is empty', () {
        Directory(path.join(workspacePath, 'gg_foo')).createSync();
        final result = stagingCloneFolder(workspacePath, 'gg_foo');
        expect(path.basename(result.path), 'gg_foo');
      });

      test('returns a temp folder when the plain folder is occupied', () {
        makeFolder('gg_foo');
        final result = stagingCloneFolder(workspacePath, 'gg_foo');
        expect(path.basename(result.path), 'gg_foo.clone-tmp');
      });

      test('clears a stale temp folder before returning it', () {
        makeFolder('gg_foo');
        final stale = Directory(path.join(workspacePath, 'gg_foo.clone-tmp'))
          ..createSync();
        File(path.join(stale.path, 'old.txt')).writeAsStringSync('old');
        final result = stagingCloneFolder(workspacePath, 'gg_foo');
        expect(path.basename(result.path), 'gg_foo.clone-tmp');
        expect(File(path.join(result.path, 'old.txt')).existsSync(), isFalse);
      });
    });

    group('finalizeClonedFolder', () {
      test('does nothing when the url carries no org', () {
        final staging = makeFolder('gg_foo', pubspecName: 'gg_foo');
        finalizeClonedFolder(
          staging: staging,
          workspacePath: workspacePath,
          repoName: 'gg_foo',
          repoUrl: 'gg_foo',
          ggLog: ggLog,
        );
        expect(staging.existsSync(), isTrue);
        expect(logs, isEmpty);
      });

      test('renames the staging folder to its org-prefixed name', () {
        final staging = makeFolder('gg_foo', pubspecName: 'gg_foo');
        finalizeClonedFolder(
          staging: staging,
          workspacePath: workspacePath,
          repoName: 'gg_foo',
          repoUrl: 'https://github.com/ggsuite/gg_foo.git',
          ggLog: ggLog,
        );
        expect(staging.existsSync(), isFalse);
        expect(
          Directory(path.join(workspacePath, 'ggsuite_gg_foo')).existsSync(),
          isTrue,
        );
      });

      test('keeps the staging folder when the target already exists', () {
        final staging = makeFolder('gg_foo', pubspecName: 'gg_foo');
        makeFolder('ggsuite_gg_foo', pubspecName: 'gg_foo');
        finalizeClonedFolder(
          staging: staging,
          workspacePath: workspacePath,
          repoName: 'gg_foo',
          repoUrl: 'https://github.com/ggsuite/gg_foo.git',
          ggLog: ggLog,
        );
        expect(staging.existsSync(), isTrue);
        expect(logs.any((l) => l.contains('Could not rename gg_foo')), isTrue);
      });

      test('warns when the rename itself fails', () {
        final staging = makeFolder('gg_foo', pubspecName: 'gg_foo');
        // A file (not a dir) at the target makes renameSync throw while
        // Directory.existsSync stays false.
        File(path.join(workspacePath, 'ggsuite_gg_foo')).writeAsStringSync('x');
        finalizeClonedFolder(
          staging: staging,
          workspacePath: workspacePath,
          repoName: 'gg_foo',
          repoUrl: 'https://github.com/ggsuite/gg_foo.git',
          ggLog: ggLog,
        );
        expect(logs.any((l) => l.contains('Could not rename gg_foo')), isTrue);
      });
    });

    group('addRepositoryHelper', () {
      test('clones a fresh repo into its org-prefixed folder', () async {
        await addRepositoryHelper(
          targetArg: 'ggsuite/gg_foo',
          ggLog: ggLog,
          gitCloner: clonerThatCreatesRepo(),
          workspacePath: workspacePath,
        );
        expect(
          Directory(path.join(workspacePath, 'ggsuite_gg_foo')).existsSync(),
          isTrue,
        );
        expect(
          Directory(path.join(workspacePath, 'gg_foo')).existsSync(),
          isFalse,
        );
      });

      test('detects an already-added repo across the prefix', () async {
        final cloner = clonerThatCreatesRepo();
        await addRepositoryHelper(
          targetArg: 'ggsuite/gg_foo',
          ggLog: ggLog,
          gitCloner: cloner,
          workspacePath: workspacePath,
        );
        logs.clear();
        await addRepositoryHelper(
          targetArg: 'ggsuite/gg_foo',
          ggLog: ggLog,
          gitCloner: cloner,
          workspacePath: workspacePath,
        );
        expect(logs, contains('gg_foo already added.'));
        verify(() => cloner.cloneRepo(any(), any())).called(1);
      });

      test('clones same-named repos of different orgs side by side', () async {
        final cloner = clonerThatCreatesRepo();
        await addRepositoryHelper(
          targetArg: 'ggsuite/gg_foo',
          ggLog: ggLog,
          gitCloner: cloner,
          workspacePath: workspacePath,
        );
        await addRepositoryHelper(
          targetArg: 'other/gg_foo',
          ggLog: ggLog,
          gitCloner: cloner,
          workspacePath: workspacePath,
        );
        expect(
          Directory(path.join(workspacePath, 'ggsuite_gg_foo')).existsSync(),
          isTrue,
        );
        expect(
          Directory(path.join(workspacePath, 'other_gg_foo')).existsSync(),
          isTrue,
        );
      });

      test('treats a prefixed repo as added for a plain name', () async {
        // The repo already exists as ggsuite_gg_foo; a plain "gg_foo" add
        // must detect it by name and not clone a duplicate.
        makeFolder(
          'ggsuite_gg_foo',
          pubspecName: 'gg_foo',
          remoteUrl: 'https://github.com/ggsuite/gg_foo.git',
        );
        final cloner = clonerThatCreatesRepo();
        await addRepositoryHelper(
          targetArg: 'gg_foo',
          ggLog: ggLog,
          gitCloner: cloner,
          workspacePath: workspacePath,
        );
        verifyNever(() => cloner.cloneRepo(any(), any()));
        expect(
          Directory(path.join(workspacePath, 'gg_foo')).existsSync(),
          isFalse,
        );
        expect(logs, contains('gg_foo already added.'));
      });

      test('re-clones a prefixed repo when force is set', () async {
        final cloner = clonerThatCreatesRepo();
        await addRepositoryHelper(
          targetArg: 'ggsuite/gg_foo',
          ggLog: ggLog,
          gitCloner: cloner,
          workspacePath: workspacePath,
        );
        await addRepositoryHelper(
          targetArg: 'ggsuite/gg_foo',
          ggLog: ggLog,
          gitCloner: cloner,
          workspacePath: workspacePath,
          force: true,
        );
        expect(
          Directory(path.join(workspacePath, 'ggsuite_gg_foo')).existsSync(),
          isTrue,
        );
        verify(() => cloner.cloneRepo(any(), any())).called(2);
      });
    });

    group('getPubspecFromWorkspace', () {
      test('resolves a prefixed repo folder', () {
        makeFolder('ggsuite_gg_foo', pubspecName: 'gg_foo');
        final pubspec = getPubspecFromWorkspace(
          targetArg: 'gg_foo',
          workspacePath: workspacePath,
          ggLog: ggLog,
        );
        expect(pubspec?.name, 'gg_foo');
      });

      test('returns null when the repo url has no extractable name', () {
        final pubspec = getPubspecFromWorkspace(
          targetArg: 'https://github.com/onlyorg',
          workspacePath: workspacePath,
          ggLog: ggLog,
        );
        expect(pubspec, isNull);
      });
    });
  });
}
