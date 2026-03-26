// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'commands/do/add.dart';
import 'commands/do/add_deps.dart';
import './commands/kidney_list.dart';
import 'commands/do/rm.dart';
import 'commands/do/init.dart';
import 'commands/do/create.dart';
import 'commands/do/code.dart';
import './commands/kidney_can.dart';
import './commands/kidney_do.dart';

/// The command line interface for KidneyCore
class KidneyCore extends Command<dynamic> {
  /// Constructor
  KidneyCore({required this.ggLog}) {
    addSubcommand(AddCommand(ggLog: ggLog));
    addSubcommand(ListCommand(ggLog: ggLog));
    addSubcommand(AddDepsCommand(ggLog: ggLog));
    addSubcommand(RemoveCommand(ggLog: ggLog));
    addSubcommand(InitCommand(ggLog: ggLog));
    addSubcommand(CreateCommand(ggLog: ggLog));
    addSubcommand(CodeCommand(ggLog: ggLog));
    addSubcommand(Can(ggLog: ggLog));
    addSubcommand(Do(ggLog: ggLog));
  }

  /// The log function
  final GgLog ggLog;

  @override
  final name = 'kidneyCore';
  @override
  final description = 'Add your description here.';
}
