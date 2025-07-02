// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:kidney_core/src/backend/organization_utils.dart';
import 'package:kidney_core/src/backend/organization.dart';
import 'package:path/path.dart' as path;

void main() {
  group('OrganizationUtils buffer/cache', () {
    late Directory tempDir;
    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('org_buffer_');
      OrganizationUtils.clearCache();
    });
    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('caches organizations from file', () {
      final orgFile = File(path.join(tempDir.path, '.organizations'));
      final orgsList = [
        {
          'id': 'id1',
          'name': 'foo',
          'url': 'u',
          'projectName': 'pn',
        },
        {
          'id': 'id2',
          'name': 'bar',
          'url': 'v',
        }
      ];
      orgFile.writeAsStringSync(jsonEncode(orgsList));
      final firstRead = OrganizationUtils.readOrganizations(tempDir.path);
      final secondRead = OrganizationUtils.readOrganizations(tempDir.path);
      expect(identical(firstRead, secondRead), isTrue);
      expect(firstRead.length, 2);
      expect(firstRead[0].name, 'foo');
    });

    test('ignores file after caching even if file is changed', () {
      final orgFile = File(path.join(tempDir.path, '.organizations'));
      orgFile.writeAsStringSync(
        jsonEncode([
          {
            'id': 'id1',
            'name': 'foo',
            'url': 'bar',
          }
        ]),
      );
      OrganizationUtils.readOrganizations(tempDir.path);
      orgFile.writeAsStringSync(
        jsonEncode([
          {
            'id': 'id2',
            'name': 'baz',
            'url': 'qux',
          }
        ]),
      );
      final again = OrganizationUtils.readOrganizations(tempDir.path);
      expect(again[0].name, 'foo');
      expect(again[0].id, 'id1');
    });

    test('addOrganization adds and updates cache + disk', () {
      expect(OrganizationUtils.readOrganizations(tempDir.path), isEmpty);
      final org = Organization(name: 'org1', url: 'u1');
      OrganizationUtils.addOrganization(tempDir.path, org);
      final cached = OrganizationUtils.readOrganizations(tempDir.path);
      expect(cached.length, 1);
      expect(cached[0].name, 'org1');
      // File was written as well
      final diskOrg = File(path.join(tempDir.path, '.organizations'));
      final json = jsonDecode(diskOrg.readAsStringSync());
      expect(json[0]['name'], 'org1');
    });

    test('does not add duplicate organizations by name', () {
      final org = Organization(name: 'dupe', url: 'u');
      OrganizationUtils.addOrganization(tempDir.path, org);
      final again = Organization(name: 'dupe', url: 'otheru');
      OrganizationUtils.addOrganization(tempDir.path, again);
      final all = OrganizationUtils.readOrganizations(tempDir.path);
      expect(all.length, 1, reason: 'No duplicates allowed');
    });

    test('getOrganizationByName finds by name', () {
      OrganizationUtils.clearCache();
      final o1 = Organization(name: 'xx', url: 'yy');
      OrganizationUtils.addOrganization(tempDir.path, o1);
      final res = OrganizationUtils.getOrganizationByName(tempDir.path, 'xx');
      expect(res, isNotNull);
      expect(res!.name, 'xx');
    });

    test('getOrganizationByName returns null if not present', () {
      OrganizationUtils.clearCache();
      expect(
        OrganizationUtils.getOrganizationByName(tempDir.path, 'qw'),
        isNull,
      );
    });

    test('getOrganizationByRepoUrl works via org extraction', () {
      OrganizationUtils.clearCache();
      final org = Organization(name: 'someorg', url: 'url');
      OrganizationUtils.addOrganization(tempDir.path, org);
      const url = 'git@github.com:someorg/some-repo.git';
      final found = OrganizationUtils.getOrganizationByRepoUrl(
        tempDir.path,
        url,
      );
      expect(found, isNotNull);
      expect(found!.name, 'someorg');
    });
  });
}
