// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:kidney_core/src/backend/constants.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:kidney_core/src/backend/workspace_utils.dart';

void main() {
  group('WorkspaceUtils.defaultMasterWorkspacePath', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('workspace_utils_test_');
    });

    tearDown(() async {
      await tempRoot.delete(recursive: true);
    });

    test('returns existing master workspace in current folder', () async {
      // Arrange ---------------------------------------------------------------
      final masterDir = Directory(path.join(tempRoot.path, kidneyMasterFolder));
      await masterDir.create();

      // Act -------------------------------------------------------------------
      final result = WorkspaceUtils.defaultMasterWorkspacePath(
        workingDir: tempRoot.path,
      );

      // Assert ----------------------------------------------------------------
      expect(result, masterDir.path);
    });

    test('resolves master workspace from a ticket workspace', () async {
      // Arrange ---------------------------------------------------------------
      final ticketsDir = Directory(
        path.join(tempRoot.path, kidneyTicketFolder),
      );
      final ticketDir = Directory(path.join(ticketsDir.path, 'ticket_123'));
      await ticketDir.create(recursive: true);

      final expectedMaster = path.join(tempRoot.path, kidneyMasterFolder);

      // Act -------------------------------------------------------------------
      final result = WorkspaceUtils.defaultMasterWorkspacePath(
        workingDir: ticketDir.path,
      );

      // Assert ----------------------------------------------------------------
      expect(result, expectedMaster);
    });

    test('falls back to cwd when nothing is found', () async {
      // Arrange ---------------------------------------------------------------
      final randomDir =
          Directory(path.join(tempRoot.path, 'random', 'sub', 'folder'));
      await randomDir.create(recursive: true);
      final expectedMaster = path.join(randomDir.path, kidneyMasterFolder);

      // Act -------------------------------------------------------------------
      final result = WorkspaceUtils.defaultMasterWorkspacePath(
        workingDir: randomDir.path,
      );

      // Assert ----------------------------------------------------------------
      expect(result, expectedMaster);
    });
  });

  group('WorkspaceUtils.defaultKidneyWorkspacePath', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot =
          await Directory.systemTemp.createTemp('workspace_utils_testK_');
    });

    tearDown(() async {
      await tempRoot.delete(recursive: true);
    });

    test('returns parent of master workspace if existing', () async {
      final wsParent = Directory(path.join(tempRoot.path, 'the_workspace'));
      final masterDir = Directory(path.join(wsParent.path, kidneyMasterFolder));
      await masterDir.create(recursive: true);

      final result = WorkspaceUtils.defaultKidneyWorkspacePath(
        workingDir: wsParent.path,
      );
      expect(result, equals(wsParent.path));
    });

    test('returns parent of resolved master workspace path', () async {
      final ticketDir = Directory(
        path.join(tempRoot.path, 'parent', kidneyTicketFolder, 'TICKET-42'),
      )..createSync(recursive: true);
      final wsParent = Directory(path.join(tempRoot.path, 'parent'));

      final result = WorkspaceUtils.defaultKidneyWorkspacePath(
        workingDir: ticketDir.path,
      );
      expect(result, equals(wsParent.path));
    });

    test(
        'uses the parent of fallback cwd/.master '
        'when nothing is found', () async {
      final customCwd = Directory(path.join(tempRoot.path, 'zombie'));
      await customCwd.create(recursive: true);
      final result = WorkspaceUtils.defaultKidneyWorkspacePath(
        workingDir: customCwd.path,
      );
      expect(result, equals(customCwd.path));
    });
  });

  group('WorkspaceUtils.isInsideExistingWorkspace', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('utils_is_inside_test_');
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('returns false for directory not in or under any master workspace',
        () async {
      // Arrange -----------------------------------------------------------
      final randomDir = Directory(path.join(tempRoot.path, 'random', 'sub'));
      await randomDir.create(recursive: true);

      // Act ---------------------------------------------------------------
      final isInside = WorkspaceUtils.isInsideExistingWorkspace(randomDir.path);

      // Assert ------------------------------------------------------------
      expect(isInside, isFalse);
    });

    test('returns true for direct child of a folder with master workspace',
        () async {
      final root = Directory(path.join(tempRoot.path, 'myroot'));
      final ws = Directory(path.join(root.path, kidneyMasterFolder));
      await ws.create(recursive: true);

      final child = Directory(path.join(root.path, 'foo'));
      await child.create();

      final isInside = WorkspaceUtils.isInsideExistingWorkspace(child.path);

      expect(isInside, isTrue);
    });

    test('returns true for nested grandchild inside workspace', () async {
      // Arrange --------------------------------------------------------------
      final root = Directory(path.join(tempRoot.path, 'parent'));
      final ws = Directory(path.join(root.path, kidneyMasterFolder));
      await ws.create(recursive: true);
      final grandChild = Directory(path.join(root.path, 'nested', 'sub'));
      await grandChild.create(recursive: true);

      // Act ------------------------------------------------------------------
      final isInside =
          WorkspaceUtils.isInsideExistingWorkspace(grandChild.path);

      // Assert ---------------------------------------------------------------
      expect(isInside, isTrue);
    });

    test('returns true if searching at the workspace root itself', () async {
      // Arrange ---------------------------------------------------------------
      final root = Directory(path.join(tempRoot.path, 'x'));
      final ws = Directory(path.join(root.path, kidneyMasterFolder));
      await ws.create(recursive: true);

      // Act ------------------------------------------------------------------
      final isInside = WorkspaceUtils.isInsideExistingWorkspace(root.path);

      // Assert ---------------------------------------------------------------
      // The workspace folder is in root, not above root. So should be false.
      expect(isInside, isTrue);
    });

    test('returns true when rootPath is the actual master workspace folder',
        () async {
      // Arrange ------------------------------------------------------------
      final root = Directory(path.join(tempRoot.path, 'top'));
      final ws = Directory(path.join(root.path, kidneyMasterFolder));
      await ws.create(recursive: true);

      // Act ---------------------------------------------------------------
      // Call on the master workspace folder directly
      final isInside = WorkspaceUtils.isInsideExistingWorkspace(ws.path);

      // Assert ------------------------------------------------------------
      // Should be false: isInside means being a child or deeper
      expect(isInside, isTrue);
    });
  });
}
