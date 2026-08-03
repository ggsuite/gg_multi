// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_log/gg_log.dart';
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:path/path.dart' as path;

import '../../backend/ticket_state.dart';
import '../../backend/workspace_utils.dart';

/// Command to check whether the current ticket state was reviewed.
///
/// `gg do review` writes the ticket hash under [stateKey] into
/// `<ticket>/.gg.json` once the review went through. This command compares
/// that hash against the current ticket state, so it answers "was *this*
/// state reviewed?" — a commit made after the review invalidates it.
class DidReviewCommand extends DirCommand<void> {
  /// Creates a new did review command.
  DidReviewCommand({
    required super.ggLog,
    super.name = 'review',
    super.description = 'Check if the current ticket state was reviewed',
    SortedProcessingList? sortedProcessingList,
    TicketState? ticketState,
  })  : _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog),
        _ticketState = ticketState ?? TicketState(ggLog: ggLog);

  /// State key used to persist the review success in `<ticketDir>/.gg.json`.
  static const String stateKey = 'didReview';

  /// Sorted processing list for repos.
  final SortedProcessingList _sortedProcessingList;

  /// Reads the review state from `<ticketDir>/.gg.json`.
  final TicketState _ticketState;

  @override
  Future<void> exec({
    required Directory directory,
    required GgLog ggLog,
  }) =>
      get(
        directory: directory,
        ggLog: ggLog,
      );

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    final String? ticketPath = WorkspaceUtils.detectTicketPath(
      path.absolute(directory.path),
    );
    if (ticketPath == null) {
      ggLog(cAction('Please run this command inside a ticket folder.'));
      throw Exception(cDetail('Not inside a ticket folder'));
    }

    final ticketDir = Directory(ticketPath);
    final nodes = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );

    if (nodes.isEmpty) {
      ggLog(cWarn('⚠️ No repos in this ticket'));
      return;
    }

    final wasReviewed = await GgStatusPrinter<bool>(
      message: 'The current state was reviewed',
      ggLog: ggLog,
    ).logTask(
      task: () => _ticketState.readSuccess(
        ticketDir: ticketDir,
        subs: nodes,
        key: stateKey,
      ),
      success: (wasReviewed) => wasReviewed,
    );

    if (!wasReviewed) {
      throw Exception(
        cAction('Please run ') + cCmd('gg do review') + cAction('.'),
      );
    }
  }
}

/// Mock for [DidReviewCommand]
class MockDidReviewCommand extends MockDirCommand<void>
    implements DidReviewCommand {}
