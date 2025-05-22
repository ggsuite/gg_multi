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

    test('extractOrganizationFromUrl extracts org from HTTP-URL', () {
      final org = OrganizationUtils.extractOrganizationFromUrl(
        'https://github.com/foobar/repo.git',
      );
      expect(org, equals('foobar'));
    });

    test('extractOrganizationFromUrl extracts org from SSH-URL', () {
      final org = OrganizationUtils.extractOrganizationFromUrl(
        'git@github.com:foobar/barfoo.git',
      );
      expect(org, equals('foobar'));
    });

    test('extractOrganizationFromUrl returns null for random string', () {
      final org = OrganizationUtils.extractOrganizationFromUrl('foobar-git');
      expect(org, isNull);
    });
  });
}
