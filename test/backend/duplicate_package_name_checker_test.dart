// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_multi/src/backend/duplicate_package_name_checker.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory workspace;
  late String workspacePath;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('duplicate_names_test');
    workspacePath = workspace.path;
  });

  tearDown(() {
    if (workspace.existsSync()) {
      workspace.deleteSync(recursive: true);
    }
  });

  /// Creates `<workspace>/<org>/<repo>` with the given manifests.
  Directory createRepo(
    String org,
    String repo, {
    String? dartName,
    String? npmName,
  }) {
    final dir = Directory(path.join(workspacePath, org, repo))
      ..createSync(recursive: true);
    if (dartName != null) {
      File(path.join(dir.path, 'pubspec.yaml'))
          .writeAsStringSync('name: $dartName\nversion: 1.0.0\n');
    }
    if (npmName != null) {
      File(path.join(dir.path, 'package.json'))
          .writeAsStringSync('{"name": "$npmName"}');
    }
    return dir;
  }

  group('declaredPackageNames', () {
    test('returns the dart name of a pubspec.yaml', () {
      final dir = createRepo('org', 'repo', dartName: 'my_package');
      expect(declaredPackageNames(dir), <String>{'dart:my_package'});
    });

    test('returns the npm name including its scope', () {
      final dir = createRepo('org', 'repo', npmName: '@scope/my-package');
      expect(declaredPackageNames(dir), <String>{'npm:@scope/my-package'});
    });

    test('returns both names of a cross-language repository', () {
      final dir = createRepo(
        'org',
        'repo',
        dartName: 'bridge',
        npmName: '@org/bridge',
      );
      expect(
        declaredPackageNames(dir),
        <String>{'dart:bridge', 'npm:@org/bridge'},
      );
    });

    test('returns nothing when the repository has no manifest', () {
      final dir = createRepo('org', 'repo');
      expect(declaredPackageNames(dir), isEmpty);
    });

    test('returns nothing when a manifest cannot be parsed', () {
      final dir = createRepo('org', 'repo');
      File(path.join(dir.path, 'package.json')).writeAsStringSync('{ not json');
      expect(declaredPackageNames(dir), isEmpty);
    });

    test('returns nothing when pubspec.yaml declares no name', () {
      final dir = createRepo('org', 'repo');
      File(path.join(dir.path, 'pubspec.yaml'))
          .writeAsStringSync('version: 1.0.0\n');
      expect(declaredPackageNames(dir), isEmpty);
    });

    test('returns nothing when package.json declares no name', () {
      final dir = createRepo('org', 'repo');
      File(path.join(dir.path, 'package.json'))
          .writeAsStringSync('{"version": "1.0.0"}');
      expect(declaredPackageNames(dir), isEmpty);
    });

    test('returns nothing when package.json is no object', () {
      final dir = createRepo('org', 'repo');
      File(path.join(dir.path, 'package.json')).writeAsStringSync('[]');
      expect(declaredPackageNames(dir), isEmpty);
    });
  });

  group('throwOnDuplicatePackageName', () {
    test('does nothing when the package name is unique', () {
      createRepo('org_a', 'repo_a', dartName: 'package_a');
      final added = createRepo('org_b', 'repo_b', dartName: 'package_b');

      expect(
        () => throwOnDuplicatePackageName(
          workspacePath: workspacePath,
          repoDir: added,
        ),
        returnsNormally,
      );
    });

    test('does nothing when the repository declares no package name', () {
      createRepo('org_a', 'repo_a', dartName: 'package_a');
      final added = createRepo('org_b', 'repo_b');

      expect(
        () => throwOnDuplicatePackageName(
          workspacePath: workspacePath,
          repoDir: added,
        ),
        returnsNormally,
      );
    });

    test('throws when another repository declares the same dart name', () {
      createRepo('org_a', 'repo_a', dartName: 'package');
      final added = createRepo('org_b', 'repo_b', dartName: 'package');

      expect(
        () => throwOnDuplicatePackageName(
          workspacePath: workspacePath,
          repoDir: added,
        ),
        throwsA(
          isA<DuplicatePackageNameException>()
              .having((e) => e.packageName, 'packageName', 'package')
              .having(
                (e) => e.addedRepo,
                'addedRepo',
                path.join('org_b', 'repo_b'),
              )
              .having(
                (e) => e.existingRepo,
                'existingRepo',
                path.join('org_a', 'repo_a'),
              ),
        ),
      );
    });

    test('throws when another repository declares the same npm name', () {
      createRepo('org_a', 'repo_a', npmName: '@scope/package');
      final added = createRepo('org_b', 'repo_b', npmName: '@scope/package');

      expect(
        () => throwOnDuplicatePackageName(
          workspacePath: workspacePath,
          repoDir: added,
        ),
        throwsA(
          isA<DuplicatePackageNameException>().having(
            (e) => e.packageName,
            'packageName',
            '@scope/package',
          ),
        ),
      );
    });

    test('does not confuse a dart package with an npm package', () {
      createRepo('org_a', 'repo_a', dartName: 'package');
      final added = createRepo('org_b', 'repo_b', npmName: 'package');

      expect(
        () => throwOnDuplicatePackageName(
          workspacePath: workspacePath,
          repoDir: added,
        ),
        returnsNormally,
      );
    });

    test('does not confuse two npm packages of different scopes', () {
      createRepo('org_a', 'repo_a', npmName: '@a/package');
      final added = createRepo('org_b', 'repo_b', npmName: '@b/package');

      expect(
        () => throwOnDuplicatePackageName(
          workspacePath: workspacePath,
          repoDir: added,
        ),
        returnsNormally,
      );
    });

    test('does not compare the repository with itself', () {
      final added = createRepo('org_a', 'repo_a', dartName: 'package');

      expect(
        () => throwOnDuplicatePackageName(
          workspacePath: workspacePath,
          repoDir: added,
        ),
        returnsNormally,
      );
    });

    test('names both repositories in its message', () {
      createRepo('org_a', 'repo_a', dartName: 'package');
      final added = createRepo('org_b', 'repo_b', dartName: 'package');

      try {
        throwOnDuplicatePackageName(
          workspacePath: workspacePath,
          repoDir: added,
        );
        fail('Expected a DuplicatePackageNameException.');
      } on DuplicatePackageNameException catch (e) {
        expect(e.toString(), contains('package'));
        expect(e.toString(), contains(path.join('org_a', 'repo_a')));
        expect(e.toString(), contains(path.join('org_b', 'repo_b')));
      }
    });
  });
}
