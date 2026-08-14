// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_multi_commit/gg_multi_commit.dart';
import 'package:gg_multi_do_publish/gg_multi_do_publish.dart';

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
  String get description => 'Perform checks on the ticket';

  // ...........................................................................
  void _initSubCommands() {
    addSubcommand(CanCommitCommand(ggLog: ggLog));
    addSubcommand(CanPushCommand(ggLog: ggLog));
    addSubcommand(CanPublishCommand(ggLog: ggLog));
    addSubcommand(CanReviewCommand(ggLog: ggLog));
  }
}
