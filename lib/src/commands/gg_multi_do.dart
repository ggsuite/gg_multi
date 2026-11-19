// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_multi_core/gg_multi_core.dart' show GgRc;
import 'package:gg_multi_workspace/gg_multi_workspace.dart';
import 'package:gg_multi/src/commands/do/upgrade.dart';

import 'package:gg_multi_commit/gg_multi_commit.dart';
import 'package:gg_multi_do_publish/gg_multi_do_publish.dart';
import 'package:gg_multi_maintain/gg_multi_maintain.dart' show DoMaintain;

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
    // A breaking release brings the repos between it and the ticket repos
    // depending on it into the ticket — added by gg_multi_workspace's
    // `gg do add`, which the commands below do not depend on.
    const addBetween = addReposBetweenWithAddCommand;
    addSubcommand(DoCommitCommand(ggLog: ggLog, addReposBetween: addBetween));
    addSubcommand(DoPushCommand(ggLog: ggLog, addReposBetween: addBetween));
    addSubcommand(DoPublishCommand(ggLog: ggLog, addReposBetween: addBetween));
    addSubcommand(DoReviewCommand(ggLog: ggLog, addReposBetween: addBetween));
    addSubcommand(ExecCommand(ggLog: ggLog));
    // `gg do add` presets its flags from ~/.gg_rc.
    addSubcommand(AddCommand(ggLog: ggLog, readSettings: GgRc.load));
    addSubcommand(DoLocalizeCommand(ggLog: ggLog, addReposBetween: addBetween));
    addSubcommand(ImportCommand(ggLog: ggLog));
    addSubcommand(CodeCommand(ggLog: ggLog));
    addSubcommand(CreateCommand(ggLog: ggLog));
    addSubcommand(InitCommand(ggLog: ggLog));
    addSubcommand(RmCommand(ggLog: ggLog));
    addSubcommand(UpgradeCommand(ggLog: ggLog));
    addSubcommand(ListCommand(ggLog: ggLog));
    addSubcommand(DoMaintain(ggLog: ggLog));
  }
}
