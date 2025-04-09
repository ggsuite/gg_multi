// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import './commands/my_command.dart';
import './commands/add.dart';
import 'package:gg_log/gg_log.dart';

/// The command line interface for KidneyCore
class KidneyCore extends Command<dynamic> {
  /// Constructor
  KidneyCore({required this.ggLog}) {
    addSubcommand(MyCommand(ggLog: ggLog));
    addSubcommand(AddCommand(ggLog: ggLog));
  }

  /// The log function
  final GgLog ggLog;

  // ...........................................................................
  @override
  final name = 'kidneyCore';
  @override
  final description = 'Add your description here.';
}
