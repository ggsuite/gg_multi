// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'repo_folder_resolver.dart';

/// Relative path of the ticket marker inside a repository.
const String ticketJsonRelativePath = '.gg/.ticket.json';

/// The `.gitignore` line that re-includes the otherwise-ignored marker so it
/// is committed together with the feature branch.
const String ticketJsonGitignoreLine = '!.gg/.ticket.json';

/// One repository entry of a [TicketJson] marker.
class TicketRepo {
  /// Constructor.
  const TicketRepo({required this.name, required this.url});

  /// Parses a single repository entry from decoded JSON.
  factory TicketRepo.fromJson(Map<String, dynamic> json) => TicketRepo(
        name: json['name']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
      );

  /// The repository folder name (as used in the master/ticket workspace).
  final String name;

  /// The git remote URL the repository is cloned from.
  final String url;

  /// Serializes this entry to a JSON map.
  Map<String, String> toJson() => <String, String>{'name': name, 'url': url};
}

/// The content of a `.gg/.ticket.json` marker: the ticket id, its description
/// and the full list of repositories (with git URLs) that make up the ticket.
///
/// `gg do add` writes this marker into every repository of a ticket so the
/// whole ticket layout travels with each feature branch. `gg do checkout` can
/// then reproduce the ticket 1:1 from any single repository.
class TicketJson {
  /// Constructor.
  const TicketJson({
    required this.issueId,
    required this.description,
    required this.repositories,
  });

  /// Parses a [TicketJson] from a JSON string. Throws [FormatException] when
  /// the source is not a JSON object.
  factory TicketJson.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid .ticket.json: expected an object.');
    }
    final repos = decoded['repositories'];
    return TicketJson(
      issueId: decoded['issue_id']?.toString() ?? '',
      description: decoded['description']?.toString() ?? '',
      repositories: repos is List
          ? repos
              .whereType<Map<String, dynamic>>()
              .map(TicketRepo.fromJson)
              .toList()
          : const <TicketRepo>[],
    );
  }

  /// The ticket id (equals the ticket folder name and the branch name).
  final String issueId;

  /// The human-readable ticket description.
  final String description;

  /// All repositories that belong to the ticket.
  final List<TicketRepo> repositories;

  /// Renders a pretty (multi-line) JSON string for good readability, ending
  /// with a trailing newline.
  String toPrettyJson() {
    const encoder = JsonEncoder.withIndent('  ');
    final map = <String, Object?>{
      'issue_id': issueId,
      'description': description,
      'repositories': repositories.map((r) => r.toJson()).toList(),
    };
    return '${encoder.convert(map)}\n';
  }
}

/// Builds a [TicketJson] for the ticket at [ticketDir] from [repoDirs].
///
/// `issue_id` is the ticket folder name, `description` is read from the root
/// `.ticket` file, and each repository contributes its folder name and origin
/// remote URL.
TicketJson buildTicketJson({
  required Directory ticketDir,
  required Iterable<Directory> repoDirs,
}) {
  final repositories = <TicketRepo>[
    for (final dir in repoDirs)
      TicketRepo(
        name: path.basename(dir.path),
        url: RepoFolderResolver.remoteUrl(dir) ?? '',
      ),
  ];

  return TicketJson(
    issueId: path.basename(ticketDir.path),
    description: _readTicketDescription(ticketDir),
    repositories: repositories,
  );
}

/// Writes (overwriting) the `.gg/.ticket.json` marker into every repository in
/// [repoDirs] and whitelists it in each repo's `.gitignore`, so the marker is
/// committed with the feature branch. The same [ticket] is written everywhere.
void writeTicketJsonToRepos({
  required Iterable<Directory> repoDirs,
  required TicketJson ticket,
}) {
  final content = ticket.toPrettyJson();
  for (final repoDir in repoDirs) {
    final ggDir = Directory(path.join(repoDir.path, '.gg'));
    if (!ggDir.existsSync()) {
      ggDir.createSync(recursive: true);
    }
    File(path.join(ggDir.path, '.ticket.json')).writeAsStringSync(content);
    _whitelistInGitignore(repoDir);
  }
}

/// Reads the `description` field from the root `.ticket` file, or returns an
/// empty string when it is missing or malformed.
String _readTicketDescription(Directory ticketDir) {
  final file = File(path.join(ticketDir.path, '.ticket'));
  if (!file.existsSync()) {
    return '';
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map<String, dynamic>) {
      return decoded['description']?.toString() ?? '';
    }
  } catch (_) {
    // Fall through to an empty description on a malformed .ticket.
  }
  return '';
}

/// Appends [ticketJsonGitignoreLine] to the repo's `.gitignore` when present
/// and not already whitelisted. A no-op when there is no `.gitignore` (then
/// the marker is not ignored anyway).
void _whitelistInGitignore(Directory repoDir) {
  final gitignore = File(path.join(repoDir.path, '.gitignore'));
  if (!gitignore.existsSync()) {
    return;
  }
  final current = gitignore.readAsStringSync();
  final alreadyWhitelisted = const LineSplitter()
      .convert(current)
      .any((line) => line.trim() == ticketJsonGitignoreLine);
  if (alreadyWhitelisted) {
    return;
  }
  final needsNewline = current.isNotEmpty && !current.endsWith('\n');
  gitignore.writeAsStringSync(
    '$current${needsNewline ? '\n' : ''}$ticketJsonGitignoreLine\n',
  );
}
