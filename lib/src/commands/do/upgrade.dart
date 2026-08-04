// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import 'upgrade/dependencies.dart';
import 'upgrade/master.dart';

/// Command to bring parts of the workspace in sync with their remotes.
class UpgradeCommand extends Command<void> {
  /// Constructor accepting a log function.
  UpgradeCommand({required this.ggLog}) {
    addSubcommand(
      UpdateMasterCommand(ggLog: ggLog),
    );
    addSubcommand(
      UpgradeDependenciesCommand(ggLog: ggLog),
    );
  }

  /// Log function
  final GgLog ggLog;

  @override
  String get name => 'upgrade';

  @override
  String get description => 'Upgrade parts of the workspace';
}
