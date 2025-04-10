// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import '../../backend/list_backend.dart';

/// Command to list all organizations from repos in the master workspace.
class ListOrganizationsCommand extends Command<dynamic> {
  /// Constructor with optional workspace path.
  ListOrganizationsCommand({required this.ggLog, this.workspacePath});

  /// The log function.
  final GgLog ggLog;

  /// Optional workspace path override.
  final String? workspacePath;

  @override
  String get name => 'organizations';

  @override
  String get description =>
      'Lists all organizations from the repos in the master workspace.';

  @override
  Future<void> run() async {
    final String masterWorkspacePath = workspacePath ??
        '${Directory.current.path}${Platform.pathSeparator}kidney_ws_master';
    final repoInfos = await getAllRepoInfos(masterWorkspacePath);
    final orgSet = <String>{};
    for (final repo in repoInfos) {
      orgSet.add(repo.organization);
    }
    final orgs = orgSet.toList()..sort();
    if (orgs.isEmpty) {
      ggLog('No organizations found.');
    } else {
      for (final org in orgs) {
        if (org != 'unknown') {
          ggLog('$org -- https://github.com/orgs/$org/');
        } else {
          ggLog(org);
        }
      }
    }
  }
}
