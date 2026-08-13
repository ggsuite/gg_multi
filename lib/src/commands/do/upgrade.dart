// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import 'package:gg_multi_commit/gg_multi_commit.dart';
import 'package:gg_multi_workspace/gg_multi_workspace.dart';

/// Command to bring parts of the workspace in sync with their remotes.
class UpgradeCommand extends Command<void> {
  /// Constructor accepting a log function.
  UpgradeCommand({required this.ggLog}) {
    addSubcommand(
      UpdateOceanCommand(ggLog: ggLog),
    );
    addSubcommand(
      UpgradeDepsCommand(ggLog: ggLog),
    );
  }

  /// Log function
  final GgLog ggLog;

  @override
  String get name => 'upgrade';

  @override
  String get description => 'Upgrade parts of the workspace';
}
