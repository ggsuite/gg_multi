// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'list_repos.dart';
import 'list_organizations.dart';
import 'list_deps.dart';
import 'package:gg_log/gg_log.dart';

/// Command to list items from the master workspace.
/// If no subcommand is provided, it asks the user to choose.
class ListCommand extends Command<dynamic> {
  /// Constructor accepting a log function and optional input provider.
  ListCommand({
    required this.ggLog,
    this.inputProvider,
  }) {
    // Add subcommands for listing repos, organizations, and deps.
    addSubcommand(ListReposCommand(ggLog: ggLog));
    addSubcommand(ListOrganizationsCommand(ggLog: ggLog));
    addSubcommand(ListDepsCommand(ggLog: ggLog));
  }

  /// The log function.
  final GgLog ggLog;

  /// Function to get user input; defaults to stdin.readLineSync.
  final String? Function()? inputProvider;

  @override
  String get name => 'list';

  @override
  String get description => 'List repos, organizations, or dependencies.';

  @override
  Future<void> run() async {
    // If a subcommand is provided, command runner will call its run.
    if (argResults!.rest.isNotEmpty) {
      return;
    }
    // Interactive prompt.
    ggLog('Choose one: (r) repos, (o) organizations, (d) deps');
    final choice =
        inputProvider != null ? inputProvider!() : stdin.readLineSync();
    if (choice == null) {
      ggLog('No input provided.');
      return;
    }
    switch (choice.toLowerCase().trim()) {
      case 'r':
      case 'repos':
        await ListReposCommand(ggLog: ggLog).run();
        break;
      case 'o':
      case 'organizations':
        await ListOrganizationsCommand(ggLog: ggLog).run();
        break;
      case 'd':
      case 'deps':
        ListDepsCommand(ggLog: ggLog).run();
        break;
      default:
        ggLog('Invalid choice.');
    }
  }
}
