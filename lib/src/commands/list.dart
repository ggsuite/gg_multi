// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'list/repos.dart';
import 'list/organizations.dart';
import 'list/deps.dart';
import 'package:gg_log/gg_log.dart';

/// Command to list items from the master workspace.
/// If no subcommand is provided, it asks the user to choose.
class ListCommand extends Command<dynamic> {
  /// Constructor accepting a log function
  /// and optional workspace path.
  ListCommand({
    required this.ggLog,
    String? workspacePath,
  }) {
    // Add subcommands for listing repos, organizations, and deps.
    addSubcommand(ListReposCommand(ggLog: ggLog, workspacePath: workspacePath));
    addSubcommand(
      ListOrganizationsCommand(ggLog: ggLog, workspacePath: workspacePath),
    );
    addSubcommand(ListDepsCommand(ggLog: ggLog));
  }

  /// The log function.
  final GgLog ggLog;

  @override
  String get name => 'list';

  @override
  String get description => 'List repos, organizations, or dependencies.';
}
