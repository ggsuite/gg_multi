// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:test/test.dart';
import 'package:kidney_core/src/commands/list_organizations.dart';

void main() {
  group('ListOrganizationsCommand', () {
    late Directory tempDir;
    late String originalDir;
    final messages = <String>[];

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('list_org_test');
      originalDir = Directory.current.path;
      Directory.current = tempDir.path;
      Directory('kidney_ws_master').createSync();
    });

    tearDown(() {
      Directory.current = originalDir;
      tempDir.deleteSync(recursive: true);
    });

    test('lists organizations uniquely sorted', () async {
      final masterPath =
          '${Directory.current.path}${Platform.pathSeparator}kidney_ws_master';
      // Repo1: inlavigo
      final repo1 = Directory('$masterPath${Platform.pathSeparator}repo1');
      repo1.createSync();
      File('${repo1.path}${Platform.pathSeparator}pubspec.yaml')
          .writeAsStringSync('name: repo1\nversion: 3.0.0');
      Directory('${repo1.path}${Platform.pathSeparator}.git').createSync();
      File('${repo1.path}${Platform.pathSeparator}.git'
              '${Platform.pathSeparator}config')
          .writeAsStringSync('url = https://github.com/inlavigo/repo1.git');

      // Repo2: microsoft
      final repo2 = Directory('$masterPath${Platform.pathSeparator}repo2');
      repo2.createSync();
      File('${repo2.path}${Platform.pathSeparator}pubspec.yaml')
          .writeAsStringSync('name: repo2\nversion: 2.5.0');
      Directory('${repo2.path}${Platform.pathSeparator}.git').createSync();
      File('${repo2.path}${Platform.pathSeparator}.git'
              '${Platform.pathSeparator}config')
          .writeAsStringSync('url = https://github.com/microsoft/repo2.git');

      // Repo3: inlavigo again
      final repo3 = Directory('$masterPath${Platform.pathSeparator}repo3');
      repo3.createSync();
      File('${repo3.path}${Platform.pathSeparator}pubspec.yaml')
          .writeAsStringSync('name: repo3\nversion: 1.0.0');
      Directory('${repo3.path}${Platform.pathSeparator}.git').createSync();
      File('${repo3.path}${Platform.pathSeparator}.git'
              '${Platform.pathSeparator}config')
          .writeAsStringSync('url = https://github.com/inlavigo/repo3.git');

      final command = ListOrganizationsCommand(ggLog: messages.add);
      await command.run();

      expect(
        messages,
        contains('inlavigo -- https://github.com/orgs/inlavigo/'),
      );
      expect(
        messages,
        contains('microsoft -- https://github.com/orgs/microsoft/'),
      );
    });
  });
}
