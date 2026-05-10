// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import './commands/gg_multi_can.dart';
import './commands/gg_multi_did.dart';
import './commands/gg_multi_do.dart';
import 'commands/ls.dart';

/// The command line interface for GgMulti
class GgMulti extends Command<dynamic> {
  /// Constructor
  GgMulti({required this.ggLog}) {
    addSubcommand(ListCommand(ggLog: ggLog));
    addSubcommand(Can(ggLog: ggLog));
    addSubcommand(Did(ggLog: ggLog));
    addSubcommand(Do(ggLog: ggLog));
  }

  /// The log function
  final GgLog ggLog;

  @override
  final name = 'ggMulti';
  @override
  final description = 'Add your description here.';
}
