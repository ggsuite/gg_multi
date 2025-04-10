// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import '../backend/list_backend.dart';

/// Command to list all repositories in the master workspace.
class ListReposCommand extends Command<dynamic> {
  /// Constructor.
  ListReposCommand({required this.ggLog});

  /// The log function.
  final GgLog ggLog;

  @override
  String get name => 'repos';

  @override
  String get description =>
      'Lists all repos in the master workspace, sorted by name.';

  @override
  Future<void> run() async {
    final String masterWorkspacePath =
        '${Directory.current.path}${Platform.pathSeparator}kidney_ws_master';

    final repoInfos = await getAllRepoInfos(masterWorkspacePath);
    repoInfos.sort((a, b) => a.name.compareTo(b.name));
    if (repoInfos.isEmpty) {
      ggLog('No repositories found in the master workspace.');
    } else {
      for (final repo in repoInfos) {
        ggLog('${repo.name} ${repo.version} '
            '(${repo.language}) from ${repo.organization}');
      }
    }
  }
}
