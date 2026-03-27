// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import 'did/commit.dart';
import 'did/push.dart';

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
  String get description =>
      'Checks if you already committed or pushed for the current ticket.';

  /// Registers all did subcommands.
  void _initSubCommands() {
    addSubcommand(DidCommitCommand(ggLog: ggLog));
    addSubcommand(DidPushCommand(ggLog: ggLog));
  }
}
