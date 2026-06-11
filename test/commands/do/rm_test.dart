// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:gg_multi/src/backend/constants.dart';
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
