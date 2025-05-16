// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:kidney_core/src/backend/workspace_utils.dart';

void main() {
  group('WorkspaceUtils.defaultMasterWorkspacePath', () {
    late Directory tempRoot;
    late String originalCwd;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('workspace_utils_test_');
      originalCwd = Directory.current.path;
    });

    tearDown(() async {
      // Reset working directory and clean up.
      Directory.current = Directory(originalCwd);
      await tempRoot.delete(recursive: true);
    });

    test('returns existing master workspace in current folder', () async {
      // Arrange ---------------------------------------------------------------
      final masterDir = Directory(path.join(tempRoot.path, 'kidney_ws_master'));
      await masterDir.create();
      Directory.current = tempRoot;

      // Act -------------------------------------------------------------------
      final result = WorkspaceUtils.defaultMasterWorkspacePath();

      // Assert ----------------------------------------------------------------
      expect(result, masterDir.path);
    });

    test('resolves master workspace from a ticket workspace', () async {
      // Arrange ---------------------------------------------------------------
      final ticketsDir = Directory(path.join(tempRoot.path, 'tickets'));
      final ticketDir = Directory(path.join(ticketsDir.path, 'ticket_123'));
      await ticketDir.create(recursive: true);

      Directory.current = ticketDir;
      final expectedMaster = path.join(tempRoot.path, 'kidney_ws_master');

      // Act -------------------------------------------------------------------
      final result = WorkspaceUtils.defaultMasterWorkspacePath();

      // Assert ----------------------------------------------------------------
      expect(result, expectedMaster);
    });

    test('falls back to cwd when nothing is found', () async {
      // Arrange ---------------------------------------------------------------
      final randomDir =
          Directory(path.join(tempRoot.path, 'random', 'sub', 'folder'));
      await randomDir.create(recursive: true);
      Directory.current = randomDir;
      final expectedMaster = path.join(randomDir.path, 'kidney_ws_master');

      // Act -------------------------------------------------------------------
      final result = WorkspaceUtils.defaultMasterWorkspacePath();

      // Assert ----------------------------------------------------------------
      expect(result, expectedMaster);
    });
  });
}
