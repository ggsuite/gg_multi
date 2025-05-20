// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:path/path.dart' as path;

/// Utility functions that deal with the location of workspaces on disk.
class WorkspaceUtils {
  /// Returns the full path of the `kidney_ws_master` directory that belongs to
  /// the current working directory.
  ///
  /// The lookup algorithm climbs up the directory tree starting from
  /// [Directory.current] following these rules until a match is found or the
  /// filesystem root is reached:
  ///
  /// 1. If a directory named `kidney_ws_master` exists in the **examined**
  ///    folder, that directory is returned.
  /// 2. If a directory named `tickets` exists in the **examined** folder, the
  ///    parent of that folder is considered the project root and the path
  ///    `<root>/kidney_ws_master` is returned (even if the directory does not
  ///    yet exist).
  /// 3. If neither 1 nor 2 matches, the algorithm continues with the parent
  ///    directory. When the root of the filesystem is reached without a match
  ///    the path `<original working dir>/kidney_ws_master` is returned.  NOTE:
  ///    The path component separators of the *original* working directory are
  ///    preserved so that tests that have been written with mixed path
  ///    separators (e.g. forward slashes on Windows) still pass.
  ///
  /// This logic makes it possible to execute the binary from
  /// * inside the master workspace,
  /// * inside a ticket workspace, or
  /// * from any random sub-folder in the project tree,
  /// while still resolving the correct location for the master workspace.
  static String defaultMasterWorkspacePath({
    String? workingDir,
  }) {
    // coverage:ignore-start
    workingDir ??= Directory.current.path;
    // coverage:ignore-end

    var dir = Directory(workingDir);

    while (true) {
      // 1. Is there an existing master workspace in the current folder? -------
      if (Directory(path.join(dir.path, 'kidney_ws_master')).existsSync()) {
        return path.join(dir.path, 'kidney_ws_master');
      }

      // 2. Is the current folder the root that contains `tickets`? ------------
      if (Directory(path.join(dir.path, 'tickets')).existsSync()) {
        return path.join(dir.path, 'kidney_ws_master');
      }

      // 3. Go one level up or break when we are at the filesystem root. -------
      final parent = dir.parent;
      if (parent.path == dir.path) {
        // Reached filesystem root - build the fallback path **without**
        // modifying the original string so that any forward slashes that were
        // present in the test setup remain untouched.  We only append the
        // platform specific separator *between* the original path and the
        // `kidney_ws_master` segment.
        return path.join(workingDir, 'kidney_ws_master');
      }
      dir = parent;
    }
  }

  /// Returns the path of the Kidney workspace, which is the parent directory
  /// of the master workspace (`kidney_ws_master`).
  static String defaultKidneyWorkspacePath() {
    return path.dirname(defaultMasterWorkspacePath());
  }

  /// Returns `true` if [directoryPath] is located *inside* an existing Kidney
  /// workspace (i.e. one of its ancestor directories already contains a
  /// `kidney_ws_master` folder).  This is used by `init` to prevent nested
  /// workspaces.
  static bool isInsideExistingWorkspace(String directoryPath) {
    var dir = Directory(directoryPath).absolute;

    while (true) {
      if (Directory(path.join(dir.path, 'kidney_ws_master')).existsSync()) {
        return true;
      }

      final parent = dir.parent;
      if (parent.path == dir.path) {
        // We reached the filesystem root without finding a workspace.
        return false;
      }

      dir = parent;
    }
  }
}
