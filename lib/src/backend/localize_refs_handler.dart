// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

/// A typedef for a process runner (same signature as in git_handler.dart).
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

/// Runs `gg_localize_refs localize-refs` inside [repoPath].
/// Throws if the command fails.
Future<void> localizeRefs(
  String repoPath, {
  ProcessRunner? processRunner,
}) async {
  final ProcessRunner run = processRunner ??
      (
        String exe,
        List<String> args, {
        String? workingDirectory,
      }) =>
          Process.run(
            exe,
            args,
            workingDirectory: workingDirectory,
            runInShell: true,
          );
  final result = await run(
    'gg_localize_refs',
    <String>['localize-refs'],
    workingDirectory: repoPath,
  );
  if (result.exitCode != 0) {
    throw Exception(
      'Failed to localize refs in $repoPath: ${result.stderr}',
    );
  }
}
