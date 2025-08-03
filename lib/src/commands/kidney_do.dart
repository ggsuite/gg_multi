// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import 'do/commit.dart';
import 'do/push.dart';
import 'do/publish.dart';
import 'do/review.dart';

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
  final description =
      'Perform actions like committing, pushing or '
      'reviewing across ticket repositories.';

  // ...........................................................................
  void _initSubCommands() {
    addSubcommand(DoCommitCommand(ggLog: ggLog));
    addSubcommand(DoPushCommand(ggLog: ggLog));
    addSubcommand(DoPublishCommand(ggLog: ggLog));
    addSubcommand(DoReviewCommand(ggLog: ggLog));
  }
}