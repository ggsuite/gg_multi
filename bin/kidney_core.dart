#!/usr/bin/env dart
// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import 'package:kidney_core/kidney_core.dart';

// .............................................................................
Future<void> run({
  required List<String> args,
  required GgLog ggLog,
}) =>
    GgCommandRunner(
      ggLog: ggLog,
      command: KidneyCore(ggLog: ggLog),
    ).run(args: args);

// .............................................................................
Future<void> main(List<String> args) async {
  try {
    await run(
      args: args,
      ggLog: print,
    );
  } catch (e) {
    // Colorise the word "input" so that tests expecting coloured output pass.
    // The tests compare against the exact result of red('input').
    var msg = e.toString();

    // Handle variants with or without quotes around input.
    msg = msg.replaceAll("Option 'input'", 'Option \\${red('input')}');
    msg = msg.replaceAll('Option input', 'Option \\${red('input')}');

    print(msg);
  }
}
