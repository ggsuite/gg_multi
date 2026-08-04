// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_multi/src/commands/do/push.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:gg_publish/gg_publish.dart' as gg_publish;
import 'package:gg_status_printer/gg_status_printer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:test/test.dart';

class MockGgDoPush extends Mock implements gg.DoPush {}

class MockGgCanCommit extends Mock implements gg.CanCommit {}

class MockMainBranch extends Mock implements gg_publish.MainBranch {}

class MockSortedProcessingList extends Mock implements SortedProcessingList {}

class FakeDirectory extends Fake implements Directory {}

class MockProcessRunner extends Mock {
  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });
}

/// All collaborators of a [DoPushCommand], each pre-stubbed to succeed so a
/// test only has to override the one it is about.
typedef PushTestBed = ({
  DoPushCommand command,
  MockProcessRunner git,
  MockGgDoPush ggDoPush,
  MockGgCanCommit ggCanCommit,
  MockMainBranch mainBranch,
});

void main() {
  late Directory tempDir;
  late Directory ticketsDir;
  late Directory ticketDir;
  final messages = <String>[];

  setUpAll(() {
    registerFallbackValue(FakeDirectory());
  });

  void ggLog(String msg) => messages.add(rmControls(msg));

  setUp(() {
    messages.clear();
    tempDir = Directory.systemTemp.createTempSync(
      'do_push_ticket_test_',
    );
    ticketsDir = Directory(path.join(tempDir.path, 'tickets'))..createSync();
    ticketDir = Directory(path.join(ticketsDir.path, 'TICKP'))..createSync();
    // Create repositories with pubspec.yaml so SortedProcessingList finds
    // them
    final aDir = Directory(path.join(ticketDir.path, 'A'))..createSync();
    File(path.join(aDir.path, 'pubspec.yaml')).writeAsStringSync('name: A');
    final bDir = Directory(path.join(ticketDir.path, 'B'))..createSync();
    File(path.join(bDir.path, 'pubspec.yaml')).writeAsStringSync('name: B');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// Stubs the git calls of a clean, already merged repo on branch [branch]:
  /// nothing uncommitted, merging main is a no-op and the feature branch does
  /// not exist on the remote yet.
  void stubBaseGit(MockProcessRunner m, {String branch = 'TICKP'}) {
    when(
      () => m(
        'git',
        ['status', '--porcelain'],
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
    when(
      () => m(
        'git',
        ['rev-parse', 'HEAD'],
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((_) async => ProcessResult(0, 0, 'samehead', ''));
    when(
      () => m(
        'git',
        ['fetch', 'origin', 'main'],
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
    when(
      () => m(
        'git',
        ['merge', 'origin/main'],
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((_) async => ProcessResult(0, 0, 'Already up to date.', ''));
    when(
      () => m(
        'git',
        ['diff', '--name-only', '--diff-filter=U'],
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
    when(
      () => m(
        'git',
        ['rev-parse', '--abbrev-ref', 'HEAD'],
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((_) async => ProcessResult(0, 0, branch, ''));
    when(
      () => m(
        'git',
        ['ls-remote', '--heads', 'origin', branch],
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

    // The merge is followed by a dependency resolution in every repo.
    when(
      () => m(
        'dart',
        ['pub', 'get'],
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
  }

  /// Stubs the probes `_integrateRemoteBranch` runs before it decides how to
  /// integrate the remote feature branch: the remote branch exists at
  /// [remoteHead], its fetch, and the two ancestry checks. By default the
  /// remote branch is neither already contained in the local history nor
  /// obsolete, so the regular `pull --rebase` runs.
  void stubIntegrateProbes(
    MockProcessRunner m, {
    String branch = 'TICKP',
    String remoteHead = 'abc123',
    bool remoteContainedInHead = false,
    bool mainContainedInHead = false,
  }) {
    when(
      () => m(
        'git',
        ['ls-remote', '--heads', 'origin', branch],
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer(
      (_) async => ProcessResult(0, 0, '$remoteHead\trefs/heads/$branch', ''),
    );
    when(
      () => m(
        'git',
        ['fetch', 'origin', branch],
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
    when(
      () => m(
        'git',
        ['merge-base', '--is-ancestor', remoteHead, 'HEAD'],
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer(
      (_) async => ProcessResult(0, remoteContainedInHead ? 0 : 1, '', ''),
    );
    when(
      () => m(
        'git',
        ['merge-base', '--is-ancestor', 'origin/main', 'HEAD'],
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer(
      (_) async => ProcessResult(0, mainContainedInHead ? 0 : 1, '', ''),
    );
  }

  /// Stubs the history inspection of `_remoteBranchIsObsolete`: [cherry] is
  /// the `git cherry` output and [extraCommits] the `<hash>\t<subject>` lines
  /// the remote branch holds on top of `HEAD`.
  void stubObsoleteAnalysis(
    MockProcessRunner m, {
    String remoteHead = 'abc123',
    String cherry = '',
    String extraCommits = '',
  }) {
    when(
      () => m(
        'git',
        ['cherry', 'origin/main', remoteHead],
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((_) async => ProcessResult(0, 0, cherry, ''));
    when(
      () => m(
        'git',
        ['log', '--format=%H%x09%s', remoteHead, '--not', 'HEAD'],
        workingDirectory: any(named: 'workingDirectory'),
      ),
    ).thenAnswer((_) async => ProcessResult(0, 0, extraCommits, ''));
  }

  /// Builds a [DoPushCommand] whose collaborators all succeed for the
  /// [repos]: the ticket was reviewed, the trees are clean, merging main is a
  /// no-op and pushing works.
  PushTestBed makeCommand({List<String> repos = const ['A', 'B']}) {
    final git = MockProcessRunner();
    stubBaseGit(git);

    final ggDoPush = MockGgDoPush();
    when(
      () => ggDoPush.exec(
        directory: any(named: 'directory'),
        ggLog: any(named: 'ggLog'),
        force: any(named: 'force'),
      ),
    ).thenAnswer((_) async {});

    final ggCanCommit = MockGgCanCommit();
    when(
      () => ggCanCommit.exec(
        directory: any(named: 'directory'),
        ggLog: any(named: 'ggLog'),
        saveState: any(named: 'saveState'),
      ),
    ).thenAnswer((_) async {});

    final mainBranch = MockMainBranch();
    when(
      () => mainBranch.get(
        directory: any(named: 'directory'),
        ggLog: any(named: 'ggLog'),
      ),
    ).thenAnswer((_) async => 'main');

    final sortedProcessingList = MockSortedProcessingList();
    when(
      () => sortedProcessingList.get(
        directory: any(named: 'directory'),
        ggLog: any(named: 'ggLog'),
      ),
    ).thenAnswer(
      (_) async => [
        for (final repo in repos)
          Node(
            name: repo,
            directory: Directory(path.join(ticketDir.path, repo)),
            manifest: DartPackageManifest(pubspec: Pubspec(repo)),
          ),
      ],
    );

    final command = DoPushCommand(
      ggLog: ggLog,
      ggDoPush: ggDoPush,
      ggCanCommit: ggCanCommit,
      sortedProcessingList: sortedProcessingList,
      processRunner: git.call,
      mainBranch: mainBranch,
    );

    return (
      command: command,
      git: git,
      ggDoPush: ggDoPush,
      ggCanCommit: ggCanCommit,
      mainBranch: mainBranch,
    );
  }

  CommandRunner<void> runner(DoPushCommand command) =>
      CommandRunner<void>('test', 'do push ticket')..addCommand(command);

  group('DoPushCommand (ticket-wide)', () {
    test('fails outside any ticket folder', () async {
      await expectLater(
        () async => await runner(DoPushCommand(ggLog: ggLog))
            .run(['push', '--input', tempDir.path]),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'message',
            'Exception: Not inside a ticket folder',
          ),
        ),
      );
      expect(
        messages,
        contains('Please run this command inside a ticket folder.'),
      );
    });

    test('logs when there are no repositories', () async {
      final emptyTicket = Directory(path.join(ticketsDir.path, 'EMPTY'))
        ..createSync();
      await runner(DoPushCommand(ggLog: ggLog))
          .run(['push', '--input', emptyTicket.path]);
      expect(
        messages,
        contains('⚠️ No repos in this ticket'),
      );
    });

    test('pushes all repos successfully (verbose)', () async {
      final bed = makeCommand();

      await runner(bed.command).run([
        'push',
        '--input',
        ticketDir.path,
        '--verbose',
      ]);

      expect(
        messages.where((m) => m.contains('Uncommitted changes?')),
        isNotEmpty,
      );
      expect(
        messages.where(
          (m) => m.contains('Merging main into the feature branches'),
        ),
        isNotEmpty,
      );
      expect(
        messages,
        containsAllInOrder(<Matcher>[
          equals('\nPushing ...'),
          equals(' - A'),
          equals(' - B'),
          equals('\nA'),
          equals('✓ Pushed'),
          equals('\nB'),
          equals('✓ Pushed'),
          equals('\n✓ All repos pushed\n'),
        ]),
      );
    });

    test('reports the repos that failed', () async {
      final bed = makeCommand();

      when(
        () => bed.ggDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((invocation) async {
        final repoDir = invocation.namedArguments[#directory] as Directory;
        if (path.basename(repoDir.path) == 'B') {
          throw Exception('Failed to push B');
        }
      });

      await expectLater(
        () async => await runner(bed.command).run([
          'push',
          '--input',
          ticketDir.path,
          '--verbose',
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'message',
            'Exception: Failed to push.',
          ),
        ),
      );
      expect(
        messages,
        containsAllInOrder(<Matcher>[
          equals('\nA'),
          equals('✓ Pushed'),
          equals('\nB'),
          // The reason belongs under the repo it happened in — once.
          equals('✗ Failed to push\nFailed to push B'),
          equals('\nPlease fix the issues above.\n'),
        ]),
      );
    });

    test('uses quiet taskLog when verbose is false', () async {
      final localMessages = <String>[];
      void localLog(String msg) => localMessages.add(rmControls(msg));

      final bed = makeCommand();

      // Rebuild with the local log so the assertion sees every message.
      final command = DoPushCommand(
        ggLog: localLog,
        ggDoPush: bed.ggDoPush,
        ggCanCommit: bed.ggCanCommit,
        sortedProcessingList: _sortedList(ticketDir, const ['A', 'B']),
        processRunner: bed.git.call,
        mainBranch: bed.mainBranch,
      );

      await command.get(
        directory: ticketDir,
        ggLog: localLog,
        force: false,
        verbose: false,
      );

      // Without --verbose the per-repo output of `gg do push` is dropped,
      // but the headers and the summary stay.
      expect(
        localMessages,
        containsAllInOrder(<Matcher>[
          equals('\nPushing ...'),
          equals(' - A'),
          equals(' - B'),
          equals('\nA'),
          equals('✓ Pushed'),
          equals('\nB'),
          equals('✓ Pushed'),
          equals('\n✓ All repos pushed\n'),
        ]),
      );
      // The merge details are verbose-only.
      expect(
        localMessages.where((m) => m == '✓ Merged main into A'),
        isEmpty,
      );
    });

    test('forwards --force to gg do push', () async {
      final bed = makeCommand(repos: ['A']);

      await runner(bed.command).run([
        'push',
        '--input',
        ticketDir.path,
        '--force',
      ]);

      verify(
        () => bed.ggDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: true,
        ),
      ).called(1);
    });

    test('aborts before merging when a repo has uncommitted changes', () async {
      final bed = makeCommand();

      when(
        () => bed.git(
          'git',
          ['status', '--porcelain'],
          workingDirectory: path.join(ticketDir.path, 'A'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, ' M lib/a.dart', ''));

      await expectLater(
        () async => await runner(bed.command).run([
          'push',
          '--input',
          ticketDir.path,
          '--verbose',
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'message',
            allOf(
              contains('Uncommitted changes in A'),
              contains('Please run gg do commit first.'),
            ),
          ),
        ),
      );

      expect(messages, contains('Uncommitted changes in'));
      expect(messages, contains(' - A'));
      verifyNever(
        () => bed.git(
          'git',
          ['merge', 'origin/main'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
      verifyNever(
        () => bed.ggDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
        ),
      );
    });
  });

  group('DoPushCommand dependency resolution', () {
    test('runs "dart pub get" in every repo after the merge', () async {
      final bed = makeCommand();

      await runner(bed.command).run([
        'push',
        '--input',
        ticketDir.path,
        '--verbose',
      ]);

      verifyInOrder([
        () => bed.git(
              'git',
              ['merge', 'origin/main'],
              workingDirectory: path.join(ticketDir.path, 'A'),
            ),
        () => bed.git(
              'dart',
              ['pub', 'get'],
              workingDirectory: path.join(ticketDir.path, 'A'),
            ),
        () => bed.git(
              'dart',
              ['pub', 'get'],
              workingDirectory: path.join(ticketDir.path, 'B'),
            ),
      ]);

      expect(messages, contains('✓ Resolved dependencies of A'));
    });

    test('runs "flutter pub get" in a Flutter repo', () async {
      File(path.join(ticketDir.path, 'A', 'pubspec.yaml'))
          .writeAsStringSync('name: A\nflutter:\n  uses-material-design: true');
      final bed = makeCommand(repos: ['A']);
      when(
        () => bed.git(
          'flutter',
          ['pub', 'get'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      await runner(bed.command).run(['push', '--input', ticketDir.path]);

      verify(
        () => bed.git(
          'flutter',
          ['pub', 'get'],
          workingDirectory: path.join(ticketDir.path, 'A'),
        ),
      ).called(1);
    });

    test('skips a repo without a pubspec.yaml', () async {
      final bed = makeCommand(repos: ['A']);
      File(path.join(ticketDir.path, 'A', 'pubspec.yaml')).deleteSync();

      await runner(bed.command).run(['push', '--input', ticketDir.path]);

      verifyNever(
        () => bed.git(
          'dart',
          ['pub', 'get'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
    });

    test('fails the push when "dart pub get" fails', () async {
      final bed = makeCommand(repos: ['A']);
      when(
        () => bed.git(
          'dart',
          ['pub', 'get'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(0, 1, '', 'version solving failed'),
      );

      await expectLater(
        () async => await runner(bed.command).run([
          'push',
          '--input',
          ticketDir.path,
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'message',
            contains('"dart pub get" failed in A: version solving failed'),
          ),
        ),
      );
    });

    test(
        'reports stdout when the failing "dart pub get" stays silent on '
        'stderr', () async {
      final bed = makeCommand(repos: ['A']);
      when(
        () => bed.git(
          'dart',
          ['pub', 'get'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 1, 'no pubspec', ''));

      await expectLater(
        () async => await runner(bed.command).run([
          'push',
          '--input',
          ticketDir.path,
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'message',
            contains('"dart pub get" failed in A: no pubspec'),
          ),
        ),
      );
    });
  });

  group('DoPushCommand merge phase', () {
    test('fetches and merges main into every repo before pushing', () async {
      final bed = makeCommand();

      await runner(bed.command).run([
        'push',
        '--input',
        ticketDir.path,
        '--verbose',
      ]);

      verifyInOrder([
        () => bed.git(
              'git',
              ['fetch', 'origin', 'main'],
              workingDirectory: path.join(ticketDir.path, 'A'),
            ),
        () => bed.git(
              'git',
              ['merge', 'origin/main'],
              workingDirectory: path.join(ticketDir.path, 'A'),
            ),
        () => bed.git(
              'git',
              ['fetch', 'origin', 'main'],
              workingDirectory: path.join(ticketDir.path, 'B'),
            ),
        () => bed.git(
              'git',
              ['merge', 'origin/main'],
              workingDirectory: path.join(ticketDir.path, 'B'),
            ),
        // The pushes only start after every repo merged cleanly.
        () => bed.ggDoPush.exec(
              directory: any(named: 'directory'),
              ggLog: any(named: 'ggLog'),
              force: any(named: 'force'),
            ),
      ]);

      expect(messages, contains('✓ Merged main into A'));
      expect(messages, contains('✓ Merged main into B'));
    });

    test('merges origin/master when the repo has no main branch', () async {
      final bed = makeCommand(repos: ['A']);

      when(
        () => bed.mainBranch.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => 'master');
      when(
        () => bed.git(
          'git',
          ['fetch', 'origin', 'master'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => bed.git(
          'git',
          ['merge', 'origin/master'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      await runner(bed.command).run([
        'push',
        '--input',
        ticketDir.path,
        '--verbose',
      ]);

      verify(
        () => bed.git(
          'git',
          ['merge', 'origin/master'],
          workingDirectory: path.join(ticketDir.path, 'A'),
        ),
      ).called(1);
      expect(messages, contains('✓ Merged master into A'));
    });

    test('skips the merge for a repo without main or master', () async {
      final bed = makeCommand(repos: ['A']);

      when(
        () => bed.mainBranch.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenThrow(
        ArgumentError('Could not determine the main branch.'),
      );

      await runner(bed.command).run([
        'push',
        '--input',
        ticketDir.path,
        '--verbose',
      ]);

      verifyNever(
        () => bed.git(
          'git',
          ['merge', 'origin/main'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
      expect(
        messages,
        contains('✓ A has no main branch — nothing to merge'),
      );
      expect(messages, contains('\n✓ All repos pushed\n'));
    });

    test('asks the user to resolve merge conflicts and keeps the merge',
        () async {
      final bed = makeCommand(repos: ['A']);

      when(
        () => bed.git(
          'git',
          ['merge', 'origin/main'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(
          1,
          1,
          'CONFLICT (content): Merge conflict in CHANGELOG.md',
          '',
        ),
      );
      when(
        () => bed.git(
          'git',
          ['diff', '--name-only', '--diff-filter=U'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(0, 0, 'CHANGELOG.md\npubspec.yaml\n', ''),
      );

      await expectLater(
        () async => await runner(bed.command).run([
          'push',
          '--input',
          ticketDir.path,
          '--verbose',
        ]),
        throwsA(
          isA<MergeConflictException>().having(
            (e) => rmControls(e.toString()),
            'message',
            allOf(
              contains('Merging origin/main into A produced conflicts:'),
              contains(' - A/CHANGELOG.md'),
              contains(' - A/pubspec.yaml'),
              contains(
                'Please resolve the conflicts. Then execute: '
                'gg do commit -m"Merge main" --no-log',
              ),
            ),
          ),
        ),
      );

      // The merge conflict must survive in the working tree: no abort, no
      // reset, no push.
      verifyNever(
        () => bed.git(
          'git',
          ['merge', '--abort'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
      verifyNever(
        () => bed.ggDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
        ),
      );
    });

    test('fails and cleans up when the merge fails without conflicts',
        () async {
      final bed = makeCommand(repos: ['A']);

      when(
        () => bed.git(
          'git',
          ['merge', 'origin/main'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(1, 1, '', 'fatal: not something to merge'),
      );
      when(
        () => bed.git(
          'git',
          ['merge', '--abort'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 1, '', ''));

      await expectLater(
        () async => await runner(bed.command).run([
          'push',
          '--input',
          ticketDir.path,
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'message',
            contains('Failed to merge main.'),
          ),
        ),
      );

      expect(
        messages.any(
          (m) => m.contains(
            '✗ Failed to merge main into A',
          ),
        ),
        isTrue,
      );
      expect(
        messages.any((m) => m.contains('fatal: not something to merge')),
        isTrue,
      );
      verify(
        () => bed.git(
          'git',
          ['merge', '--abort'],
          workingDirectory: path.join(ticketDir.path, 'A'),
        ),
      ).called(1);
      verifyNever(
        () => bed.ggDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
        ),
      );
    });

    test('verifies the repo with can commit when the merge moved HEAD',
        () async {
      final bed = makeCommand(repos: ['A']);

      var headCalls = 0;
      when(
        () => bed.git(
          'git',
          ['rev-parse', 'HEAD'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(0, 0, headCalls++ == 0 ? 'h1' : 'h2', ''),
      );

      await runner(bed.command).run([
        'push',
        '--input',
        ticketDir.path,
        '--verbose',
      ]);

      verify(
        () => bed.ggCanCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          saveState: false,
        ),
      ).called(1);
      expect(messages, contains('✓ Verified A after merging main'));
    });

    test(
        'resets to the pre-merge commit when the merged state does not pass '
        'can commit', () async {
      final bed = makeCommand(repos: ['A']);

      var headCalls = 0;
      when(
        () => bed.git(
          'git',
          ['rev-parse', 'HEAD'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(0, 0, headCalls++ == 0 ? 'h1' : 'h2', ''),
      );
      when(
        () => bed.ggCanCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          saveState: any(named: 'saveState'),
        ),
      ).thenThrow(Exception('Duplicate mapping key'));
      when(
        () => bed.git(
          'git',
          ['reset', '--hard', 'h1'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      await expectLater(
        () async => await runner(bed.command).run([
          'push',
          '--input',
          ticketDir.path,
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'message',
            contains('Merged state does not pass can commit.'),
          ),
        ),
      );

      // The repo was reset to before the merge.
      verify(
        () => bed.git(
          'git',
          ['reset', '--hard', 'h1'],
          workingDirectory: path.join(ticketDir.path, 'A'),
        ),
      ).called(1);
      expect(
        messages.any(
          (m) => m.contains('✗ Merging main into A broke "gg can commit"'),
        ),
        isTrue,
      );
      expect(
        messages.any((m) => m.contains('The repo was reset to')),
        isTrue,
      );
      verifyNever(
        () => bed.ggDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
        ),
      );
    });
  });

  group('DoPushCommand remote-branch integration', () {
    test('integrates the remote feature branch before pushing when it exists',
        () async {
      final bed = makeCommand(repos: ['A']);
      stubIntegrateProbes(bed.git);
      when(
        () => bed.git(
          'git',
          ['pull', '--rebase', 'origin', 'TICKP'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

      await runner(bed.command).run([
        'push',
        '--input',
        ticketDir.path,
        '--verbose',
      ]);

      verifyInOrder([
        () => bed.git(
              'git',
              ['pull', '--rebase', 'origin', 'TICKP'],
              workingDirectory: path.join(ticketDir.path, 'A'),
            ),
        () => bed.ggDoPush.exec(
              directory: any(named: 'directory'),
              ggLog: any(named: 'ggLog'),
              force: any(named: 'force'),
            ),
      ]);
      expect(
        messages,
        contains('✓ Integrated origin/TICKP into A before push'),
      );
    });

    test(
        'skips the integration when the remote branch is already contained '
        'in the local history', () async {
      final bed = makeCommand(repos: ['A']);
      stubIntegrateProbes(bed.git, remoteContainedInHead: true);

      await runner(bed.command).run([
        'push',
        '--input',
        ticketDir.path,
        '--verbose',
      ]);

      verifyNever(
        () => bed.git(
          'git',
          ['pull', '--rebase', 'origin', 'TICKP'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
      expect(messages, contains('\n✓ All repos pushed\n'));
    });

    test('skips the integration when the branch is not on the remote yet',
        () async {
      final bed = makeCommand(repos: ['A']);
      // Base stub: ls-remote returns nothing.

      await runner(bed.command).run([
        'push',
        '--input',
        ticketDir.path,
      ]);

      verifyNever(
        () => bed.git(
          'git',
          ['fetch', 'origin', 'TICKP'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
      verifyNever(
        () => bed.git(
          'git',
          ['pull', '--rebase', 'origin', 'TICKP'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
      expect(messages, contains('\n✓ All repos pushed\n'));
    });

    test('skips the integration in detached HEAD state', () async {
      final bed = makeCommand(repos: ['A']);
      when(
        () => bed.git(
          'git',
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'HEAD', ''));

      await runner(bed.command).run([
        'push',
        '--input',
        ticketDir.path,
      ]);

      verifyNever(
        () => bed.git(
          'git',
          ['ls-remote', '--heads', 'origin', 'HEAD'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
      expect(messages, contains('\n✓ All repos pushed\n'));
    });

    test(
        'replaces an obsolete remote branch — one whose commits are on main '
        'or gg bookkeeping — instead of rebasing onto it', () async {
      final bed = makeCommand(repos: ['A']);
      stubIntegrateProbes(bed.git, mainContainedInHead: true);
      stubObsoleteAnalysis(
        bed.git,
        cherry: '- onmain',
        extraCommits: 'onmain\tFix the rm bug\n'
            'keeper\t#gg: changed references to git',
      );
      when(
        () => bed.git(
          'git',
          [
            'push',
            '--force-with-lease=TICKP:abc123',
            '--set-upstream',
            'origin',
            'HEAD:refs/heads/TICKP',
          ],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      await runner(bed.command).run([
        'push',
        '--input',
        ticketDir.path,
        '--verbose',
      ]);

      verify(
        () => bed.git(
          'git',
          [
            'push',
            '--force-with-lease=TICKP:abc123',
            '--set-upstream',
            'origin',
            'HEAD:refs/heads/TICKP',
          ],
          workingDirectory: path.join(ticketDir.path, 'A'),
        ),
      ).called(1);
      verifyNever(
        () => bed.git(
          'git',
          ['pull', '--rebase', 'origin', 'TICKP'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
      expect(
        messages.any(
          (m) => m.contains(
            'origin/TICKP of A was a leftover of an already merged ticket',
          ),
        ),
        isTrue,
      );
    });

    test(
        'rebases when the remote branch still holds a commit that is '
        'neither on main nor gg bookkeeping', () async {
      final bed = makeCommand(repos: ['A']);
      stubIntegrateProbes(bed.git, mainContainedInHead: true);
      stubObsoleteAnalysis(
        bed.git,
        cherry: '+ work',
        extraCommits: 'work\tSomebody else pushed this',
      );
      when(
        () => bed.git(
          'git',
          ['pull', '--rebase', 'origin', 'TICKP'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

      await runner(bed.command).run([
        'push',
        '--input',
        ticketDir.path,
        '--verbose',
      ]);

      verify(
        () => bed.git(
          'git',
          ['pull', '--rebase', 'origin', 'TICKP'],
          workingDirectory: path.join(ticketDir.path, 'A'),
        ),
      ).called(1);
    });

    test('rebases when the remote branch adds no commit to the local history',
        () async {
      final bed = makeCommand(repos: ['A']);
      stubIntegrateProbes(bed.git, mainContainedInHead: true);
      stubObsoleteAnalysis(bed.git, extraCommits: '');
      when(
        () => bed.git(
          'git',
          ['pull', '--rebase', 'origin', 'TICKP'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

      await runner(bed.command).run([
        'push',
        '--input',
        ticketDir.path,
      ]);

      verify(
        () => bed.git(
          'git',
          ['pull', '--rebase', 'origin', 'TICKP'],
          workingDirectory: path.join(ticketDir.path, 'A'),
        ),
      ).called(1);
    });

    test(
        'fails with a manual-deletion hint when replacing the obsolete '
        'remote branch is rejected', () async {
      final bed = makeCommand(repos: ['A']);
      stubIntegrateProbes(bed.git, mainContainedInHead: true);
      stubObsoleteAnalysis(
        bed.git,
        cherry: '- work',
        extraCommits: 'work\tFix the rm bug',
      );
      when(
        () => bed.git(
          'git',
          [
            'push',
            '--force-with-lease=TICKP:abc123',
            '--set-upstream',
            'origin',
            'HEAD:refs/heads/TICKP',
          ],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(1, 1, '', 'stale info'),
      );

      await expectLater(
        () async => await runner(bed.command).run([
          'push',
          '--input',
          ticketDir.path,
          '--verbose',
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'message',
            contains('Failed to push.'),
          ),
        ),
      );

      expect(
        messages.any(
          (m) => m.contains(
            '✗ Failed to replace the obsolete branch origin/TICKP',
          ),
        ),
        isTrue,
      );
      expect(
        messages.any(
          (m) => m.contains('git push origin --delete TICKP'),
        ),
        isTrue,
      );
    });

    test(
        'aborts the rebase and fails clearly when integrating the remote '
        'feature branch conflicts (no force push)', () async {
      final bed = makeCommand(repos: ['A']);
      stubIntegrateProbes(bed.git);
      when(
        () => bed.git(
          'git',
          ['pull', '--rebase', 'origin', 'TICKP'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(1, 1, '', 'CONFLICT: could not apply'),
      );
      when(
        () => bed.git(
          'git',
          ['rebase', '--abort'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      await expectLater(
        () async => await runner(bed.command).run([
          'push',
          '--input',
          ticketDir.path,
          '--verbose',
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => rmControls(e.toString()),
            'message',
            contains('Failed to push.'),
          ),
        ),
      );

      verify(
        () => bed.git(
          'git',
          ['rebase', '--abort'],
          workingDirectory: path.join(ticketDir.path, 'A'),
        ),
      ).called(1);
      expect(
        messages.any(
          (m) => m.contains('✗ Failed to integrate origin/TICKP into A'),
        ),
        isTrue,
      );
      expect(
        messages.any(
          (m) => m.contains('git pull --rebase origin TICKP'),
        ),
        isTrue,
      );
      // Never force-push over a real divergence.
      verifyNever(
        () => bed.git(
          'git',
          any(
            that: contains(
              predicate<String>((a) => a.startsWith('--force-with-lease')),
            ),
          ),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
    });
  });
}

/// Returns a [MockSortedProcessingList] resolving [repos] inside [ticketDir].
MockSortedProcessingList _sortedList(Directory ticketDir, List<String> repos) {
  final sorted = MockSortedProcessingList();
  when(
    () => sorted.get(
      directory: any(named: 'directory'),
      ggLog: any(named: 'ggLog'),
    ),
  ).thenAnswer(
    (_) async => [
      for (final repo in repos)
        Node(
          name: repo,
          directory: Directory(path.join(ticketDir.path, repo)),
          manifest: DartPackageManifest(pubspec: Pubspec(repo)),
        ),
    ],
  );
  return sorted;
}
