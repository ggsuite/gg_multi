// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:test/test.dart';
import 'package:kidney_core/src/backend/url_parser.dart';
import 'package:kidney_core/src/backend/git_platform.dart';

void main() {
  group('UrlParser', () {
    const parser = UrlParser();

    test('parses Azure SSH URL correctly', () {
      const url = 'git@ssh.dev.azure.com:v3/myorg/myproj/myrepo.git';
      final result = parser.parse(url);
      expect(result.platformType, 'azure');
      expect(result.org, 'myorg');
      expect(result.project, 'myproj');
      expect(result.repo, 'myrepo');
    });

    test('parses Azure SSH URL with insufficient segments as unknown', () {
      const url = 'git@ssh.dev.azure.com:v3/myorg/';
      final result = parser.parse(url);
      expect(result.platformType, 'unknown');
      expect(result.org, null);
      expect(result.project, null);
      expect(result.repo, null);
    });

    test('parses GitHub SSH URL correctly', () {
      const url = 'git@github.com:myorg/myrepo.git';
      final result = parser.parse(url);
      expect(result.platformType, 'github');
      expect(result.org, 'myorg');
      expect(result.repo, 'myrepo');
      expect(result.project, isNull);
    });

    test('parses HTTP URL correctly for GitHub', () {
      const url = 'https://github.com/myorg/myrepo.git';
      final result = parser.parse(url);
      expect(result.platformType, 'github');
      expect(result.org, 'myorg');
      expect(result.repo, 'myrepo');
    });

    test('parses HTTP URL correctly for Azure', () {
      const url = 'https://ssh.dev.azure.com/v3/myorg/myproj/myrepo.git';
      final result = parser.parse(url);
      expect(result.platformType, 'azure');
      expect(result.org, 'myorg');
      expect(result.project, 'myproj');
      expect(result.repo, 'myrepo');
    });

    test('parses HTTP Azure URL with insufficient segments as unknown', () {
      const url = 'https://ssh.dev.azure.com/v3/myorg/';
      final result = parser.parse(url);
      expect(result.platformType, 'azure');
      expect(result.org, 'myorg');
      expect(result.project, null);
      expect(result.repo, null);
    });

    test('parses username/repo format as GitHub', () {
      const target = 'myorg/myrepo';
      final result = parser.parse(target);
      expect(result.platformType, 'github');
      expect(result.org, 'myorg');
      expect(result.repo, 'myrepo');
    });

    test('parses plain repo name as unknown', () {
      const target = 'myrepo';
      final result = parser.parse(target);
      expect(result.platformType, 'unknown');
      expect(result.org, null);
      expect(result.repo, 'myrepo');
    });

    test('cleans trailing / and #', () {
      const url = 'https://github.com/myorg/myrepo.git/#/';
      final result = parser.parse(url);
      expect(result.repo, 'myrepo');
    });

    test('returns unknown for invalid format', () {
      const invalid = 'invalid_url';
      final result = parser.parse(invalid);
      expect(result.platformType, 'unknown');
      expect(result.org, null);
      expect(result.repo, 'invalid_url');
    });

    test('getPlatform returns correct instance', () {
      expect(parser.getPlatform('github'), isA<GitHubPlatform>());
      expect(parser.getPlatform('azure'), isA<AzureDevOpsPlatform>());
      expect(() => parser.getPlatform('unknown'), throwsArgumentError);
    });
  });
}
