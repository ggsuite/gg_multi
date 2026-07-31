// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// The file gg_localize_refs writes the local path overrides to.
const String pubspecOverridesFileName = 'pubspec_overrides.yaml';

/// Removes [packageNames] from the `dependency_overrides` of the
/// `pubspec_overrides.yaml` of every repo in [repoDirs] and returns the
/// directories whose file was changed.
///
/// gg_localize_refs points those overrides at the sibling checkouts of the
/// ticket (`path: ../<repo>`). When a repo leaves the ticket, its entry
/// becomes a dangling path and every `pub get` of the remaining repos fails —
/// so the entry goes with it. A file that holds nothing but the removed
/// entries is deleted instead of left behind as an empty override.
///
/// Repos without the file, without a `dependency_overrides` section, or
/// without any of [packageNames] are left untouched. An unparsable file is
/// skipped as well: it is the user's, and guessing at it could destroy it.
List<Directory> removeDependencyOverrides({
  required Iterable<Directory> repoDirs,
  required Set<String> packageNames,
}) {
  final changed = <Directory>[];
  if (packageNames.isEmpty) return changed;

  for (final repoDir in repoDirs) {
    final file = File(path.join(repoDir.path, pubspecOverridesFileName));
    if (!file.existsSync()) continue;

    final content = file.readAsStringSync();
    final Object? parsed;
    try {
      parsed = loadYaml(content);
    } on YamlException {
      continue;
    }
    if (parsed is! YamlMap) continue;

    final overrides = parsed['dependency_overrides'];
    if (overrides is! YamlMap) continue;

    final toRemove = packageNames.where(overrides.containsKey).toList();
    if (toRemove.isEmpty) continue;

    if (toRemove.length == overrides.length) {
      // Nothing would be left to override — an empty `dependency_overrides`
      // is invalid for pub, so the generated file goes away entirely.
      file.deleteSync();
      changed.add(repoDir);
      continue;
    }

    final editor = YamlEditor(content);
    for (final name in toRemove) {
      editor.remove(<Object>['dependency_overrides', name]);
    }
    file.writeAsStringSync(editor.toString());
    changed.add(repoDir);
  }

  return changed;
}
