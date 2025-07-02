// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:path/path.dart' as path;
import 'package:kidney_core/src/backend/organization_utils.dart';

void main() {
  group('OrganizationUtils', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('org_utils_test_');
      OrganizationUtils.clearCache();
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('readOrganizations returns empty list if file does not exist', () {
      final orgs = OrganizationUtils.readOrganizations(tempDir.path);
      expect(orgs, isEmpty);
    });

    test('appendOrganization creates file and adds entry', () {
      const url = 'https://github.com/myorg/myrepo.git';
      OrganizationUtils.appendOrganization(tempDir.path, url);
      final orgs = OrganizationUtils.readOrganizations(tempDir.path);
      expect(orgs.any((o) => o.name == 'myorg'), isTrue);
      expect(orgs[0].url, 'https://github.com/myorg/');
      final file = File(path.join(tempDir.path, '.organizations'));
      expect(file.existsSync(), isTrue);
      final parsed = jsonDecode(file.readAsStringSync());
      expect(parsed is List, isTrue);
      expect(parsed[0]['name'], 'myorg');
      expect(parsed[0]['url'], 'https://github.com/myorg/');
    });

    test('second append with same org does not duplicate', () {
      OrganizationUtils.appendOrganization(
        tempDir.path,
        'https://github.com/myorg/myrepo.git',
      );
      OrganizationUtils.appendOrganization(
        tempDir.path,
        'https://github.com/myorg/another.git',
      );
      final orgs = OrganizationUtils.readOrganizations(tempDir.path);
      expect(orgs.length, 1);
      expect(orgs[0].name, 'myorg');
      expect(orgs[0].url, 'https://github.com/myorg/');
    });

    group('extractOrganizationFromUrl', () {
      group('extracts github org', () {
        test('from HTTP-URL for repo', () {
          final org = OrganizationUtils.extractOrganizationFromUrl(
            'https://github.com/foobar/repo.git',
          );
          expect(org, equals('foobar'));
        });

        test('from HTTP-URL for org', () {
          final org = OrganizationUtils.extractOrganizationFromUrl(
            'https://github.com/foobar',
          );
          expect(org, equals('foobar'));
        });

        test('from HTTP-URL with final / for org', () {
          final org = OrganizationUtils.extractOrganizationFromUrl(
            'https://github.com/foobar/',
          );
          expect(org, equals('foobar'));
        });

        test('from SSH-URL', () {
          final org = OrganizationUtils.extractOrganizationFromUrl(
            'git@github.com:foobar/barfoo.git',
          );
          expect(org, equals('foobar'));
        });
      });

      test('returns org name', () {
        final org = OrganizationUtils.extractOrganizationFromUrl('foobar-git');
        expect(org, equals('foobar-git'));
      });

      group('extracts Azure org', () {
        test('from SSH URL', () {
          const url = 'git@ssh.dev.azure.com:v3/devorg/sampleproj/reponame';
          final org = OrganizationUtils.extractOrganizationFromUrl(url);
          expect(org, equals('devorg'));
        });

        test('from https URL', () {
          const url = 'https://ssh.dev.azure.com:v3/devorg/sampleproj/reponame';
          final org = OrganizationUtils.extractOrganizationFromUrl(url);
          expect(org, equals('devorg'));
        });

        test('from SSH URL with git ending', () {
          const url =
              'git@ssh.dev.azure.com:v3/acme-lab_xyz/project/reponame.git';
          final org = OrganizationUtils.extractOrganizationFromUrl(url);
          expect(org, equals('acme-lab_xyz'));
        });
      });
    });

    test(
      'readOrganizations returns empty list if JSON parsing fails',
      () {
        final orgsFile = File(path.join(tempDir.path, '.organizations'));
        orgsFile.writeAsStringSync('invalid json!'); // not valid JSON
        final orgs = OrganizationUtils.readOrganizations(tempDir.path);
        expect(
          orgs,
          isEmpty,
          reason: 'Should return empty list if '
              '.organizations file contains invalid JSON',
        );
      },
    );

    test(
      'readOrganizations imports legacy Map format',
      () {
        final orgsFile = File(path.join(tempDir.path, '.organizations'));
        final legacy = {'a': 'u1', 'b': 'u2'};
        orgsFile.writeAsStringSync(jsonEncode(legacy));
        final orgs = OrganizationUtils.readOrganizations(tempDir.path);
        expect(orgs.length, 2);
        expect(orgs[0].name, 'a');
        expect(orgs[0].url, 'u1');
        expect(orgs[1].name, 'b');
        expect(orgs[1].url, 'u2');
      },
    );

    test(
      'readOrganizations returns empty list if JSON is not List or Map',
      () {
        final orgsFile = File(path.join(tempDir.path, '.organizations'));
        orgsFile.writeAsStringSync(jsonEncode('this is neither list nor map'));
        final orgs = OrganizationUtils.readOrganizations(tempDir.path);
        expect(orgs, isEmpty);
      },
    );

    test('readOrganizations reads list format', () {
      // This test covers the code path where the file
      // contains a proper JSON list of Organization objects.
      OrganizationUtils.clearCache();
      final file = File(path.join(tempDir.path, '.organizations'));
      final listJson = [
        {'id': '1', 'name': 'o1', 'url': 'u1'},
        {'id': '2', 'name': 'o2', 'url': 'u2', 'projectName': 'p2'},
      ];
      file.writeAsStringSync(jsonEncode(listJson));
      final orgs = OrganizationUtils.readOrganizations(tempDir.path);
      expect(orgs.length, 2);
      expect(orgs[0].name, 'o1');
      expect(orgs[1].projectName, 'p2');
      // Test cache by identical call
      final orgs2 = OrganizationUtils.readOrganizations(tempDir.path);
      expect(identical(orgs, orgs2), isTrue);
    });

    group('buildBaseUrl', () {
      test('returns GitHub HTTPS URL for SSH repoUrl', () {
        final result = OrganizationUtils.buildBaseUrl(
          'git@github.com:myorg/myrepo.git',
          'myorg',
        );
        expect(result, equals('https://github.com/myorg/'));
      });

      test('returns correct HTTPS URL for HTTP(S) repoUrl', () {
        final result = OrganizationUtils.buildBaseUrl(
          'https://gitlab.com/fooorg/myrepo.git',
          'fooorg',
        );
        expect(result, equals('https://gitlab.com/fooorg/'));
      });

      test('falls back to GitHub HTTPS URL on parse error', () {
        final result = OrganizationUtils.buildBaseUrl(
          'https://in valid',
          'someOrg',
        );
        expect(result, equals('https://github.com/someOrg/'));
      });

      test('returns fallback URL when host is empty', () {
        final result = OrganizationUtils.buildBaseUrl(
          'https:///anything',
          'fallback',
        );
        expect(result, equals('https://github.com/fallback/'));
      });

      test('returns fallback URL when host contains invalid characters', () {
        final result = OrganizationUtils.buildBaseUrl(
          'https://examp!e.com/repo.git',
          'fallback',
        );
        expect(result, equals('https://github.com/fallback/'));
      });

      test('returns correct Azure SSH URL for org base', () {
        const url = 'git@ssh.dev.azure.com:v3/myorg/myproj/myrepo';
        const org = 'myorg';
        final base = OrganizationUtils.buildBaseUrl(url, org);
        expect(base, equals('https://ssh.dev.azure.com:v3/myorg/'));
      });
    });
  });
}
