// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_multi/src/backend/ticket_json.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ticket_json_test');
  });

  tearDown(() {
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  Directory makeDir(String name) =>
      Directory(path.join(tmp.path, name))..createSync(recursive: true);

  group('TicketRepo', () {
    test('fromJson reads name and url', () {
      final repo = TicketRepo.fromJson(<String, dynamic>{
        'name': 'gg_one',
        'url': 'git@example.com:org/gg_one.git',
      });
      expect(repo.name, 'gg_one');
      expect(repo.url, 'git@example.com:org/gg_one.git');
    });

    test('fromJson defaults to empty strings when fields are missing', () {
      final repo = TicketRepo.fromJson(const <String, dynamic>{});
      expect(repo.name, '');
      expect(repo.url, '');
    });

    test('toJson serializes name and url', () {
      const repo = TicketRepo(name: 'a', url: 'b');
      expect(repo.toJson(), <String, String>{'name': 'a', 'url': 'b'});
    });
  });

  group('TicketJson', () {
    test('fromJsonString parses a full marker, filtering bad repo entries', () {
      const source = '''
{
  "issue_id": "feat_x",
  "description": "desc",
  "repositories": [
    { "name": "gg_one", "url": "u1" },
    "not-an-object",
    { "name": "gg_multi", "url": "u2" }
  ]
}
''';
      final ticket = TicketJson.fromJsonString(source);
      expect(ticket.issueId, 'feat_x');
      expect(ticket.description, 'desc');
      expect(ticket.repositories.length, 2);
      expect(ticket.repositories.first.name, 'gg_one');
      expect(ticket.repositories.last.url, 'u2');
    });

    test('fromJsonString defaults fields and tolerates non-list repos', () {
      final ticket = TicketJson.fromJsonString('{"repositories": 42}');
      expect(ticket.issueId, '');
      expect(ticket.description, '');
      expect(ticket.repositories, isEmpty);
    });

    test('fromJsonString throws on a non-object source', () {
      expect(
        () => TicketJson.fromJsonString('[1, 2, 3]'),
        throwsA(isA<FormatException>()),
      );
    });

    test('toPrettyJson is multi-line, indented and newline-terminated', () {
      const ticket = TicketJson(
        issueId: 'feat_x',
        description: 'desc',
        repositories: [TicketRepo(name: 'gg_one', url: 'u1')],
      );
      final json = ticket.toPrettyJson();
      expect(json.endsWith('\n'), isTrue);
      expect(json.split('\n').length, greaterThan(3));
      expect(json, contains('  "issue_id": "feat_x"'));

      // Round-trips back to an equivalent marker.
      final parsed = TicketJson.fromJsonString(json);
      expect(parsed.issueId, 'feat_x');
      expect(parsed.repositories.single.url, 'u1');
    });
  });

  group('buildTicketJson', () {
    test('derives issue id, description and repo list with urls', () {
      final ticketDir = makeDir('my_ticket');
      File(path.join(ticketDir.path, '.ticket')).writeAsStringSync(
        '{"issue_id":"my_ticket","description":"the desc"}',
      );

      // One repo with a remote, one without.
      final withRemote = makeDir('repo_a');
      Directory(path.join(withRemote.path, '.git')).createSync();
      File(path.join(withRemote.path, '.git', 'config')).writeAsStringSync(
        '[remote "origin"]\n\turl = git@example.com:org/repo_a.git\n',
      );
      final withoutRemote = makeDir('repo_b');

      final ticket = buildTicketJson(
        ticketDir: ticketDir,
        repoDirs: [withRemote, withoutRemote],
      );

      expect(ticket.issueId, 'my_ticket');
      expect(ticket.description, 'the desc');
      expect(ticket.repositories.length, 2);
      expect(ticket.repositories[0].name, 'repo_a');
      expect(ticket.repositories[0].url, 'git@example.com:org/repo_a.git');
      expect(ticket.repositories[1].name, 'repo_b');
      expect(ticket.repositories[1].url, '');
    });

    test('uses an empty description when .ticket is absent', () {
      final ticketDir = makeDir('no_ticket_file');
      final ticket = buildTicketJson(
        ticketDir: ticketDir,
        repoDirs: const <Directory>[],
      );
      expect(ticket.description, '');
      expect(ticket.repositories, isEmpty);
    });

    test('uses an empty description when .ticket lacks the field', () {
      final ticketDir = makeDir('partial_ticket');
      File(path.join(ticketDir.path, '.ticket'))
          .writeAsStringSync('{"issue_id":"x"}');
      final ticket = buildTicketJson(
        ticketDir: ticketDir,
        repoDirs: const <Directory>[],
      );
      expect(ticket.description, '');
    });

    test('uses an empty description when .ticket is malformed', () {
      final ticketDir = makeDir('broken_ticket');
      File(path.join(ticketDir.path, '.ticket')).writeAsStringSync('not json');
      final ticket = buildTicketJson(
        ticketDir: ticketDir,
        repoDirs: const <Directory>[],
      );
      expect(ticket.description, '');
    });

    test('uses an empty description when .ticket is not an object', () {
      final ticketDir = makeDir('array_ticket');
      File(path.join(ticketDir.path, '.ticket')).writeAsStringSync('[1,2]');
      final ticket = buildTicketJson(
        ticketDir: ticketDir,
        repoDirs: const <Directory>[],
      );
      expect(ticket.description, '');
    });
  });

  group('writeTicketJsonToRepos', () {
    const ticket = TicketJson(
      issueId: 'feat_x',
      description: 'desc',
      repositories: [TicketRepo(name: 'r', url: 'u')],
    );

    File markerOf(Directory repo) =>
        File(path.join(repo.path, '.gg', '.ticket.json'));

    test('creates .gg and writes the pretty marker', () {
      final repo = makeDir('fresh');
      writeTicketJsonToRepos(repoDirs: [repo], ticket: ticket);
      expect(markerOf(repo).readAsStringSync(), ticket.toPrettyJson());
    });

    test('writes into a pre-existing .gg folder', () {
      final repo = makeDir('has_gg');
      Directory(path.join(repo.path, '.gg')).createSync();
      writeTicketJsonToRepos(repoDirs: [repo], ticket: ticket);
      expect(markerOf(repo).existsSync(), isTrue);
    });

    test('skips gitignore handling when there is no .gitignore', () {
      final repo = makeDir('no_gitignore');
      writeTicketJsonToRepos(repoDirs: [repo], ticket: ticket);
      expect(File(path.join(repo.path, '.gitignore')).existsSync(), isFalse);
    });

    test('appends the whitelist line (file ends with newline)', () {
      final repo = makeDir('gi_newline');
      final gi = File(path.join(repo.path, '.gitignore'))
        ..writeAsStringSync('.gg\n!.gg/.gg.json\n');
      writeTicketJsonToRepos(repoDirs: [repo], ticket: ticket);
      expect(
        gi.readAsStringSync(),
        '.gg\n!.gg/.gg.json\n$ticketJsonGitignoreLine\n',
      );
    });

    test('appends the whitelist line (file without trailing newline)', () {
      final repo = makeDir('gi_no_newline');
      final gi = File(path.join(repo.path, '.gitignore'))
        ..writeAsStringSync('.gg');
      writeTicketJsonToRepos(repoDirs: [repo], ticket: ticket);
      expect(gi.readAsStringSync(), '.gg\n$ticketJsonGitignoreLine\n');
    });

    test('writes the whitelist line into an empty .gitignore', () {
      final repo = makeDir('gi_empty');
      final gi = File(path.join(repo.path, '.gitignore'))
        ..writeAsStringSync('');
      writeTicketJsonToRepos(repoDirs: [repo], ticket: ticket);
      expect(gi.readAsStringSync(), '$ticketJsonGitignoreLine\n');
    });

    test('does not duplicate an existing whitelist line', () {
      final repo = makeDir('gi_present');
      final gi = File(path.join(repo.path, '.gitignore'))
        ..writeAsStringSync('.gg\n$ticketJsonGitignoreLine\n');
      writeTicketJsonToRepos(repoDirs: [repo], ticket: ticket);
      expect(gi.readAsStringSync(), '.gg\n$ticketJsonGitignoreLine\n');
    });
  });
}
