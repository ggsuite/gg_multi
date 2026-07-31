// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import 'maintain/exec.dart';

/// Command that groups the maintenance tasks for the repositories of the
/// current ticket. Without a subcommand it prints the ones available.
class MaintainCommand extends Command<void> {
  /// Constructor accepting a log function.
  MaintainCommand({required this.ggLog}) {
    addSubcommand(
      DoExecuteCommand(ggLog: ggLog),
    );
  }

  /// Log function
  final GgLog ggLog;

  @override
  String get name => 'maintain';

  @override
  String get description => 'Maintain the repositories of the current ticket.';
}
