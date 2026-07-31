// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'repo_folder_resolver.dart';

/// Thrown when a repository declares a package name that another repository
/// of the same workspace already declares.
class DuplicatePackageNameException implements Exception {
  /// Constructor
  DuplicatePackageNameException({
    required this.packageName,
    required this.addedRepo,
    required this.existingRepo,
  });

  /// The package name owned by two repositories.
  final String packageName;

  /// Path of the repository that was about to be added, relative to the
  /// workspace.
  final String addedRepo;

  /// Path of the repository that already owns [packageName], relative to the
  /// workspace.
  final String existingRepo;

  @override
  String toString() => 'Package name "$packageName" of $addedRepo is already '
      'used by $existingRepo. Rename one of the packages.';
}

/// Returns the package names [repoDir] declares, each prefixed by its
/// ecosystem (`dart:<name>`, `npm:<name>`).
///
/// The prefix keeps a Dart package and an npm package of the same name apart:
/// they live in different registries and do not collide. The npm scope is
/// part of the name for the same reason — `@a/foo` and `@b/foo` are two
/// packages, not one.
///
/// A repository can declare both, e.g. a cross-language bridge shipping a
/// `pubspec.yaml` and a `package.json`.
Set<String> declaredPackageNames(Directory repoDir) {
  final result = <String>{};

  try {
    final pubspec = File(path.join(repoDir.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      final match = RegExp(r'^name:\s*(\S+)', multiLine: true)
          .firstMatch(pubspec.readAsStringSync());
      final name = match?.group(1);
      if (name != null) {
        result.add('dart:$name');
      }
    }

    final packageJson = File(path.join(repoDir.path, 'package.json'));
    if (packageJson.existsSync()) {
      final json = jsonDecode(packageJson.readAsStringSync());
      final name = json is Map<String, dynamic> ? json['name'] : null;
      if (name is String && name.isNotEmpty) {
        result.add('npm:$name');
      }
    }
  } catch (_) {
    // An unreadable manifest declares nothing.
  }

  return result;
}

/// Throws a [DuplicatePackageNameException] when [repoDir] declares a package
/// name that another repository in [workspacePath] already declares.
///
/// Two repositories owning one package name break every lookup that goes by
/// package name — the dependency graph, `RepoFolderResolver.resolve`, the
/// localization of references — so such a repository must not enter the
/// workspace in the first place.
void throwOnDuplicatePackageName({
  required String workspacePath,
  required Directory repoDir,
}) {
  final added = declaredPackageNames(repoDir);
  if (added.isEmpty) {
    return;
  }

  for (final other in RepoFolderResolver.repoDirs(workspacePath)) {
    if (path.equals(other.path, repoDir.path)) {
      continue;
    }
    final shared = declaredPackageNames(other).intersection(added);
    if (shared.isEmpty) {
      continue;
    }
    final qualified = (shared.toList()..sort()).first;
    throw DuplicatePackageNameException(
      packageName: qualified.substring(qualified.indexOf(':') + 1),
      addedRepo: RepoFolderResolver.relativePath(
        workspacePath: workspacePath,
        repoDir: repoDir,
      ),
      existingRepo: RepoFolderResolver.relativePath(
        workspacePath: workspacePath,
        repoDir: other,
      ),
    );
  }
}
