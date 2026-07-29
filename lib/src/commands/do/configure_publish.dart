// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_one/gg_one.dart' as gg;
import 'package:gg_args/gg_args.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
// ignore: lines_longer_than_80_chars
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_localize_refs/gg_localize_refs.dart';
import 'package:gg_log/gg_log.dart';
import 'package:interact/interact.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';

import '../../backend/workspace_utils.dart';

/// Typedef for editing a merge message interactively.
typedef EditMessage = Future<String?> Function(String initialMessage);

/// Typedef for asking whether the ticket should be deleted after publishing.
typedef ConfirmDeleteTicket = bool Function(String ticketName);

/// Interactively builds the `.gg/.gg-publish.json` publish configuration for
/// the current ticket, asking for the version increment and merge message of
/// every repo up front plus a single `delete_ticket` choice. `do publish` runs
/// this automatically when no configuration is supplied, so all decisions are
/// made before the long (unattended) publish starts.
class DoConfigurePublishCommand extends DirCommand<void> {
  /// Constructor
  DoConfigurePublishCommand({
    required super.ggLog,
    super.name = 'configure-publish',
    super.description = 'Interactively create the .gg/.gg-publish.json publish '
        'configuration for the current ticket.',
    SortedProcessingList? sortedProcessingList,
    GetVersion? getVersionCommand,
    gg.VersionSelector? versionSelector,
    EditMessage? editMessage,
    ConfirmDeleteTicket? confirmDeleteTicket,
  })  : _sortedProcessingList =
            sortedProcessingList ?? SortedProcessingList(ggLog: ggLog),
        _getVersion = getVersionCommand ?? GetVersion(ggLog: ggLog),
        _versionSelector = versionSelector ?? gg.VersionSelector(),
        _editMessage = editMessage ?? _defaultEditMessage,
        _confirmDeleteTicket =
            confirmDeleteTicket ?? _defaultConfirmDeleteTicket {
    _addArgs();
  }

  /// Collects the repos of a ticket in dependency order.
  final SortedProcessingList _sortedProcessingList;

  /// Reads the current package version from a repo's manifest.
  final GetVersion _getVersion;

  /// Lets the user pick the version increment (patch/minor/major) per repo.
  final gg.VersionSelector _versionSelector;

  /// Opens an interactive editor for a repo's merge message.
  final EditMessage _editMessage;

  /// Asks the user whether the ticket should be deleted after publishing.
  final ConfirmDeleteTicket _confirmDeleteTicket;

  /// Returns the `.gg/.gg-publish.json` file for [ticketDir].
  static File configFileFor(Directory ticketDir) =>
      File(path.join(ticketDir.path, '.gg', '.gg-publish.json'));

  @override
  Future<void> get({
    required Directory directory,
    required GgLog ggLog,
  }) async {
    await configure(
      directory: directory,
      ggLog: ggLog,
      defaultMergeMessage: argResults?['message'] as String?,
    );
  }

