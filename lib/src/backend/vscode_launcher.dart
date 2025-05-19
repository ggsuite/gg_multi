// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

/// Typedef for launching a process, mainly for testability.
typedef ProcessStarter = Future<void> Function(
  String executable,
  List<String> arguments, {
  bool runInShell,
});

/// Provides logic to open a directory in VS Code via the command line.
///
/// Example:
/// ```dart
/// final launcher = VSCodeLauncher();
/// await launcher.open(Directory('/some/path'));
/// ```
class VSCodeLauncher {
  /// Constructs a VSCodeLauncher with optional [processStarter] injection.
  /// The default starts VSCode using Process.start with runInShell: true.
  VSCodeLauncher({
    ProcessStarter? processStarter,
  }) : _starter = processStarter ?? _defaultStarter;

  final ProcessStarter _starter;

  /// Opens the given [directory] in VS Code via CLI.
  /// Throws any exception from process launching.
  Future<void> open(Directory directory) {
    return _starter('code', [directory.path], runInShell: true);
  }

  // Real implementation for launching VS Code.
  // coverage:ignore-start
  static Future<void> _defaultStarter(
    String executable,
    List<String> arguments, {
    bool runInShell = false,
  }) async {
    await Process.start(executable, arguments, runInShell: runInShell);
  }
  // coverage:ignore-end
}
