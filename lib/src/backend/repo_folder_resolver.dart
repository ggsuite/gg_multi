// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'url_parser.dart';

/// Resolves repository folders in a workspace. A folder is matched by its
/// exact name, then by its manifest package name (for cross-language bridge
/// repos whose folder name differs from the package name), then by its git
/// remote url.
class RepoFolderResolver {
  /// Returns the folder of [repoName] inside [workspacePath] or null,
  /// matching the exact folder name first, then the manifest package name.
  static Directory? resolve({
    required String workspacePath,
    required String repoName,
  }) {
    final exact = Directory(path.join(workspacePath, repoName));
    if (exact.existsSync()) {
      return exact;
    }
    for (final dir in _subDirs(workspacePath)) {
      if (packageName(dir) == repoName) {
        return dir;
      }
    }
    return null;
  }

  /// Returns the folder whose git remote matches [repoUrl] or null.
  static Directory? resolveByRemoteUrl({
    required String workspacePath,
    required String repoUrl,
  }) {
    final wanted = urlIdentity(repoUrl);
    if (wanted == null) {
      return null;
    }
    for (final dir in _subDirs(workspacePath)) {
      final url = remoteUrl(dir);
      if (url != null && urlIdentity(url) == wanted) {
        return dir;
      }
    }
    return null;
  }

  /// Package name from pubspec.yaml or package.json (npm scope stripped).
  static String? packageName(Directory dir) {
    try {
      final pubspec = File(path.join(dir.path, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        final match = RegExp(r'^name:\s*(\S+)', multiLine: true)
            .firstMatch(pubspec.readAsStringSync());
        return match?.group(1);
      }
      final packageJson = File(path.join(dir.path, 'package.json'));
      if (packageJson.existsSync()) {
        final json = jsonDecode(packageJson.readAsStringSync());
        final name = (json as Map<String, dynamic>)['name']?.toString();
        if (name == null) {
          return null;
        }
        return name.startsWith('@') ? name.split('/').last : name;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// First remote URL found in the folder's .git/config or null.
  static String? remoteUrl(Directory dir) {
    final config = File(path.join(dir.path, '.git', 'config'));
    if (!config.existsSync()) {
      return null;
    }
    final urlLine = config.readAsLinesSync().firstWhere(
          (line) => line.trim().startsWith('url ='),
          orElse: () => '',
        );
    final parts = urlLine.split('=');
    if (parts.length < 2) {
      return null;
    }
    return parts.sublist(1).join('=').trim();
  }

  /// `<org>/<repo>` identity of [url] for remote comparison, or null.
  static String? urlIdentity(String url) {
    final parsed = const UrlParser().parse(url);
    if (parsed.org == null || parsed.repo == null) {
      return null;
    }
    return '${parsed.org}/${parsed.repo}'.toLowerCase();
  }

  // ######################
  // Private
  // ######################

  // ...........................................................................
  /// Lists the direct subdirectories of [workspacePath].
  static List<Directory> _subDirs(String workspacePath) {
    final workspace = Directory(workspacePath);
    if (!workspace.existsSync()) {
      return const <Directory>[];
    }
    return workspace.listSync(recursive: false).whereType<Directory>().toList();
  }
}
