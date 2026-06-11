// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_multi/src/backend/repo_folder_resolver.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('repo_resolver_test_');
  });

  tearDown(() {
    if (workspace.existsSync()) {
      workspace.deleteSync(recursive: true);
    }
  });

  // Creates a repo folder with optional pubspec/package.json/git remote.
  Directory makeRepo(
    String folderName, {
    String? pubspecName,
    bool flutter = false,
    String? packageJsonName,
    bool tsconfig = false,
    String? remoteUrl,
  }) {
    final dir = Directory(path.join(workspace.path, folderName))
      ..createSync(recursive: true);
    if (pubspecName != null) {
      final flutterBlock =
          flutter ? '\nflutter:\n  uses-material-design: true' : '';
      File(path.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: $pubspecName\nversion: 1.0.0$flutterBlock\n',
      );
    }
    if (packageJsonName != null) {
      File(path.join(dir.path, 'package.json'))
          .writeAsStringSync('{"name": "$packageJsonName"}');
    }
    if (tsconfig) {
      File(path.join(dir.path, 'tsconfig.json')).writeAsStringSync('{}');
    }
    if (remoteUrl != null) {
      final gitDir = Directory(path.join(dir.path, '.git'))..createSync();
      File(path.join(gitDir.path, 'config')).writeAsStringSync(
        '[remote "origin"]\n\turl = $remoteUrl\n',
      );
    }
    return dir;
  }

  group('RepoFolderResolver', () {
    group('resolve', () {
      test('matches the exact folder name first', () {
        final dir = makeRepo('gg_foo', pubspecName: 'gg_foo');
        final result = RepoFolderResolver.resolve(
          workspacePath: workspace.path,
          repoName: 'gg_foo',
        );
        expect(result?.path, dir.path);
      });

      test('matches via the pubspec package name of a prefixed folder', () {
        final dir = makeRepo('ggsuite_gg_foo', pubspecName: 'gg_foo');
        final result = RepoFolderResolver.resolve(
          workspacePath: workspace.path,
          repoName: 'gg_foo',
        );
        expect(result?.path, dir.path);
      });

      test('matches via a scoped package.json name', () {
        final dir = makeRepo(
          'tssuite-ts_foo',
          packageJsonName: '@tssuite/ts_foo',
          tsconfig: true,
        );
        final result = RepoFolderResolver.resolve(
          workspacePath: workspace.path,
          repoName: 'ts_foo',
        );
        expect(result?.path, dir.path);
      });

      test('returns null when no folder matches', () {
        makeRepo('ggsuite_other', pubspecName: 'other');
        final result = RepoFolderResolver.resolve(
          workspacePath: workspace.path,
          repoName: 'gg_foo',
        );
        expect(result, isNull);
      });

      test('returns null when the workspace does not exist', () {
        final result = RepoFolderResolver.resolve(
          workspacePath: path.join(workspace.path, 'nope'),
          repoName: 'gg_foo',
        );
        expect(result, isNull);
      });
    });

    group('resolveByRemoteUrl', () {
      test('matches a prefixed folder across url schemes', () {
        // Stored remote is https; query is the ssh form of the same repo.
        final dir = makeRepo(
          'ggsuite_gg_foo',
          pubspecName: 'gg_foo',
          remoteUrl: 'https://github.com/ggsuite/gg_foo.git',
        );
        final result = RepoFolderResolver.resolveByRemoteUrl(
          workspacePath: workspace.path,
          repoUrl: 'git@github.com:ggsuite/gg_foo.git',
        );
        expect(result?.path, dir.path);
      });

      test('returns null when the query url has no identity', () {
        makeRepo(
          'ggsuite_gg_foo',
          pubspecName: 'gg_foo',
          remoteUrl: 'https://github.com/ggsuite/gg_foo.git',
        );
        final result = RepoFolderResolver.resolveByRemoteUrl(
          workspacePath: workspace.path,
          repoUrl: 'foo',
        );
        expect(result, isNull);
      });

      test('returns null when no remote matches', () {
        makeRepo(
          'ggsuite_other',
          pubspecName: 'other',
          remoteUrl: 'https://github.com/ggsuite/other.git',
        );
        final result = RepoFolderResolver.resolveByRemoteUrl(
          workspacePath: workspace.path,
          repoUrl: 'https://github.com/ggsuite/gg_foo.git',
        );
        expect(result, isNull);
      });
    });

    group('packageName', () {
      test('reads the pubspec name', () {
        final dir = makeRepo('x', pubspecName: 'gg_foo');
        expect(RepoFolderResolver.packageName(dir), 'gg_foo');
      });

      test('returns null when pubspec has no name', () {
        final dir = Directory(path.join(workspace.path, 'x'))..createSync();
        File(path.join(dir.path, 'pubspec.yaml'))
            .writeAsStringSync('version: 1.0.0\n');
        expect(RepoFolderResolver.packageName(dir), isNull);
      });

      test('returns null when pubspec cannot be decoded', () {
        final dir = Directory(path.join(workspace.path, 'x'))..createSync();
        // Invalid UTF-8 bytes make readAsStringSync throw.
        File(path.join(dir.path, 'pubspec.yaml'))
            .writeAsBytesSync(<int>[0xC3, 0x28]);
        expect(RepoFolderResolver.packageName(dir), isNull);
      });

      test('reads an unscoped package.json name', () {
        final dir = makeRepo('x', packageJsonName: 'ts_foo');
        expect(RepoFolderResolver.packageName(dir), 'ts_foo');
      });

      test('strips the npm scope from a package.json name', () {
        final dir = makeRepo('x', packageJsonName: '@tssuite/ts_foo');
        expect(RepoFolderResolver.packageName(dir), 'ts_foo');
      });

      test('returns null when package.json has no name', () {
        final dir = Directory(path.join(workspace.path, 'x'))..createSync();
        File(path.join(dir.path, 'package.json')).writeAsStringSync('{}');
        expect(RepoFolderResolver.packageName(dir), isNull);
      });

      test('returns null when package.json is invalid', () {
        final dir = Directory(path.join(workspace.path, 'x'))..createSync();
        File(path.join(dir.path, 'package.json'))
            .writeAsStringSync('{not json');
        expect(RepoFolderResolver.packageName(dir), isNull);
      });

      test('returns null when no manifest is present', () {
        final dir = Directory(path.join(workspace.path, 'x'))..createSync();
        expect(RepoFolderResolver.packageName(dir), isNull);
      });
    });

    group('remoteUrl', () {
      test('returns null when there is no git config', () {
        final dir = Directory(path.join(workspace.path, 'x'))..createSync();
        expect(RepoFolderResolver.remoteUrl(dir), isNull);
      });

      test('returns null when the config has no url line', () {
        final dir = Directory(path.join(workspace.path, 'x'))..createSync();
        final gitDir = Directory(path.join(dir.path, '.git'))..createSync();
        File(path.join(gitDir.path, 'config')).writeAsStringSync('[core]\n');
        expect(RepoFolderResolver.remoteUrl(dir), isNull);
      });

      test('keeps an url value that itself contains "="', () {
        final dir = makeRepo(
          'x',
          remoteUrl: 'https://host/r.git?a=b',
        );
        expect(RepoFolderResolver.remoteUrl(dir), 'https://host/r.git?a=b');
      });
    });

    group('urlIdentity', () {
      test('is scheme independent and lower-cased', () {
        final ssh = RepoFolderResolver.urlIdentity(
          'git@github.com:Ggsuite/Gg_Foo.git',
        );
        final https = RepoFolderResolver.urlIdentity(
          'https://github.com/ggsuite/gg_foo',
        );
        expect(ssh, https);
        expect(ssh, 'ggsuite/gg_foo');
      });

      test('returns null when the url carries no org', () {
        expect(RepoFolderResolver.urlIdentity('gg_foo'), isNull);
      });
    });

    group('orgPrefixedFolderName', () {
      test('returns the repo name when org is null', () {
        final dir = makeRepo('gg_foo', pubspecName: 'gg_foo');
        final name = RepoFolderResolver.orgPrefixedFolderName(
          repoName: 'gg_foo',
          org: null,
          repoDir: dir,
        );
        expect(name, 'gg_foo');
      });

      test('returns the repo name when org is empty', () {
        final dir = makeRepo('gg_foo', pubspecName: 'gg_foo');
        final name = RepoFolderResolver.orgPrefixedFolderName(
          repoName: 'gg_foo',
          org: '',
          repoDir: dir,
        );
        expect(name, 'gg_foo');
      });

      test('uses an underscore separator for Dart projects', () {
        final dir = makeRepo('gg_foo', pubspecName: 'gg_foo');
        final name = RepoFolderResolver.orgPrefixedFolderName(
          repoName: 'gg_foo',
          org: 'ggsuite',
          repoDir: dir,
        );
        expect(name, 'ggsuite_gg_foo');
      });

      test('uses a hyphen separator for TypeScript projects', () {
        final dir = makeRepo(
          'ts_foo',
          packageJsonName: 'ts_foo',
          tsconfig: true,
        );
        final name = RepoFolderResolver.orgPrefixedFolderName(
          repoName: 'ts_foo',
          org: 'tssuite',
          repoDir: dir,
        );
        expect(name, 'tssuite-ts_foo');
      });

      test('returns the repo name when the project type is unknown', () {
        final dir = Directory(path.join(workspace.path, 'gg_foo'))
          ..createSync();
        final name = RepoFolderResolver.orgPrefixedFolderName(
          repoName: 'gg_foo',
          org: 'ggsuite',
          repoDir: dir,
        );
        expect(name, 'gg_foo');
      });
    });
  });
}
