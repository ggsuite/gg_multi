// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'package:gg_multi/src/backend/status_utils.dart';

import '../rm_console_colors_helper.dart';

class MockGgLog extends Mock {
  void call(String message);
}

void main() {
  group('StatusUtils', () {
    late Directory tempDir;
    late List<String> logMessages;

    void ggLog(String message) {
      logMessages.add(rmConsoleColors(message));
    }

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('status_utils_test_');
      logMessages = [];
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('setStatus writes JSON file correctly', () {
      final repoDir = Directory(path.join(tempDir.path, 'repo'))
        ..createSync(recursive: true);

      StatusUtils.setStatus(
        repoDir,
        StatusUtils.statusLocalized,
        ggLog: ggLog,
      );

      final statusFile = File(path.join(repoDir.path, '.gg_multi_status'));
      expect(statusFile.existsSync(), isTrue);
      final content =
          jsonDecode(statusFile.readAsStringSync()) as Map<String, dynamic>;
      expect(content['status'], StatusUtils.statusLocalized);
    });

    test('setStatus logs error but does not throw on failure', () {
      final repoDir = Directory(path.join(tempDir.path, 'repo'))
        ..createSync(recursive: true);
      // Make the directory read-only to simulate write failure
      repoDir.createSync(); // Ensure it exists

      expect(
        () => StatusUtils.setStatus(
          Directory('/invalid/path'),
          'test',
          ggLog: ggLog,
        ),
        returnsNormally,
      );
      expect(
        logMessages.first,
        contains(
          'Failed to set status',
        ),
      );
    });

    test('constants are correctly defined', () {
      expect(StatusUtils.statusUnlocalized, 'unlocalized');
      expect(StatusUtils.statusLocalized, 'localized');
      expect(StatusUtils.statusGitLocalized, 'git-localized');
      expect(StatusUtils.statusLocalMerged, 'local-merged');
      expect(StatusUtils.statusMerged, 'merged');
    });

    group('readStatus', () {
      test('returns status when file exists and is valid', () {
        final repoDir = Directory(path.join(tempDir.path, 'repo'))
          ..createSync(recursive: true);
        File(path.join(repoDir.path, '.gg_multi_status'))
            .writeAsStringSync(jsonEncode({'status': 'localized'}));

        final status = StatusUtils.readStatus(repoDir, ggLog: ggLog);
        expect(status, 'localized');
        expect(logMessages, isEmpty);
      });

      test('returns null and logs error when file does not exist', () {
        final repoDir = Directory(path.join(tempDir.path, 'no_file_repo'))
          ..createSync(recursive: true);

        final status = StatusUtils.readStatus(repoDir, ggLog: ggLog);
        expect(status, isNull);
        expect(
          logMessages.first,
          contains('Missing .gg_multi_status file in ${repoDir.path}'),
        );
      });

      test('returns null and logs error when parsing fails', () {
        final repoDir = Directory(path.join(tempDir.path, 'bad_json_repo'))
          ..createSync(recursive: true);
        File(path.join(repoDir.path, '.gg_multi_status'))
            .writeAsStringSync('invalid json');

        final status = StatusUtils.readStatus(repoDir, ggLog: ggLog);
        expect(status, isNull);
        expect(
          logMessages.first,
          contains('Failed to read status from ${repoDir.path}: '),
        );
      });

      test('returns null when status key is missing in JSON', () {
        final repoDir = Directory(path.join(tempDir.path, 'missing_key_repo'))
          ..createSync(recursive: true);
        File(path.join(repoDir.path, '.gg_multi_status'))
            .writeAsStringSync(jsonEncode({}));

        final status = StatusUtils.readStatus(repoDir, ggLog: ggLog);
        expect(status, isNull);
        expect(logMessages, isEmpty);
      });
    });
  });
}
