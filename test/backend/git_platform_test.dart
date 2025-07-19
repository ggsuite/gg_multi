// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:kidney_core/src/backend/git_platform.dart';

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

    test('fetchOrgRepos throws UnimplementedError', () {
      final platform = AzureDevOpsPlatform();
      expect(
        () => platform.fetchOrgRepos('myorg'),
        throwsUnimplementedError,
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
  });
}
