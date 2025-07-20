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

    group('parseAzure', () {
      test('parses full Azure SSH URL', () {
        const url = 'git@ssh.dev.azure.com:v3/myorg/myproj/myrepo.git';
        final result = parser.parseAzure(url);
        expect(result.platformType, 'azure');
        expect(result.org, 'myorg');
        expect(result.project, 'myproj');
        expect(result.repo, 'myrepo');
      });

      test('parses Azure SSH URL without repo', () {
        const url = 'git@ssh.dev.azure.com:v3/myorg/myproj';
        final result = parser.parseAzure(url);
        expect(result.platformType, 'azure');
        expect(result.org, 'myorg');
        expect(result.project, 'myproj');
        expect(result.repo, null);
      });

      test('returns unknown for insufficient segments', () {
        const url = 'git@ssh.dev.azure.com:v3/myorg';
        final result = parser.parseAzure(url);
        expect(result.platformType, 'unknown');
        expect(result.org, null);
        expect(result.project, null);
        expect(result.repo, null);
      });

      test('handles Azure SSH URL without .git', () {
        const url = 'git@ssh.dev.azure.com:v3/myorg/myproj/myrepo';
        final result = parser.parseAzure(url);
        expect(result.repo, 'myrepo');
      });
    });

    group('parseGitHubSsh', () {
      test('parses valid GitHub SSH URL', () {
        const url = 'git@github.com:myorg/myrepo.git';
        final result = parser.parseGitHubSsh(url);
        expect(result.platformType, 'github');
        expect(result.org, 'myorg');
        expect(result.repo, 'myrepo');
      });

      test('parses GitHub SSH URL without .git', () {
        const url = 'git@github.com:myorg/myrepo';
        final result = parser.parseGitHubSsh(url);
        expect(result.repo, 'myrepo');
      });

      test('returns null for invalid SSH format', () {
        const url = 'git@invalid';
        final result = parser.parseGitHubSsh(url);
        expect(result.platformType, 'unknown');
        expect(result.org, null);
        expect(result.repo, null);
      });
    });

    group('parseHttp', () {
      test('parses valid GitHub HTTP URL', () {
        const url = 'https://github.com/myorg/myrepo.git';
        final result = parser.parseHttp(url);
        expect(result.platformType, 'github');
        expect(result.org, 'myorg');
        expect(result.repo, 'myrepo');
      });

      test('parses Azure HTTP URL with v3', () {
        const url = 'https://ssh.dev.azure.com/v3/myorg/myproj/myrepo.git';
        final result = parser.parseHttp(url);
        expect(result.platformType, 'azure');
        expect(result.org, 'myorg');
        expect(result.project, 'myproj');
        expect(result.repo, 'myrepo');
      });

      test('parses Azure HTTP URL without repo', () {
        const url = 'https://ssh.dev.azure.com/v3/myorg/myproj';
        final result = parser.parseHttp(url);
        expect(result.platformType, 'azure');
        expect(result.org, 'myorg');
        expect(result.project, 'myproj');
        expect(result.repo, null);
      });

      test('parses unknown platform for non-GitHub/non-Azure host', () {
        const url = 'https://example.com/myorg/myrepo.git';
        final result = parser.parseHttp(url);
        expect(result.platformType, 'unknown');
        expect(result.org, 'myorg');
        expect(result.repo, 'myrepo');
      });

      test('returns platformType only for empty segments', () {
        const url = 'https://github.com/';
        final result = parser.parseHttp(url);
        expect(result.platformType, 'github');
        expect(result.org, null);
        expect(result.repo, null);
      });

      test('handles invalid URI by returning unknown', () {
        const url = '::invalid_uri::';
        final result = parser.parseHttp(url);
        expect(result.platformType, 'unknown');
      });

      test('handles Azure without v3 as unknown', () {
        const url = 'https://ssh.dev.azure.com/myorg/myproj/myrepo.git';
        final result = parser.parseHttp(url);
        expect(result.platformType, 'azure');
        expect(result.org, 'myorg');
        expect(result.project, 'myproj');
        expect(result.repo, 'myrepo');
      });
    });

    group('parseUsernameRepo', () {
      test('parses valid username/repo', () {
        const target = 'myorg/myrepo';
        final result = parser.parseUsernameRepo(target);
        expect(result.platformType, 'github');
        expect(result.org, 'myorg');
        expect(result.repo, 'myrepo');
      });

      test('returns unknown for invalid parts length', () {
        const target = 'myorg/myrepo/extra';
        final result = parser.parseUsernameRepo(target);
        expect(result.platformType, 'unknown');
        expect(result.org, null);
        expect(result.repo, null);
      });

      test('returns unknown for single part', () {
        const target = 'myrepo';
        final result = parser.parseUsernameRepo(target);
        expect(result.platformType, 'unknown');
      });
    });

    group('parsePlainRepo', () {
      test('parses valid plain repo name', () {
        const target = 'myrepo';
        final result = parser.parsePlainRepo(target);
        expect(result.platformType, 'unknown');
        expect(result.org, null);
        expect(result.repo, 'myrepo');
      });

      test('returns unknown for repo with /', () {
        const target = 'my/repo';
        final result = parser.parsePlainRepo(target);
        expect(result.platformType, 'unknown');
      });

      test('returns unknown for repo with :', () {
        const target = 'my:repo';
        final result = parser.parsePlainRepo(target);
        expect(result.platformType, 'unknown');
      });
    });
  });
}