  /// Builds the publish configuration for the ticket containing [directory],
  /// writes it to `<ticket>/.gg/.gg-publish.json` and returns it. Pass
  /// [deleteTicket] to skip the interactive delete-ticket prompt.
  ///
  /// [defaultMergeMessage] (typically from `-m`) is the default merge message:
  /// it pre-fills every repo's merge-message prompt and is the fallback when
  /// the prompt is left empty. It takes precedence over the ticket
  /// description; a generic `Publish <repo>` is used only when both are empty.
  Future<gg.PublishConfig> configure({
    required Directory directory,
    required GgLog ggLog,
    bool? deleteTicket,
    String? defaultMergeMessage,
  }) async {
    final String? ticketPath = WorkspaceUtils.detectTicketPath(
      path.absolute(directory.path),
    );
    if (ticketPath == null) {
      throw Exception('Not inside a ticket folder');
    }

    final ticketDir = Directory(ticketPath);
    final ticketName = path.basename(ticketDir.path);

    // Never clobber the progress of an unfinished publish — rewriting the
    // file would silently discard the per-repo status markers, so a later
    // `--continue` would re-publish repos that already released.
    final existingFile = configFileFor(ticketDir);
    if (existingFile.existsSync()) {
      final existing = gg.PublishConfig.load(
        configArg: existingFile.path,
        fallbackDir: ticketDir.path,
      );
      if (existing.repos.values.any((r) => r.status != null)) {
        throw Exception(
          'An unfinished publish left progress in ${existingFile.path}. '
          'Resume it with "gg do publish --continue", or discard it with '
          '"gg do publish --reconfigure".',
        );
      }
    }

    final ticketDescription = _readTicketDescription(ticketDir);

    // The merge-message seed: an explicit `-m` wins, otherwise the ticket
    // description. It pre-fills the per-repo prompt and is the fallback when
    // the user clears it (the config model rejects an empty merge message).
    final trimmedDefault = defaultMergeMessage?.trim();
    final seedMessage = (trimmedDefault != null && trimmedDefault.isNotEmpty)
        ? trimmedDefault
        : (ticketDescription ?? '');

    final subs = await _sortedProcessingList.get(
      directory: ticketDir,
      ggLog: ggLog,
    );
    if (subs.isEmpty) {
      ggLog(yellow('⚠️ No repos in this ticket'));
    }

    final repos = <String, gg.RepoOverride>{};
    for (final repo in subs) {
      final repoDir = repo.directory;
      final repoName = path.basename(repoDir.path);
      ggLog('${cyan(repoName)}:');

      final increment = await _versionSelector.selectIncrement(
        currentVersion: await _currentVersion(repoDir),
      );
      // A merge message must never be empty (the config model rejects it), so
      // fall back to the seed (-m or ticket description) and finally a generic
      // default.
      var message = (await _editMessage(seedMessage) ?? '').trim();
      if (message.isEmpty) {
        message = seedMessage;
      }
      if (message.isEmpty) {
        message = 'Publish $repoName';
      }

      repos[repoName] = gg.RepoOverride(
        versionIncrement: increment.name,
        mergeMessage: message,
      );
    }

    final delete = deleteTicket ?? _confirmDeleteTicket(ticketName);

    final config = gg.PublishConfig(deleteTicket: delete, repos: repos);
    final file = configFileFor(ticketDir);
    await config.save(file: file);
    ggLog(green('Wrote publish configuration to ${file.path}'));
    return config;
  }

  /// Reads the current package version of [repoDir], defaulting to 0.0.0 when
  /// it cannot be read or parsed (e.g. a repo without a version). Only the
  /// chosen increment is stored, so the baseline is used just for the preview.
  Future<Version> _currentVersion(Directory repoDir) async {
    try {
      final raw = await _getVersion.get(directory: repoDir);
      if (raw == null || raw.isEmpty) {
        return Version(0, 0, 0);
      }
      return Version.parse(raw);
    } catch (_) {
      return Version(0, 0, 0);
    }
  }

  /// Reads the optional description from the ticket configuration file, used as
  /// the default merge message.
  String? _readTicketDescription(Directory ticketDir) {
    final ticketFile = File(path.join(ticketDir.path, '.ticket'));
    if (!ticketFile.existsSync()) {
      return null;
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(ticketFile.readAsStringSync());
    } catch (_) {
      // A hand-edited / truncated .ticket must not crash the publish.
      return null;
    }
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final description = decoded['description']?.toString().trim();
    if (description == null || description.isEmpty) {
      return null;
    }

    return description;
  }

  /// Opens the default editor with [initialMessage] and returns the result.
  // coverage:ignore-start
  static Future<String?> _defaultEditMessage(String initialMessage) async {
    gg.throwWhenNotATerminal(
      'the merge message prompt',
      'pass -m <message> or provide a config file via --config',
    );
    return Input(
      prompt: 'Edit merge message',
      defaultValue: initialMessage,
      initialText: initialMessage,
    ).interact();
  }

  /// Asks the user whether the ticket repositories should be deleted.
  static bool _defaultConfirmDeleteTicket(String ticketName) {
    gg.throwWhenNotATerminal(
      'the delete-ticket prompt',
      'set delete_ticket in .gg/.gg-publish.json (or --config)',
    );
    final selected = Select(
      prompt: 'Delete ticket $ticketName and remove remote feature branches?',
      options: ['No', 'Yes'],
      initialIndex: 1,
    ).interact();
    return selected == 1;
  }
  // coverage:ignore-end

  /// Adds command line arguments.
  void _addArgs() {
    argParser.addOption(
      'message',
      abbr: 'm',
      help: 'Default merge message that pre-fills every repo\'s merge-message '
          'prompt (and is used when a prompt is left empty). Takes precedence '
          'over the ticket description.',
    );
  }
}

/// Mock for [DoConfigurePublishCommand]
class MockDoConfigurePublishCommand extends MockDirCommand<void>
    implements DoConfigurePublishCommand {}
