// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_multi/src/commands/do/add.dart';
import 'package:gg_multi/src/commands/do/checkout.dart';
import 'package:gg_multi/src/commands/do/claude.dart';
import 'package:gg_multi/src/commands/do/code.dart';
import 'package:gg_multi/src/commands/do/create.dart';
import 'package:gg_multi/src/commands/do/init.dart';
import 'package:gg_multi/src/commands/do/rm.dart';
import 'package:gg_multi/src/commands/do/upgrade.dart';

import 'do/commit.dart';
import 'do/push.dart';
import 'do/publish.dart';
import 'do/review.dart';
import 'do/exec.dart';
import 'do/ls.dart';

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
    addSubcommand(DoClaudeCommand(ggLog: ggLog));
    addSubcommand(AddCommand(ggLog: ggLog));
    addSubcommand(DoCheckoutCommand(ggLog: ggLog));
    addSubcommand(CodeCommand(ggLog: ggLog));
    addSubcommand(CreateCommand(ggLog: ggLog));
    addSubcommand(InitCommand(ggLog: ggLog));
    addSubcommand(RemoveCommand(ggLog: ggLog));
    addSubcommand(UpgradeCommand(ggLog: ggLog));
    addSubcommand(ListCommand(ggLog: ggLog));
  }
}
