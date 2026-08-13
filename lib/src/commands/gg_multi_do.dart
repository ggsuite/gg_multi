// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_multi_workspace/gg_multi_workspace.dart';
import 'package:gg_multi/src/commands/do/upgrade.dart';

import 'package:gg_multi_commit/gg_multi_commit.dart';
import 'package:gg_multi_do_publish/gg_multi_do_publish.dart';

/// Command to perform actions such as committing
/// and pushing across ticket repositories.
class Do extends Command<void> {
  /// Constructor
  Do({required this.ggLog}) {
    _initSubCommands();
  }

  /// The log function
  final GgLog ggLog;

  /// The name of the command
  @override
  final name = 'do';

  /// The description of the command
  @override
  final description = 'Act on all repos of the current ticket';

  // ...........................................................................
  void _initSubCommands() {
    addSubcommand(DoCommitCommand(ggLog: ggLog));
    addSubcommand(DoPushCommand(ggLog: ggLog));
    addSubcommand(DoPublishCommand(ggLog: ggLog));
    addSubcommand(DoReviewCommand(ggLog: ggLog));
    addSubcommand(ExecCommand(ggLog: ggLog));
    addSubcommand(AddCommand(ggLog: ggLog));
    addSubcommand(ImportCommand(ggLog: ggLog));
    addSubcommand(CodeCommand(ggLog: ggLog));
    addSubcommand(CreateCommand(ggLog: ggLog));
    addSubcommand(InitCommand(ggLog: ggLog));
    addSubcommand(RmCommand(ggLog: ggLog));
    addSubcommand(UpgradeCommand(ggLog: ggLog));
    addSubcommand(ListCommand(ggLog: ggLog));
  }
}
