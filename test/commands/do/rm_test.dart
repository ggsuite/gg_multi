// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:gg_multi/src/backend/constants.dart';
import 'package:gg_multi/src/backend/ticket_json.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:gg_multi/src/commands/do/rm.dart';

import '../../rm_console_colors_helper.dart';

void main() {
  group('RemoveCommand', () {
    late Directory tempDir; // workspace root
    late Directory masterWs;
    late Directory ticketsRoot;
    final messages = <String>[];

    void ggLog(String message) {
      messages.add(rmConsoleColors(message));
    }

    CommandRunner<void> runnerAt(String rootPath) {
      return CommandRunner<void>('test', 'RemoveCommand Test')
        ..addCommand(RemoveCommand(ggLog: ggLog, rootPath: rootPath));
    }

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('remove_test_');
      masterWs = Directory(path.join(tempDir.path, ggMultiMasterFolder))
        ..createSync(recursive: true);
      ticketsRoot = Directory(path.join(tempDir.path, ggMultiTicketFolder))
        ..createSync(recursive: true);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    group('invoked from workspace root', () {
      test('deletes repo when only in master', () async {
        final repoDir = Directory(path.join(masterWs.path, 'project'))
          ..createSync(recursive: true);

        await runnerAt(tempDir.path).run(['rm', 'project']);

        expect(repoDir.existsSync(), isFalse);
        expect(
          messages,
          contains('Deleted repository project from master workspace.'),
        );
      });

      test(
          'refuses to delete master copy when the repo is also in a ticket — '
          'and lists the offending tickets', () async {
        // Repo in master + in ticket "alpha".
        final masterRepo = Directory(path.join(masterWs.path, 'shared'))
          ..createSync();
        final alphaDir = Directory(path.join(ticketsRoot.path, 'alpha'))
          ..createSync();
        Directory(path.join(alphaDir.path, 'shared')).createSync();

        await runnerAt(tempDir.path).run(['rm', 'shared']);

        expect(masterRepo.existsSync(), isTrue);
        expect(
          messages,
          contains('Repository shared is used by the following tickets:'),
        );
        expect(messages, contains(' - alpha'));
        expect(
          messages.any((m) => m.contains('Please remove it from those')),
          isTrue,
        );
      });

      test('lists multiple tickets that reference the repo', () async {
        Directory(path.join(masterWs.path, 'r1')).createSync();
        final t1 = Directory(path.join(ticketsRoot.path, 't1'))..createSync();
        Directory(path.join(t1.path, 'r1')).createSync();
        final t2 = Directory(path.join(ticketsRoot.path, 't2'))..createSync();
        Directory(path.join(t2.path, 'r1')).createSync();

        await runnerAt(tempDir.path).run(['rm', 'r1']);

        expect(messages, contains(' - t1'));
        expect(messages, contains(' - t2'));
      });

      test('reports not-found when repo lives nowhere', () async {
        await runnerAt(tempDir.path).run(['rm', 'ghost']);

        expect(
          messages,
          contains('Repository ghost not found in any workspace.'),
        );
      });
    });

    group('invoked from inside a ticket', () {
      test('deletes the repo from this ticket only', () async {
        // alpha-scoped rm must not touch master or sibling tickets.
        Directory(path.join(masterWs.path, 'shared')).createSync();
        final alphaDir = Directory(path.join(ticketsRoot.path, 'alpha'))
          ..createSync();
        final betaDir = Directory(path.join(ticketsRoot.path, 'beta'))
          ..createSync();
        final alphaRepo = Directory(path.join(alphaDir.path, 'shared'))
          ..createSync();
        final betaRepo = Directory(path.join(betaDir.path, 'shared'))
          ..createSync();

        await runnerAt(alphaDir.path).run(['rm', 'shared']);

        expect(alphaRepo.existsSync(), isFalse);
        expect(betaRepo.existsSync(), isTrue);
        expect(
          Directory(path.join(masterWs.path, 'shared')).existsSync(),
          isTrue,
          reason: 'master must never be touched from a ticket-scoped rm',
        );
        expect(
          messages,
          contains('Deleted repository shared from ticket alpha.'),
        );
      });

      test('reports when the repo is not part of this ticket', () async {
        final alphaDir = Directory(path.join(ticketsRoot.path, 'alpha'))
          ..createSync();

        await runnerAt(alphaDir.path).run(['rm', 'unrelated']);

        expect(
          messages,
          contains('Repository unrelated is not part of ticket alpha.'),
        );
      });
    });

    group('dependency chain inside a ticket', () {
      // Creates a dart package folder depending on [deps].
      Directory makePackage(
        Directory parent,
        String name, {
        List<String> deps = const [],
      }) {
        final dir = Directory(path.join(parent.path, name))
          ..createSync(recursive: true);
        final buffer = StringBuffer('name: $name\nversion: 1.0.0\n');
        if (deps.isNotEmpty) {
          buffer.writeln('dependencies:');
          for (final dep in deps) {
            buffer.writeln('  $dep: ^1.0.0');
          }
        }
        File(path.join(dir.path, 'pubspec.yaml'))
            .writeAsStringSync(buffer.toString());
        return dir;
      }

      // a -> b -> c
      late Directory alphaDir;
      late Directory a;
      late Directory b;
      late Directory c;

      setUp(() {
        alphaDir = Directory(path.join(ticketsRoot.path, 'alpha'))
          ..createSync();
        a = makePackage(alphaDir, 'a', deps: ['b']);
        b = makePackage(alphaDir, 'b', deps: ['c']);
        c = makePackage(alphaDir, 'c');
      });

      test('throws when the repo sits between two other ticket repos',
          () async {
        await expectLater(
          runnerAt(alphaDir.path).run(['rm', 'b']),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              allOf(contains('Cannot remove b'), contains('sits between')),
            ),
          ),
        );

        expect(b.existsSync(), isTrue, reason: 'b must not be deleted');
        expect(
          messages,
          contains('Repository b connects other repos of ticket alpha:'),
        );
        expect(messages, contains(' - a depends on b'));
        expect(messages, contains(' - b depends on c'));
        expect(messages, contains('Please remove a first.'));
      });

      test('deletes a repo nothing else depends on', () async {
        await runnerAt(alphaDir.path).run(['rm', 'a']);

        expect(a.existsSync(), isFalse);
        expect(
          messages,
          contains('Deleted repository a from ticket alpha.'),
        );
      });

      test('deletes a repo that has no dependencies in the ticket', () async {
        await runnerAt(alphaDir.path).run(['rm', 'c']);

        expect(c.existsSync(), isFalse);
        expect(
          messages,
          contains('Deleted repository c from ticket alpha.'),
        );
      });

      test('deletes the linking repo once its dependents are gone', () async {
        await runnerAt(alphaDir.path).run(['rm', 'a']);
        await runnerAt(alphaDir.path).run(['rm', 'b']);

        expect(b.existsSync(), isFalse);
        expect(
          messages,
          contains('Deleted repository b from ticket alpha.'),
        );
      });

      test('deletes a folder that is no package at all', () async {
        final plain = Directory(path.join(alphaDir.path, 'plain'))
          ..createSync();

        await runnerAt(alphaDir.path).run(['rm', 'plain']);

        expect(plain.existsSync(), isFalse);
      });
    });

    group('.ticket.json', () {
      late Directory alphaDir;
      late Directory a;
      late Directory b;

      // Writes a package folder plus its `.gg/.ticket.json` marker.
      Directory makePackage(Directory parent, String name) {
        final dir = Directory(path.join(parent.path, name))
          ..createSync(recursive: true);
        File(path.join(dir.path, 'pubspec.yaml'))
            .writeAsStringSync('name: $name\nversion: 1.0.0\n');
        return dir;
      }

      void writeMarker(Directory repoDir, List<String> repos) {
        Directory(path.join(repoDir.path, '.gg')).createSync(recursive: true);
        File(path.join(repoDir.path, '.gg', '.ticket.json')).writeAsStringSync(
          TicketJson(
            issueId: 'alpha',
            description: 'Some ticket',
            repositories: [
              for (final repo in repos) TicketRepo(name: repo, url: ''),
            ],
          ).toPrettyJson(),
        );
      }

      TicketJson markerOf(Directory repoDir) => TicketJson.fromJsonString(
            File(path.join(repoDir.path, '.gg', '.ticket.json'))
                .readAsStringSync(),
          );

      setUp(() {
        alphaDir = Directory(path.join(ticketsRoot.path, 'alpha'))
          ..createSync();
        writeRootTicket(
          alphaDir,
          issueId: 'alpha',
          description: 'Some ticket',
        );
        a = makePackage(alphaDir, 'a');
        b = makePackage(alphaDir, 'b');
        writeMarker(a, ['a', 'b']);
        writeMarker(b, ['a', 'b']);
      });

      test('drops the deleted repo from the marker of the remaining repos',
          () async {
        await runnerAt(alphaDir.path).run(['rm', 'a']);

        expect(a.existsSync(), isFalse);
        final marker = markerOf(b);
        expect(marker.repositories.map((r) => r.name), ['b']);
        expect(marker.issueId, 'alpha');
        expect(marker.description, 'Some ticket');
        expect(
          messages,
          contains('Removed a from .gg/.ticket.json of 1 repo(s).'),
        );
      });

      test('leaves the marker untouched when the removal is refused', () async {
        // b depends on a → removing a is fine, but make a link two repos.
        File(path.join(b.path, 'pubspec.yaml'))
            .writeAsStringSync('name: b\nversion: 1.0.0\n'
                'dependencies:\n  a: ^1.0.0\n');
        final c = makePackage(alphaDir, 'c');
        writeMarker(c, ['a', 'b', 'c']);
        File(path.join(a.path, 'pubspec.yaml'))
            .writeAsStringSync('name: a\nversion: 1.0.0\n'
                'dependencies:\n  c: ^1.0.0\n');

        await expectLater(
          runnerAt(alphaDir.path).run(['rm', 'a']),
          throwsA(isA<Exception>()),
        );

        expect(markerOf(b).repositories.map((r) => r.name), ['a', 'b']);
      });

      test('writes no marker into repos that have none', () async {
        Directory(path.join(b.path, '.gg')).deleteSync(recursive: true);

        await runnerAt(alphaDir.path).run(['rm', 'a']);

        expect(
          File(path.join(b.path, '.gg', '.ticket.json')).existsSync(),
          isFalse,
        );
        expect(
          messages.any((m) => m.contains('.gg/.ticket.json of')),
          isFalse,
        );
      });
    });

    group('org-prefixed folders', () {
      // Creates a repo folder carrying a pubspec name that differs from the
      // (org-prefixed) folder name.
      Directory makePrefixed(Directory parent, String folder, String pkg) {
        final dir = Directory(path.join(parent.path, folder))
          ..createSync(recursive: true);
        File(path.join(dir.path, 'pubspec.yaml'))
            .writeAsStringSync('name: $pkg\nversion: 1.0.0\n');
        return dir;
      }

      test('deletes a prefixed master folder addressed by package name',
          () async {
        final dir = makePrefixed(masterWs, 'ggsuite_foo', 'foo');

        await runnerAt(tempDir.path).run(['rm', 'foo']);

        expect(dir.existsSync(), isFalse);
        expect(
          messages,
          contains('Deleted repository foo from master workspace.'),
        );
      });

      test('finds a prefixed ticket copy when refusing master deletion',
          () async {
        makePrefixed(masterWs, 'ggsuite_foo', 'foo');
        final alphaDir = Directory(path.join(ticketsRoot.path, 'alpha'))
          ..createSync();
        makePrefixed(alphaDir, 'ggsuite_foo', 'foo');

        await runnerAt(tempDir.path).run(['rm', 'foo']);

        expect(
          messages,
          contains('Repository foo is used by the following tickets:'),
        );
        expect(messages, contains(' - alpha'));
      });

      test('deletes a prefixed folder from inside a ticket', () async {
        final alphaDir = Directory(path.join(ticketsRoot.path, 'alpha'))
          ..createSync();
        final repo = makePrefixed(alphaDir, 'ggsuite_foo', 'foo');

        await runnerAt(alphaDir.path).run(['rm', 'foo']);

        expect(repo.existsSync(), isFalse);
        expect(
          messages,
          contains('Deleted repository foo from ticket alpha.'),
        );
      });
    });

    test('throws UsageException when missing target argument', () async {
      expect(
        () => runnerAt(tempDir.path).run(['rm']),
        throwsA(isA<UsageException>()),
      );
    });
  });
}
