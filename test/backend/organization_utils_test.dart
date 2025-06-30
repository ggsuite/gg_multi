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
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('readOrganizations returns empty map if file does not exist', () {
      final orgs = OrganizationUtils.readOrganizations(tempDir.path);
      expect(orgs, isEmpty);
    });

    test('appendOrganization creates file and adds entry', () {
      OrganizationUtils.appendOrganization(
        tempDir.path,
        'https://github.com/myorg/myrepo.git',
      );
      final orgs = OrganizationUtils.readOrganizations(tempDir.path);
      expect(orgs, contains('myorg'));
      expect(orgs['myorg'], 'https://github.com/myorg/');
      final file = File(path.join(tempDir.path, '.organizations'));
      expect(file.existsSync(), isTrue);
      final parsed = jsonDecode(file.readAsStringSync()) as Map;
      expect(parsed['myorg'], 'https://github.com/myorg/');
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
      expect(orgs['myorg'], 'https://github.com/myorg/');
    });

    test('extractOrganizationFromUrl extracts org from HTTP-URL for repo', () {
      final org = OrganizationUtils.extractOrganizationFromUrl(
        'https://github.com/foobar/repo.git',
      );
      expect(org, equals('foobar'));
    });

    test('extractOrganizationFromUrl extracts org from HTTP-URL for org', () {
      final org = OrganizationUtils.extractOrganizationFromUrl(
        'https://github.com/foobar',
      );
      expect(org, equals('foobar'));
    });

    test('extractOrganizationFromUrl extracts org '
        'from HTTP-URL with final / for org', () {
      final org = OrganizationUtils.extractOrganizationFromUrl(
        'https://github.com/foobar/',
      );
      expect(org, equals('foobar'));
    });

    test('extractOrganizationFromUrl extracts org from SSH-URL', () {
      final org = OrganizationUtils.extractOrganizationFromUrl(
        'git@github.com:foobar/barfoo.git',
      );
      expect(org, equals('foobar'));
    });

    test('extractOrganizationFromUrl returns org name', () {
      final org = OrganizationUtils.extractOrganizationFromUrl('foobar-git');
      expect(org, equals('foobar-git'));
    });

    test(
      'readOrganizations returns empty map if JSON parsing fails',
      () {
        final orgsFile = File(path.join(tempDir.path, '.organizations'));
        orgsFile.writeAsStringSync('invalid json!'); // not valid JSON
        final orgs = OrganizationUtils.readOrganizations(tempDir.path);
        expect(
          orgs,
          isEmpty,
          reason: 'Should return empty map if '
              '.organizations file contains invalid JSON',
        );
      },
    );

    test(
      'readOrganizations returns empty map if JSON is not a Map',
      () {
        final orgsFile = File(path.join(tempDir.path, '.organizations'));
        orgsFile.writeAsStringSync(jsonEncode(['not', 'a', 'map']));
        final orgs = OrganizationUtils.readOrganizations(tempDir.path);
        expect(
          orgs,
          isEmpty,
          reason: 'Should return empty map if .organizations '
              'file contains valid JSON but is not a Map',
        );
      },
    );

    group('buildBaseUrl', () {
      test('returns GitHub HTTPS URL for SSH repoUrl', () {
        // This branch covers the line return 'https://github.com/\u001forg/';
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
        // Simulate an invalid URL which throws in Uri.parse()
        final result = OrganizationUtils.buildBaseUrl(
          'https://in valid',
          'someOrg',
        );
        expect(result, equals('https://github.com/someOrg/'));
      });

      test('returns fallback URL when host is empty', () {
        // This triggers the branch where uri.host.isEmpty
        final result = OrganizationUtils.buildBaseUrl(
          'https:///anything',
          'fallback',
        );
        expect(result, equals('https://github.com/fallback/'));
      });

      test('returns fallback URL when host contains invalid characters', () {
        // This triggers the branch where uri.host has invalid chars
        final result = OrganizationUtils.buildBaseUrl(
          'https://examp!e.com/repo.git',
          'fallback',
        );
        expect(result, equals('https://github.com/fallback/'));
      });
    });
  });
}
