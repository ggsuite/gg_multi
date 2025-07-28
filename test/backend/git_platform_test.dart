// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:kidney_core/src/backend/git_platform.dart';

class MockProcessRunner extends Mock {
  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  });
}

void main() {
  group('GitHubPlatform', () {
    test('buildRepoUrl returns correct URL', () {
      final platform = GitHubPlatform();
      final url = platform.buildRepoUrl('myorg', 'myrepo');
      expect(url, equals('https://github.com/myorg/myrepo.git'));
    });

    test('fetchOrgRepos fetches and returns repo list', () async {
      final platform = GitHubPlatform();
      final mockClient = MockClient((request) async {
        if (request.url.toString() ==
            'https://api.github.com/orgs/testorg/repos') {
          return http.Response(
            jsonEncode([
              {'name': 'repo1', 'clone_url': 'url1'},
              {'name': 'repo2', 'clone_url': 'url2'},
            ]),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final repos = await platform.fetchOrgRepos('testorg', client: mockClient);
      expect(repos.length, 2);
      expect(repos[0]['name'], 'repo1');
    });

    test('fetchOrgRepos creates default client if none provided', () async {
      final platform = GitHubPlatform();
      await expectLater(
        platform.fetchOrgRepos(
          'nonexistentorg123456789abcdef',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'toString',
            contains('Failed to fetch repositories'),
          ),
        ),
      );
    });

    test('fetchOrgRepos throws on non-200 response', () async {
      final platform = GitHubPlatform();
      final mockClient =
          MockClient((request) async => http.Response('Error', 403));

      expect(
        () => platform.fetchOrgRepos('badorg', client: mockClient),
        throwsException,
      );
    });

    test('extractOrgFromUrl returns Organization for GitHub URL', () {
      final platform = GitHubPlatform();
      final org =
          platform.extractOrgFromUrl('https://github.com/myorg/myrepo.git');
      expect(org?.name, 'myorg');
      expect(org?.url, 'https://github.com/myorg/');
    });

    test('extractOrgFromUrl returns null for non-GitHub URL', () {
      final platform = GitHubPlatform();
      final org =
          platform.extractOrgFromUrl('https://dev.azure.com/myorg/myrepo.git');
      expect(org, isNull);
    });

    test('buildBaseUrl returns correct base URL', () {
      final platform = GitHubPlatform();
      final base = platform.buildBaseUrl('myorg');
      expect(base, 'https://github.com/myorg/');
    });

    test('fetchOrgRepos ignores project parameter', () async {
      final platform = GitHubPlatform();
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode(
            [
              {'name': 'repo', 'clone_url': 'url'},
            ],
          ),
          200,
        );
      });
      final repos = await platform.fetchOrgRepos(
        'testorg',
        project: 'ignored',
        client: mockClient,
      );
      expect(repos.length, 1);
    });
  });

  group('AzureDevOpsPlatform', () {
    test('buildRepoUrl returns correct URL with project', () {
      final platform = AzureDevOpsPlatform();
      final url = platform.buildRepoUrl('myorg', 'myrepo', 'myproj');
      expect(url, 'https://ssh.dev.azure.com:v3/myorg/myproj/myrepo.git');
    });

    test('buildRepoUrl throws without project', () {
      final platform = AzureDevOpsPlatform();
      expect(
        () => platform.buildRepoUrl('myorg', 'myrepo'),
        throwsArgumentError,
      );
    });

    test('fetchOrgRepos throws without project', () async {
      final platform = AzureDevOpsPlatform();
      await expectLater(
        platform.fetchOrgRepos('myorg'),
        throwsArgumentError,
      );
    });

    test('fetchOrgRepos executes CLI and parses JSON', () async {
      final mockRunner = MockProcessRunner();
      when(
        () => mockRunner(
          'az',
          any(),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(
          1,
          0,
          jsonEncode([
            {'name': 'repo1', 'sshUrl': 'ssh1'},
            {'name': 'repo2', 'sshUrl': 'ssh2'},
          ]),
          '',
        ),
      );
      final platform = AzureDevOpsPlatform(processRunner: mockRunner.call);
      final repos = await platform.fetchOrgRepos(
        'myorg',
        project: 'myproj',
      );
      expect(repos.length, 2);
      expect(repos[0]['name'], 'repo1');
      expect(repos[0]['clone_url'], 'ssh1');
      verify(
        () => mockRunner(
          'az',
          [
            'repos',
            'list',
            '--organization',
            'https://dev.azure.com/myorg',
            '--project',
            'myproj',
          ],
        ),
      ).called(1);
    });

    test('fetchOrgRepos throws on non-zero exit code', () async {
      final mockRunner = MockProcessRunner();
      when(
        () => mockRunner(
          'az',
          any(),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(2, 1, '', 'CLI error'),
      );
      final platform = AzureDevOpsPlatform(processRunner: mockRunner.call);
      await expectLater(
        platform.fetchOrgRepos('myorg', project: 'myproj'),
        throwsA(isA<Exception>()),
      );
    });

    test('fetchOrgRepos throws on invalid JSON', () async {
      final mockRunner = MockProcessRunner();
      when(
        () => mockRunner(
          'az',
          any(),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(3, 0, 'invalid json', ''),
      );
      final platform = AzureDevOpsPlatform(processRunner: mockRunner.call);
      await expectLater(
        platform.fetchOrgRepos('myorg', project: 'myproj'),
        throwsA(isA<Exception>()),
      );
    });

    test('fetchOrgRepos throws when az is not installed', () async {
      final mockRunner = MockProcessRunner();
      // First call: az --version fails
      when(
        () => mockRunner('az', ['--version']),
      ).thenAnswer(
        (_) async => ProcessResult(4, 1, '', 'az not found'),
      );
      final platform = AzureDevOpsPlatform(processRunner: mockRunner.call);
      await expectLater(
        platform.fetchOrgRepos('myorg', project: 'myproj'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Bitte installiere die Azure CLI'),
          ),
        ),
      );
      // Main az repos list should not be called
      verifyNever(
        () => mockRunner('az', any(that: contains('repos'))),
      );
    });

    test('extractOrgFromUrl returns Organization for Azure URL', () {
      final platform = AzureDevOpsPlatform();
      final org = platform.extractOrgFromUrl(
        'git@ssh.dev.azure.com:v3/myorg/myproj/myrepo.git',
      );
      expect(org?.name, 'myorg');
      expect(org?.projectName, 'myproj');
      expect(org?.url, 'https://ssh.dev.azure.com:v3/myorg/myproj/');
    });

    test('extractOrgFromUrl returns null for non-Azure URL', () {
      final platform = AzureDevOpsPlatform();
      final org =
          platform.extractOrgFromUrl('https://github.com/myorg/myrepo.git');
      expect(org, isNull);
    });

    test('buildBaseUrl returns correct base with project', () {
      final platform = AzureDevOpsPlatform();
      final base = platform.buildBaseUrl('myorg', 'myproj');
      expect(base, 'https://ssh.dev.azure.com:v3/myorg/myproj/');
    });

    test('buildBaseUrl returns correct base without project', () {
      final platform = AzureDevOpsPlatform();
      final base = platform.buildBaseUrl('myorg');
      expect(base, 'https://ssh.dev.azure.com:v3/myorg/');
    });

    test('fetchOrgRepos throws with correct message on non-zero exit code',
        () async {
      final mockRunner = MockProcessRunner();
      when(
        () => mockRunner('az', any()),
      ).thenAnswer(
        (_) async => ProcessResult(3, 1, '', 'CLI error message'),
      );
      when(
        () => mockRunner('az', ['--version']),
      ).thenAnswer(
        (_) async => ProcessResult(2, 0, '', 'azure-cli 2.75.0'),
      );
      final platform = AzureDevOpsPlatform(processRunner: mockRunner.call);
      await expectLater(
        platform.fetchOrgRepos('myorg', project: 'myproj'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            'Exception: Failed to fetch repositories for organization myorg, '
                'project myproj: CLI error message',
          ),
        ),
      );
    });
  });
}
