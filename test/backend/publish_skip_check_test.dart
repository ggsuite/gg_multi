// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

// ignore: lines_longer_than_80_chars
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_multi/src/backend/publish_skip_check.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:test/test.dart';

/// Mock for the injectable process runner.
class MockProcessRunner extends Mock {
  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });
}

void main() {
  late Directory tempDir;
  late PublishSkipCheck check;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('publish_skip_check_test_');
    check = PublishSkipCheck();
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // ...........................................................................
  /// Runs git with [args] in [dir], throwing on failure.
  Future<void> git(Directory dir, List<String> args) async {
    final result = await Process.run(
      'git',
      args,
      workingDirectory: dir.path,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      throw Exception('git ${args.join(' ')} failed: ${result.stderr}');
    }
  }

  // ...........................................................................
  /// Creates a git repo with a pubspec committed on [defaultBranch].
  Future<Directory> createRepo(
    String name, {
    String defaultBranch = 'main',
    String? pubspecContent,
  }) async {
    final dir = Directory(path.join(tempDir.path, name))..createSync();
    await git(dir, ['init', '--initial-branch', defaultBranch]);
    await git(dir, ['config', 'user.email', 'test@example.com']);
    await git(dir, ['config', 'user.name', 'Test']);
    File(path.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
      pubspecContent ?? 'name: $name\nversion: 1.0.0\n',
    );
    await git(dir, ['add', '.']);
    await git(dir, ['commit', '-m', 'Initial commit']);
    return dir;
  }

  // ...........................................................................
  /// Commits [content] to [file] in [dir] using [message].
  Future<void> commitFile(
    Directory dir,
    String file,
    String content,
    String message,
  ) async {
    File(path.join(dir.path, file)).writeAsStringSync(content);
    await git(dir, ['add', '.']);
    await git(dir, ['commit', '-m', message]);
  }

  // ...........................................................................
  /// Creates a node for [name] living in [dir].
  Node node(String name, Directory dir, {Set<String>? aliases}) => Node(
        name: name,
        directory: dir,
        manifest: DartPackageManifest(pubspec: Pubspec(name)),
        aliases: aliases,
      );

  // ...........................................................................
  /// Creates a plain (non-git) package folder with the given manifests.
  Directory createPlainRepo(
    String name, {
    String? pubspecContent,
    String? packageJsonContent,
  }) {
    final dir = Directory(path.join(tempDir.path, name))..createSync();
    if (pubspecContent != null) {
      File(path.join(dir.path, 'pubspec.yaml'))
          .writeAsStringSync(pubspecContent);
    }
    if (packageJsonContent != null) {
      File(path.join(dir.path, 'package.json'))
          .writeAsStringSync(packageJsonContent);
    }
    return dir;
  }

  group('PublishSkipCheck', () {
    group('get() — manual change detection', () {
      test('publishes when the directory is no git repository', () async {
        final dir = createPlainRepo('a', pubspecContent: 'name: a\n');
        final decision = await check.get(
          repo: node('a', dir),
          refVersions: {},
        );
        expect(decision.skip, isFalse);
        expect(
          decision.reason,
          contains('git history could not be inspected'),
        );
      });

      test('skips a feature branch that only carries gg commits', () async {
        final dir = await createRepo('a');
        await git(dir, ['checkout', '-b', 'feat']);
        await commitFile(
          dir,
          'pubspec_overrides.yaml',
          'dependency_overrides: {}\n',
          'gg_multi: changed references to path',
        );
        await commitFile(
          dir,
          'pubspec.yaml',
          'name: a\nversion: 1.0.0\npublish_to: none\n',
          'gg_multi: changed references to git',
        );
        await commitFile(
          dir,
          'pubspec.yaml',
          'name: a\nversion: 1.0.0\n',
          'Gg Multi: changed references to pub.dev',
        );

        final decision = await check.get(
          repo: node('a', dir),
          refVersions: {},
        );
        expect(decision.skip, isTrue);
        expect(
          decision.reason,
          contains('no dependency needs a constraint update'),
        );
      });

      test('publishes when the feature branch has a manual commit', () async {
        final dir = await createRepo('a');
        await git(dir, ['checkout', '-b', 'feat']);
        await commitFile(
          dir,
          'lib.dart',
          'void main() {}',
          'Fix login bug',
        );

        final decision = await check.get(
          repo: node('a', dir),
          refVersions: {},
        );
        expect(decision.skip, isFalse);
        expect(decision.reason, contains('Fix login bug'));
      });

      test('publishes when the working tree is dirty', () async {
        final dir = await createRepo('a');
        await git(dir, ['checkout', '-b', 'feat']);
        File(path.join(dir.path, 'new.txt')).writeAsStringSync('x');

        final decision = await check.get(
          repo: node('a', dir),
          refVersions: {},
        );
        expect(decision.skip, isFalse);
        expect(decision.reason, contains('uncommitted changes'));
      });

      test('ignores merge commits when scanning for manual work', () async {
        final dir = await createRepo('a');
        await git(dir, ['checkout', '-b', 'feat']);
        await commitFile(
          dir,
          'refs.txt',
          'refs',
          'gg_multi: changed references to git',
        );
        // Let main advance and merge it back into feat — the merge commit
        // (two parents) must not count as a manual change.
        await git(dir, ['checkout', 'main']);
        await commitFile(dir, 'main.txt', 'main', 'Change on main');
        await git(dir, ['checkout', 'feat']);
        await git(dir, ['merge', 'main', '--no-ff', '-m', 'Merge main']);

        final decision = await check.get(
          repo: node('a', dir),
          refVersions: {},
        );
        expect(decision.skip, isTrue);
      });

      test('falls back to master when there is no main branch', () async {
        final dir = await createRepo('a', defaultBranch: 'master');
        await git(dir, ['checkout', '-b', 'feat']);
        await commitFile(
          dir,
          'refs.txt',
          'refs',
          'gg_multi: changed references to git',
        );

        final decision = await check.get(
          repo: node('a', dir),
          refVersions: {},
        );
        expect(decision.skip, isTrue);
      });

      test('prefers origin/main over the local main branch', () async {
        final dir = await createRepo('a');
        // Simulate a fetched remote main without a real remote and drop the
        // local main so only origin/main can serve as the compare base.
        await git(dir, ['update-ref', 'refs/remotes/origin/main', 'main']);
        await git(dir, ['checkout', '-b', 'feat']);
        await git(dir, ['branch', '-D', 'main']);
        await commitFile(
          dir,
          'refs.txt',
          'refs',
          'gg_multi: changed references to git',
        );

        final decision = await check.get(
          repo: node('a', dir),
          refVersions: {},
        );
        expect(decision.skip, isTrue);
      });

      test('publishes when neither main nor master exists', () async {
        final dir = await createRepo('a', defaultBranch: 'trunk');

        final decision = await check.get(
          repo: node('a', dir),
          refVersions: {},
        );
        expect(decision.skip, isFalse);
        expect(
          decision.reason,
          contains('no main branch to compare against'),
        );
      });

      test('reports uncommitted changes via an injected runner', () async {
        final runner = MockProcessRunner();
        when(
          () => runner(
            'git',
            ['status', '--porcelain'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, ' M pubspec.yaml', ''));

        final injected = PublishSkipCheck(processRunner: runner.call);
        final dir = createPlainRepo('a', pubspecContent: 'name: a\n');
        final decision = await injected.get(
          repo: node('a', dir),
          refVersions: {},
        );
        expect(decision.skip, isFalse);
        expect(decision.reason, contains('uncommitted changes'));
      });
    });

    group('get() — dependency constraint detection', () {
      test('publishes when a dependency outgrew its constraint', () async {
        final depDir = createPlainRepo('a', pubspecContent: 'name: a\n');
        final dir = createPlainRepo(
          'b',
          pubspecContent: 'name: b\n'
              'dependencies:\n'
              '  a: ^1.0.0\n',
        );
        final repo = node('b', dir);
        repo.dependencies['a'] = node('a', depDir);

        final decision = await check.get(
          repo: repo,
          refVersions: {'a': '2.0.0'},
        );
        expect(decision.skip, isFalse);
        expect(
          decision.reason,
          allOf(
            contains('»a«'),
            contains('2.0.0'),
            contains('outside the published constraint'),
          ),
        );
      });

      test('treats a 0.x minor bump as breaking', () async {
        final depDir = createPlainRepo('a', pubspecContent: 'name: a\n');
        final dir = createPlainRepo(
          'b',
          pubspecContent: 'name: b\n'
              'dependencies:\n'
              '  a: ^0.3.0\n',
        );
        final repo = node('b', dir);
        repo.dependencies['a'] = node('a', depDir);

        final decision = await check.get(
          repo: repo,
          refVersions: {'a': '0.4.0'},
        );
        expect(decision.skip, isFalse);
        expect(decision.reason, contains('outside the published constraint'));
      });

      test('does not force a publish for a compatible bump', () async {
        final depDir = createPlainRepo('a', pubspecContent: 'name: a\n');
        final dir = createPlainRepo(
          'b',
          pubspecContent: 'name: b\n'
              'dependencies:\n'
              '  a: ^1.0.0\n',
        );
        final repo = node('b', dir);
        repo.dependencies['a'] = node('a', depDir);

        final decision = await check.get(
          repo: repo,
          refVersions: {'a': '1.5.0'},
        );
        // The dependency produced no reason; only the missing git history
        // forces the publish.
        expect(decision.skip, isFalse);
        expect(
          decision.reason,
          contains('git history could not be inspected'),
        );
      });

      test('ignores dev-only dependencies', () async {
        final depDir = createPlainRepo('a', pubspecContent: 'name: a\n');
        final dir = createPlainRepo(
          'b',
          pubspecContent: 'name: b\n'
              'dev_dependencies:\n'
              '  a: ^1.0.0\n',
        );
        final repo = node('b', dir);
        repo.dependencies['a'] = node('a', depDir);

        final decision = await check.get(
          repo: repo,
          refVersions: {'a': '2.0.0'},
        );
        expect(decision.skip, isFalse);
        expect(
          decision.reason,
          contains('git history could not be inspected'),
        );
      });

      test('publishes when the dependency version is unknown', () async {
        final depDir = createPlainRepo('a', pubspecContent: 'name: a\n');
        final dir = createPlainRepo(
          'b',
          pubspecContent: 'name: b\n'
              'dependencies:\n'
              '  a: ^1.0.0\n',
        );
        final repo = node('b', dir);
        repo.dependencies['a'] = node('a', depDir);

        final decision = await check.get(repo: repo, refVersions: {});
        expect(decision.skip, isFalse);
        expect(decision.reason, contains('is unknown'));
      });

      test('publishes when the dependency version is unparsable', () async {
        final depDir = createPlainRepo('a', pubspecContent: 'name: a\n');
        final dir = createPlainRepo(
          'b',
          pubspecContent: 'name: b\n'
              'dependencies:\n'
              '  a: ^1.0.0\n',
        );
        final repo = node('b', dir);
        repo.dependencies['a'] = node('a', depDir);

        final decision = await check.get(
          repo: repo,
          refVersions: {'a': 'not-a-version'},
        );
        expect(decision.skip, isFalse);
        expect(decision.reason, contains('not a valid semver version'));
      });

      test('reads the original constraint from the Dart backup', () async {
        final depDir = createPlainRepo('a', pubspecContent: 'name: a\n');
        // The manifest is localized to a git ref; the original constraint
        // survives in .gg/.gg_localize_refs_backup.json and must win.
        final dir = createPlainRepo(
          'b',
          pubspecContent: 'name: b\n'
              'dependencies:\n'
              '  a:\n'
              '    git:\n'
              '      url: https://example.com/a.git\n'
              '      ref: feat\n',
        );
        Directory(path.join(dir.path, '.gg')).createSync();
        File(
          path.join(dir.path, '.gg', '.gg_localize_refs_backup.json'),
        ).writeAsStringSync('{"a": "^1.0.0"}');
        final repo = node('b', dir);
        repo.dependencies['a'] = node('a', depDir);

        final breaking = await check.get(
          repo: repo,
          refVersions: {'a': '2.0.0'},
        );
        expect(breaking.skip, isFalse);
        expect(breaking.reason, contains('outside the published constraint'));

        final compatible = await check.get(
          repo: repo,
          refVersions: {'a': '1.2.0'},
        );
        expect(
          compatible.reason,
          contains('git history could not be inspected'),
        );
      });

      test('reads the constraint from a map spec with version', () async {
        final depDir = createPlainRepo('a', pubspecContent: 'name: a\n');
        final dir = createPlainRepo(
          'b',
          pubspecContent: 'name: b\n'
              'dependencies:\n'
              '  a:\n'
              '    path: ../a\n',
        );
        Directory(path.join(dir.path, '.gg')).createSync();
        File(
          path.join(dir.path, '.gg', '.gg_localize_refs_backup.json'),
        ).writeAsStringSync(
          '{"a": {"git": {"url": "https://example.com/a.git"},'
          ' "version": "^1.0.0"}}',
        );
        final repo = node('b', dir);
        repo.dependencies['a'] = node('a', depDir);

        final decision = await check.get(
          repo: repo,
          refVersions: {'a': '2.0.0'},
        );
        expect(decision.skip, isFalse);
        expect(decision.reason, contains('outside the published constraint'));
      });

      test('publishes when a map spec has no version', () async {
        final depDir = createPlainRepo('a', pubspecContent: 'name: a\n');
        final dir = createPlainRepo(
          'b',
          pubspecContent: 'name: b\n'
              'dependencies:\n'
              '  a:\n'
              '    path: ../a\n',
        );
        Directory(path.join(dir.path, '.gg')).createSync();
        File(
          path.join(dir.path, '.gg', '.gg_localize_refs_backup.json'),
        ).writeAsStringSync(
          '{"a": {"git": {"url": "https://example.com/a.git"}}}',
        );
        final repo = node('b', dir);
        repo.dependencies['a'] = node('a', depDir);

        final decision = await check.get(
          repo: repo,
          refVersions: {'a': '1.0.1'},
        );
        expect(decision.skip, isFalse);
        expect(decision.reason, contains('could be determined'));
      });

      test('publishes when the backed-up constraint is empty', () async {
        final depDir = createPlainRepo('a', pubspecContent: 'name: a\n');
        final dir = createPlainRepo(
          'b',
          pubspecContent: 'name: b\n'
              'dependencies:\n'
              '  a:\n'
              '    path: ../a\n',
        );
        Directory(path.join(dir.path, '.gg')).createSync();
        File(
          path.join(dir.path, '.gg', '.gg_localize_refs_backup.json'),
        ).writeAsStringSync('{"a": ""}');
        final repo = node('b', dir);
        repo.dependencies['a'] = node('a', depDir);

        final decision = await check.get(
          repo: repo,
          refVersions: {'a': '1.0.1'},
        );
        expect(decision.skip, isFalse);
        expect(decision.reason, contains('could be determined'));
      });

      test('publishes when the backed-up spec has an unknown shape', () async {
        final depDir = createPlainRepo('a', pubspecContent: 'name: a\n');
        final dir = createPlainRepo(
          'b',
          pubspecContent: 'name: b\n'
              'dependencies:\n'
              '  a:\n'
              '    path: ../a\n',
        );
        Directory(path.join(dir.path, '.gg')).createSync();
        File(
          path.join(dir.path, '.gg', '.gg_localize_refs_backup.json'),
        ).writeAsStringSync('{"a": 42}');
        final repo = node('b', dir);
        repo.dependencies['a'] = node('a', depDir);

        final decision = await check.get(
          repo: repo,
          refVersions: {'a': '1.0.1'},
        );
        expect(decision.skip, isFalse);
        expect(decision.reason, contains('could be determined'));
      });

      test('honors the backup at the repo root (TS/legacy)', () async {
        final depDir = createPlainRepo('a', pubspecContent: 'name: a\n');
        final dir = createPlainRepo(
          'b',
          pubspecContent: 'name: b\n'
              'dependencies:\n'
              '  a:\n'
              '    path: ../a\n',
        );
        File(
          path.join(dir.path, '.gg_localize_refs_backup.json'),
        ).writeAsStringSync('{"a": "^1.0.0"}');
        final repo = node('b', dir);
        repo.dependencies['a'] = node('a', depDir);

        final decision = await check.get(
          repo: repo,
          refVersions: {'a': '2.0.0'},
        );
        expect(decision.skip, isFalse);
        expect(decision.reason, contains('outside the published constraint'));
      });

      test('an unreadable backup falls back to the manifest', () async {
        final depDir = createPlainRepo('a', pubspecContent: 'name: a\n');
        final dir = createPlainRepo(
          'b',
          pubspecContent: 'name: b\n'
              'dependencies:\n'
              '  a: ^1.0.0\n',
        );
        Directory(path.join(dir.path, '.gg')).createSync();
        File(
          path.join(dir.path, '.gg', '.gg_localize_refs_backup.json'),
        ).writeAsStringSync('no json');
        final repo = node('b', dir);
        repo.dependencies['a'] = node('a', depDir);

        final decision = await check.get(
          repo: repo,
          refVersions: {'a': '1.1.0'},
        );
        expect(
          decision.reason,
          contains('git history could not be inspected'),
        );
      });

      test('checks npm constraints from package.json', () async {
        final depDir = createPlainRepo(
          'a',
          packageJsonContent: '{"name": "@org/a", "version": "1.0.0"}',
        );
        final dir = createPlainRepo(
          'b',
          packageJsonContent: '{"name": "@org/b",'
              ' "dependencies": {"@org/a": "^1.0.0"}}',
        );
        final repo = node(
          '@org/b',
          dir,
          aliases: {'@org/b', 'b'},
        );
        repo.dependencies['@org/a'] = node(
          '@org/a',
          depDir,
          aliases: {'@org/a', 'a'},
        );

        final breaking = await check.get(
          repo: repo,
          refVersions: {'@org/a': '2.0.0'},
        );
        expect(breaking.skip, isFalse);
        expect(breaking.reason, contains('outside the published constraint'));

        final compatible = await check.get(
          repo: repo,
          refVersions: {'@org/a': '1.4.0'},
        );
        expect(
          compatible.reason,
          contains('git history could not be inspected'),
        );
      });

      test('publishes for an unparsable npm range', () async {
        final depDir = createPlainRepo(
          'a',
          packageJsonContent: '{"name": "@org/a", "version": "1.0.0"}',
        );
        final dir = createPlainRepo(
          'b',
          packageJsonContent: '{"name": "@org/b",'
              ' "dependencies": {"@org/a": "~1.0.0"}}',
        );
        final repo = node('@org/b', dir);
        repo.dependencies['@org/a'] = node('@org/a', depDir);

        final decision = await check.get(
          repo: repo,
          refVersions: {'@org/a': '1.0.1'},
        );
        expect(decision.skip, isFalse);
        expect(decision.reason, contains('could be determined'));
      });

      test('resolves the new version through dependency aliases', () async {
        final depDir = createPlainRepo('a_dart', pubspecContent: 'name: a\n');
        final dir = createPlainRepo(
          'b',
          pubspecContent: 'name: b\n'
              'dependencies:\n'
              '  a_dart: ^1.0.0\n',
        );
        final repo = node('b', dir);
        repo.dependencies['a_dart'] = node(
          'a_dart',
          depDir,
          aliases: {'a_dart', '@org/a', 'a'},
        );

        final decision = await check.get(
          repo: repo,
          refVersions: {'@org/a': '2.0.0'},
        );
        expect(decision.skip, isFalse);
        expect(decision.reason, contains('outside the published constraint'));
      });

      test('an unparsable pubspec yields no dependency reason', () async {
        final depDir = createPlainRepo('a', pubspecContent: 'name: a\n');
        final dir = createPlainRepo('b', pubspecContent: ': not: valid: [');
        final repo = node('b', dir);
        repo.dependencies['a'] = node('a', depDir);

        final decision = await check.get(
          repo: repo,
          refVersions: {'a': '2.0.0'},
        );
        expect(
          decision.reason,
          contains('git history could not be inspected'),
        );
      });

      test('an unparsable package.json yields no dependency reason', () async {
        final depDir = createPlainRepo('a', pubspecContent: 'name: a\n');
        final dir = createPlainRepo('b', packageJsonContent: 'no json');
        final repo = node('b', dir);
        repo.dependencies['a'] = node('a', depDir);

        final decision = await check.get(
          repo: repo,
          refVersions: {'a': '2.0.0'},
        );
        expect(
          decision.reason,
          contains('git history could not be inspected'),
        );
      });

      test('a non-object package.json yields no dependency reason', () async {
        final depDir = createPlainRepo('a', pubspecContent: 'name: a\n');
        final dir = createPlainRepo('b', packageJsonContent: '[]');
        final repo = node('b', dir);
        repo.dependencies['a'] = node('a', depDir);

        final decision = await check.get(
          repo: repo,
          refVersions: {'a': '2.0.0'},
        );
        expect(
          decision.reason,
          contains('git history could not be inspected'),
        );
      });

      test('publishes when an npm constraint is null', () async {
        final depDir = createPlainRepo(
          'a',
          packageJsonContent: '{"name": "@org/a", "version": "1.0.0"}',
        );
        final dir = createPlainRepo(
          'b',
          packageJsonContent: '{"name": "@org/b",'
              ' "dependencies": {"@org/a": null}}',
        );
        final repo = node('@org/b', dir);
        repo.dependencies['@org/a'] = node('@org/a', depDir);

        final decision = await check.get(
          repo: repo,
          refVersions: {'@org/a': '1.0.1'},
        );
        expect(decision.skip, isFalse);
        expect(decision.reason, contains('could be determined'));
      });

      test('skips a git repo whose dependency bump is compatible', () async {
        final depDir = createPlainRepo('a', pubspecContent: 'name: a\n');
        final dir = await createRepo(
          'b',
          pubspecContent: 'name: b\n'
              'version: 1.0.0\n'
              'dependencies:\n'
              '  a: ^1.0.0\n',
        );
        await git(dir, ['checkout', '-b', 'feat']);
        await commitFile(
          dir,
          'refs.txt',
          'refs',
          'gg_multi: changed references to git',
        );
        final repo = node('b', dir);
        repo.dependencies['a'] = node('a', depDir);

        final decision = await check.get(
          repo: repo,
          refVersions: {'a': '1.1.0'},
        );
        expect(decision.skip, isTrue);
        expect(decision.reason, contains('no manual changes'));
      });
    });
  });
}
