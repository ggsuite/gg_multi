// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import './commands/my_command.dart';
import './commands/add.dart';
import './commands/add_deps.dart';
import './commands/list.dart';
import './commands/remove.dart';
import './commands/init.dart';
import 'package:gg_log/gg_log.dart';
import './commands/create.dart';
import './commands/code.dart';
import './commands/review.dart';

/// The command line interface for KidneyCore
class KidneyCore extends Command<dynamic> {
  /// Constructor
  KidneyCore({required this.ggLog}) {
    addSubcommand(MyCommand(ggLog: ggLog));
    addSubcommand(AddCommand(ggLog: ggLog));
    addSubcommand(ListCommand(ggLog: ggLog));
    addSubcommand(AddDepsCommand(ggLog: ggLog));
    addSubcommand(RemoveCommand(ggLog: ggLog));
    addSubcommand(InitCommand(ggLog: ggLog));
    addSubcommand(CreateCommand(ggLog: ggLog));
    addSubcommand(CodeCommand(ggLog: ggLog));
    addSubcommand(ReviewCommand(ggLog: ggLog));
  }

  /// The log function
  final GgLog ggLog;

  @override
  final name = 'kidneyCore';
  @override
  final description = 'Add your description here.';
}
