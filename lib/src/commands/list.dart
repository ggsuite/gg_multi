// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'list/repos.dart';
import 'list/organizations.dart';
import 'list/deps.dart';
import 'package:gg_log/gg_log.dart';

/// Command to list items from the master workspace.
/// If no subcommand is provided, it asks the user to choose.
class ListCommand extends Command<dynamic> {
  /// Constructor accepting a log function, optional input provider,
  /// and optional workspace path.
  ListCommand({
    required this.ggLog,
    this.inputProvider,
    this.workspacePath,
  }) {
    // Add subcommands for listing repos, organizations, and deps.
    addSubcommand(ListReposCommand(ggLog: ggLog, workspacePath: workspacePath));
    addSubcommand(
      ListOrganizationsCommand(ggLog: ggLog, workspacePath: workspacePath),
    );
    addSubcommand(ListDepsCommand(ggLog: ggLog));
  }

  /// The log function.
  final GgLog ggLog;

  /// Function to get user input; defaults to stdin.readLineSync.
  final String? Function()? inputProvider;

  /// Optional workspace path override.
  final String? workspacePath;

  @override
  String get name => 'list';

  @override
  String get description => 'List repos, organizations, or dependencies.';

  @override
  Future<void> run() async {
    // Use null-aware operator to safeguard against null argResults.
    final rest = argResults?.rest ?? [];
    if (rest.isNotEmpty) {
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
        await ListReposCommand(ggLog: ggLog, workspacePath: workspacePath)
            .run();
        break;
      case 'o':
      case 'organizations':
        await ListOrganizationsCommand(
          ggLog: ggLog,
          workspacePath: workspacePath,
        ).run();
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
