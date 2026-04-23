// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as path;

import '../../backend/workspace_utils.dart';

/// The line `gg` requires in `.gitattributes` to enable automatic EOL
/// conversion to LF.
const String gitattributesEolLine = '* text=auto eol=lf';

/// Ensures a `.gitattributes` file with the `gg`-required EOL rule exists in
/// every repository of the current ticket.
///
/// `gg` refuses to operate (e.g. `gg do commit`) when automatic EOL
/// conversion is not configured via `.gitattributes`. This command makes
/// sure the rule is present so subsequent `gg` calls succeed, regardless
/// of whether the repository is Dart or TypeScript based.
///
/// Behaviour per repository:
/// - If `.gitattributes` does not exist, it is created with the single
///   line [gitattributesEolLine].
/// - If `.gitattributes` exists but does not contain that line, the line
///   is appended.
/// - If the line is already present, the file is left untouched.
class DoInstallGitattributesCommand extends DirCommand<void> {
  /// Creates a new [DoInstallGitattributesCommand].
  DoInstallGitattributesCommand({
    required super.ggLog,
    super.name = 'install-gitattributes',
    super.description =
        'Ensures a .gitattributes file with "$gitattributesEolLine" '
            'exists in all repositories of the current ticket.',
    SortedProcessingList? sortedProcessingList,
  }) : _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog);

  /// Helper that returns the repositories in dependency-sorted order.
  final SortedProcessingList _sortedProcessingList;

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
  }) =>
      get(
        directory: directory,
        ggLog: ggLog,
      );

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    // Detect ticket folder ---------------------------------------------------
    final String? ticketPath = WorkspaceUtils.detectTicketPath(
      path.absolute(directory.path),
    );
    if (ticketPath == null) {
      ggLog(red('This command must be executed inside a ticket folder.'));
      throw Exception('Not inside a ticket folder');
    }

    final ticketDir = Directory(ticketPath);
    final ticketName = path.basename(ticketDir.path);

    // Collect all repositories in the ticket --------------------------------
    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (nodes.isEmpty) {
      ggLog(yellow('⚠️ No repositories found in ticket $ticketName.'));
      return;
    }

    // Ensure .gitattributes in each repository ------------------------------
    for (final node in nodes) {
      final repoDir = node.directory;
      final repoName = path.basename(repoDir.path);

      final attributesFile = File(
        path.join(repoDir.path, '.gitattributes'),
      );

      if (!attributesFile.existsSync()) {
        await attributesFile.writeAsString('$gitattributesEolLine\n');
        ggLog('Created .gitattributes in $repoName.');
        continue;
      }

      final existing = await attributesFile.readAsString();
      final hasLine = const LineSplitter()
          .convert(existing)
          .map((l) => l.trim())
          .contains(gitattributesEolLine);

      if (hasLine) {
        continue;
      }

      final needsLeadingNewline =
          existing.isNotEmpty && !existing.endsWith('\n');
      final prefix = needsLeadingNewline ? '\n' : '';
      await attributesFile.writeAsString(
        '$prefix$gitattributesEolLine\n',
        mode: FileMode.append,
      );
      ggLog('Updated .gitattributes in $repoName.');
    }

    ggLog(
      '✅ Ensured .gitattributes for all repositories in ticket '
      '$ticketName.',
    );
  }
}
