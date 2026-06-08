// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:path/path.dart' as path;

/// Recursively copies [source] to [destination].
///
/// * Creates the destination directory if it does not exist.
/// * Copies files and sub-directories.
/// * Skips top-level entries listed in [skipNames]; the default
///   skip-list excludes `node_modules` so pnpm's symlinked
///   `node_modules/.pnpm/<pkg>/node_modules/<dep>` chains never get
///   dereferenced and reduced to a flat copy. The destination repo is
///   expected to run its package-manager's install step after copying
///   to rebuild `node_modules` from scratch.
///
/// Throws an [ArgumentError] if the source directory does not exist.
Future<void> copyDirectory(
  Directory source,
  Directory destination, {
  Set<String> skipNames = const {'node_modules'},
}) async {
  if (!source.existsSync()) {
    throw ArgumentError('Source directory ${source.path} does not exist');
  }

  // Ensure the destination directory exists.
  if (!destination.existsSync()) {
    await destination.create(recursive: true);
  }

  await for (final entity in source.list(recursive: false)) {
    final name = path.basename(entity.path);
    if (skipNames.contains(name)) continue;
    String newPath = path.join(destination.path, name);
    // change .darta to .dart if the file is a .darta file
    if (entity is File && path.extension(entity.path) == '.darta') {
      newPath = '${path.withoutExtension(newPath)}.dart';
    }
    if (entity is File) {
      await entity.copy(newPath);
    } else if (entity is Directory) {
      // Recurse into sub-directories.
      await copyDirectory(entity, Directory(newPath), skipNames: skipNames);
    }
  }
}
