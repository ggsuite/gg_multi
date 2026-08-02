// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import 'update/master.dart';

/// Command to bring parts of the workspace in sync with their remotes.
class UpdateCommand extends Command<void> {
  /// Constructor accepting a log function.
  UpdateCommand({required this.ggLog}) {
    addSubcommand(
      UpdateMasterCommand(ggLog: ggLog),
    );
  }

  /// Log function
  final GgLog ggLog;

  @override
  String get name => 'update';

  @override
  String get description => 'Update the workspace from its git platforms.';
}
