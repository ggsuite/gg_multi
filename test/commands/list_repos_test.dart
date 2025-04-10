// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:test/test.dart';
import 'package:kidney_core/src/commands/list_repos.dart';

void main() {
  group('ListReposCommand', () {
    late Directory tempDir;
    late String originalDir;
    final messages = <String>[];

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('list_repos_test');
      originalDir = Directory.current.path;
      Directory.current = tempDir.path;
      Directory('kidney_ws_master').createSync();
    });

    tearDown(() {
      Directory.current = originalDir;
      tempDir.deleteSync(recursive: true);
    });

    test('lists repositories correctly', () async {
      final masterPath =
          '${Directory.current.path}${Platform.pathSeparator}kidney_ws_master';
      // Create repo 'json_dart'
      final repo1 = Directory('$masterPath${Platform.pathSeparator}json_dart');
      repo1.createSync();
      File('${repo1.path}${Platform.pathSeparator}pubspec.yaml')
          .writeAsStringSync('name: json_dart\nversion: 3.5.2');
      Directory('${repo1.path}${Platform.pathSeparator}.git').createSync();
      File('${repo1.path}${Platform.pathSeparator}.git'
              '${Platform.pathSeparator}config')
          .writeAsStringSync('url = https://github.com/inlavigo/json_dart.git');

      // Create repo 'project123' without pubspec
      // (default language should be dart)
      final repo2 = Directory('$masterPath${Platform.pathSeparator}project123');
      repo2.createSync();
      Directory('${repo2.path}${Platform.pathSeparator}.git').createSync();
      File('${repo2.path}${Platform.pathSeparator}.git'
              '${Platform.pathSeparator}config')
          .writeAsStringSync(
        'url = https://github.com/microsoft/project123.git',
      );

      final command = ListReposCommand(ggLog: messages.add);
      await command.run();

      expect(
        messages,
        contains('json_dart v.3.5.2 (dart) from inlavigo'),
      );
      expect(
        messages,
        contains('project123 v.1.0.0 (dart) from microsoft'),
      );
    });
  });
}
