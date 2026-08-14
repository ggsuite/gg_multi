// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import 'package:gg_multi_commit/gg_multi_commit.dart';

/// Commands to check whether actions were already completed.
class Did extends Command<void> {
  /// Creates the did command.
  Did({required this.ggLog}) {
    _initSubCommands();
  }

  /// The log function.
  final GgLog ggLog;

  @override
  String get name => 'did';

  @override
  String get description => 'Check what you already did in the ticket';

  /// Registers all did subcommands.
  void _initSubCommands() {
    addSubcommand(DidCommitCommand(ggLog: ggLog));
    addSubcommand(DidPushCommand(ggLog: ggLog));
    addSubcommand(DidReviewCommand(ggLog: ggLog));
  }
}
