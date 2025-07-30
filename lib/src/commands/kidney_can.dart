// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:kidney_core/src/commands/can/commit.dart';
import 'package:kidney_core/src/commands/can/push.dart';

/// Commands to check if actions can be performed for the current ticket
class Can extends Command<void> {
  /// Constructor
  Can({required this.ggLog}) {
    _initSubCommands();
  }

  /// The log function
  final GgLog ggLog;

  @override
  String get name => 'can';

  @override
  String get description => 'Checks if you can commit '
      'or push for the current ticket.';

  // ...........................................................................
  void _initSubCommands() {
    addSubcommand(CanCommitCommand(ggLog: ggLog));
    addSubcommand(CanPushCommand(ggLog: ggLog));
  }
}
