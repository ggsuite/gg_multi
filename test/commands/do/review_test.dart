// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_localize_refs/gg_localize_refs.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:test/test.dart';
import 'package:gg_multi/src/commands/do/review.dart';
import 'package:gg_multi/src/commands/can/review.dart';

import '../../rm_console_colors_helper.dart';

class MockSortedProcessingList extends Mock implements SortedProcessingList {}

class MockUnlocalizeRefs extends Mock implements ChangeRefsToPubDev {}

class MockLocalizeRefsToGit extends Mock
    implements ChangeRefsToGitFeatureBranch {}

class MockCanReviewCommand extends Mock implements CanReviewCommand {}

class MockGgDoCommit extends Mock implements gg.DoCommit {}

class MockGgDoPush extends Mock implements gg.DoPush {}

class FakeDirectory extends Fake implements Directory {}

class MockGgCanCommit extends Mock implements gg.CanCommit {}

class MockProcessRunner extends Mock {
  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });
}

/// Stubs the `git fetch origin main` the merge step runs before merging, and
/// the conflict lookup that follows a failed merge (no conflicts by default).
void stubGitFetchMain(MockProcessRunner m) {
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
      ['diff', '--name-only', '--diff-filter=U'],
      workingDirectory: any(named: 'workingDirectory'),
    ),
  ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
}

/// Stubs `git rev-parse HEAD` on [m] to return a constant value, so the merge
/// step sees an unchanged HEAD and skips the post-merge `gg can commit`
/// verification. Also stubs the branch and status calls of the pre-review
/// snapshot, so the state save sees a clean repo and a rollback after a
/// failure skips it as unchanged.
void stubGitHeadUnchanged(MockProcessRunner m) {
  stubGitFetchMain(m);
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
      ['rev-parse', '--abbrev-ref', 'HEAD'],
      workingDirectory: any(named: 'workingDirectory'),
    ),
  ).thenAnswer((_) async => ProcessResult(0, 0, 'TICKDR', ''));
  when(
    () => m(
      'git',
      ['status', '--porcelain'],
      workingDirectory: any(named: 'workingDirectory'),
    ),
  ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
}

/// Stubs the probes `_integrateRemoteBranch` runs before it decides how to
/// integrate the remote feature branch: the fetch of the branch and the two
/// ancestry checks. By default the remote branch is neither already contained
/// in the local history nor obsolete, so the regular `pull --rebase` runs.
void stubIntegrateProbes(
  MockProcessRunner m, {
  String remoteHead = 'abc123',
  bool remoteContainedInHead = false,
  bool mainContainedInHead = false,
}) {
  when(
    () => m(
      'git',
      ['fetch', 'origin', 'TICKDR'],
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

/// Stubs the history inspection of `_remoteBranchIsObsolete`: [cherry] is the
/// `git cherry` output and [extraCommits] the `<hash>\t<subject>` lines the
/// remote branch holds on top of `HEAD`.
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

/// Stubs every collaborator of `do review` to succeed, so a test about the
/// remote-branch integration only has to stub the git calls of that step.
/// The remote feature branch exists and points to [remoteHead].
({MockGgDoPush push, MockProcessRunner git}) stubReviewUpTo(
  MockProcessRunner mockProcessRunner, {
  required Directory ticketDir,
  String remoteHead = 'abc123',
}) {
  final mockGgDoPush = MockGgDoPush();
  stubGitHeadUnchanged(mockProcessRunner);

  when(
    () => mockProcessRunner(
      'git',
      ['merge', 'origin/main'],
      workingDirectory: any(named: 'workingDirectory'),
    ),
  ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

  when(
    () => mockProcessRunner(
      'git',
      ['ls-remote', '--heads', 'origin', 'TICKDR'],
      workingDirectory: any(named: 'workingDirectory'),
    ),
  ).thenAnswer(
    (_) async => ProcessResult(0, 0, '$remoteHead\trefs/heads/TICKDR', ''),
  );

  when(
    () => mockGgDoPush.exec(
      directory: any(named: 'directory'),
      ggLog: any(named: 'ggLog'),
    ),
  ).thenAnswer((_) async {});

  return (push: mockGgDoPush, git: mockProcessRunner);
}

/// A [DoReviewCommand] runner with the collaborators of [stubReviewUpTo].
CommandRunner<void> reviewRunner({
  required void Function(String) ggLog,
  required Directory ticketDir,
  required MockProcessRunner mockProcessRunner,
  required MockGgDoPush mockGgDoPush,
}) {
  final mockSortedProcessingList = MockSortedProcessingList();
  final mockCanReviewCommand = MockCanReviewCommand();
  final mockLocalizeRefsToGit = MockLocalizeRefsToGit();
  final mockGgDoCommit = MockGgDoCommit();

  when(
    () => mockCanReviewCommand.exec(
      directory: any(named: 'directory'),
      ggLog: any(named: 'ggLog'),
    ),
  ).thenAnswer((_) async {});

  when(
    () => mockSortedProcessingList.get(
      directory: any(named: 'directory'),
      ggLog: any(named: 'ggLog'),
    ),
  ).thenAnswer(
    (_) async => [
      Node(
        name: 'A',
        directory: Directory(path.join(ticketDir.path, 'A')),
        manifest: DartPackageManifest(pubspec: Pubspec('A')),
      ),
    ],
  );

  when(
    () => mockLocalizeRefsToGit.get(
      directory: any(named: 'directory'),
      ggLog: any(named: 'ggLog'),
      gitRef: any(named: 'gitRef'),
    ),
  ).thenAnswer((_) async {});

  when(
    () => mockGgDoCommit.exec(
      directory: any(named: 'directory'),
      ggLog: any(named: 'ggLog'),
      message: any(named: 'message'),
      force: any(named: 'force'),
      updateChangeLog: any(named: 'updateChangeLog'),
    ),
  ).thenAnswer((_) async {});

  return CommandRunner<void>('test', 'do review ticket')
    ..addCommand(
      DoReviewCommand(
        ggLog: ggLog,
        canReviewCommand: mockCanReviewCommand,
        unlocalizeRefs: MockUnlocalizeRefs(),
        localizeRefsToGit: mockLocalizeRefsToGit,
        sortedProcessingList: mockSortedProcessingList,
        ggDoCommit: mockGgDoCommit,
        ggDoPush: mockGgDoPush,
        processRunner: mockProcessRunner.call,
      ),
    );
}

void main() {
  late Directory tempDir;
  late Directory ticketsDir;
  late Directory ticketDir;
  final messages = <String>[];

  setUpAll(() {
    registerFallbackValue(FakeDirectory());
    registerFallbackValue(<String, String>{});
  });

  void ggLog(String msg) => messages.add(rmConsoleColors(msg));

  setUp(() {
    messages.clear();
    tempDir = Directory.systemTemp.createTempSync(
      'do_review_ticket_test_',
    );
    ticketsDir = Directory(path.join(tempDir.path, 'tickets'))..createSync();
    ticketDir = Directory(path.join(ticketsDir.path, 'TICKDR'))..createSync();
    Directory(path.join(ticketDir.path, 'A')).createSync();
    Directory(path.join(ticketDir.path, 'B')).createSync();
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('DoReviewCommand (ticket-wide)', () {
    test('fails outside any ticket folder', () async {
      final runner = CommandRunner<void>('test', 'do review ticket')
        ..addCommand(
          DoReviewCommand(
            ggLog: ggLog,
          ),
        );
      await expectLater(
        runner.run(['review', '--input', tempDir.path]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            'Exception: Not inside a ticket folder',
          ),
        ),
      );
      expect(
        messages,
        contains('This command must be executed inside a ticket folder.'),
      );
    });

    test('logs when there are no repositories', () async {
      final emptyTicket = Directory(path.join(ticketsDir.path, 'EMPTY'))
        ..createSync();
      final runner = CommandRunner<void>('test', 'do review ticket')
        ..addCommand(
          DoReviewCommand(
            ggLog: ggLog,
          ),
        );
      await runner.run([
        'review',
        '--input',
        emptyTicket.path,
      ]);
      expect(
        messages,
        contains('⚠️ No repos in this ticket'),
      );
    });

    test(
      'performs full flow including merge, commit and push successfully, '
      'sets status',
      () async {
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockUnlocalizeRefs = MockUnlocalizeRefs();
        final mockLocalizeRefsToGit = MockLocalizeRefsToGit();
        final mockCanReviewCommand = MockCanReviewCommand();
        final mockGgDoCommit = MockGgDoCommit();
        final mockGgDoPush = MockGgDoPush();
        final mockProcessRunner = MockProcessRunner();
        stubGitHeadUnchanged(mockProcessRunner);

        when(
          () => mockCanReviewCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockSortedProcessingList.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(
              name: 'A',
              directory: Directory(path.join(ticketDir.path, 'A')),
              manifest: DartPackageManifest(pubspec: Pubspec('A')),
            ),
            Node(
              name: 'B',
              directory: Directory(path.join(ticketDir.path, 'B')),
              manifest: DartPackageManifest(pubspec: Pubspec('B')),
            ),
          ],
        );

        when(
          () => mockProcessRunner(
            'git',
            ['merge', 'origin/main'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        when(
          () => mockProcessRunner(
            'git',
            ['ls-remote', '--heads', 'origin', 'TICKDR'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

        when(
          () => mockLocalizeRefsToGit.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            gitRef: any(named: 'gitRef'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockGgDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            force: any(named: 'force'),
            updateChangeLog: any(named: 'updateChangeLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockGgDoPush.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        final runner = CommandRunner<void>('test', 'do review ticket')
          ..addCommand(
            DoReviewCommand(
              ggLog: ggLog,
              canReviewCommand: mockCanReviewCommand,
              unlocalizeRefs: mockUnlocalizeRefs,
              localizeRefsToGit: mockLocalizeRefsToGit,
              sortedProcessingList: mockSortedProcessingList,
              ggDoCommit: mockGgDoCommit,
              ggDoPush: mockGgDoPush,
              processRunner: mockProcessRunner.call,
            ),
          );
        await runner.run([
          'review',
          '--verbose',
          '--input',
          ticketDir.path,
        ]);

        expect(
          messages.any(
            (m) => m.contains(
              'Merging origin/main into feature branches',
            ),
          ),
          isTrue,
        );
        expect(
          messages.any(
            (m) => m.contains('Gg Multi can review?'),
          ),
          isTrue,
        );
        expect(
          messages.any(
            (m) => m.contains(
              'Setting dependencies to git, committing and pushing',
            ),
          ),
          isTrue,
        );

        verify(
          () => mockProcessRunner(
            'git',
            ['merge', 'origin/main'],
            workingDirectory: path.join(ticketDir.path, 'A'),
          ),
        ).called(1);
        verify(
          () => mockProcessRunner(
            'git',
            ['merge', 'origin/main'],
            workingDirectory: path.join(ticketDir.path, 'B'),
          ),
        ).called(1);

        verifyNever(
          () => mockUnlocalizeRefs.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        );

        expect(
          messages.any((m) => m.contains('Localized refs for A')),
          isTrue,
        );
        expect(
          messages.any((m) => m.contains('Committed A')),
          isTrue,
        );
        expect(
          messages.any((m) => m.contains('Pushed A')),
          isTrue,
        );

        verify(
          () => mockGgDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: '#gg: changed references to git',
            force: any(named: 'force'),
            // gg's bookkeeping commits must not land in CHANGELOG.md.
            updateChangeLog: false,
          ),
        ).called(greaterThan(0));

        verify(
          () => mockGgDoPush.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).called(greaterThan(0));
      },
    );

    test('fails and logs when merge of main into feature fails', () async {
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockLocalizeRefsToGit = MockLocalizeRefsToGit();
      final mockCanReviewCommand = MockCanReviewCommand();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockProcessRunner = MockProcessRunner();
      stubGitHeadUnchanged(mockProcessRunner);

      when(
        () => mockSortedProcessingList.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer(
        (_) async => [
          Node(
            name: 'A',
            directory: Directory(path.join(ticketDir.path, 'A')),
            manifest: DartPackageManifest(pubspec: Pubspec('A')),
          ),
        ],
      );

      when(
        () => mockProcessRunner(
          'git',
          ['merge', 'origin/main'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(1, 1, '', 'merge failed'),
      );

      final runner = CommandRunner<void>('test', 'do review ticket')
        ..addCommand(
          DoReviewCommand(
            ggLog: ggLog,
            canReviewCommand: mockCanReviewCommand,
            unlocalizeRefs: mockUnlocalizeRefs,
            localizeRefsToGit: mockLocalizeRefsToGit,
            sortedProcessingList: mockSortedProcessingList,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            processRunner: mockProcessRunner.call,
          ),
        );

      await expectLater(
        () async => runner.run([
          'review',
          '--verbose',
          '--input',
          ticketDir.path,
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains(
              'Failed to merge main in: A',
            ),
          ),
        ),
      );

      expect(
        messages.any(
          (m) => m.contains(
            'Failed to merge main into A for ticket TICKDR: '
            'Exception: merge failed',
          ),
        ),
        isTrue,
      );

      verifyNever(
        () => mockCanReviewCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      );
    });

    test(
      'asks the user to resolve merge conflicts and keeps the merge',
      () async {
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockUnlocalizeRefs = MockUnlocalizeRefs();
        final mockLocalizeRefsToGit = MockLocalizeRefsToGit();
        final mockCanReviewCommand = MockCanReviewCommand();
        final mockGgDoCommit = MockGgDoCommit();
        final mockGgDoPush = MockGgDoPush();
        final mockProcessRunner = MockProcessRunner();
        stubGitHeadUnchanged(mockProcessRunner);

        when(
          () => mockSortedProcessingList.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(
              name: 'A',
              directory: Directory(path.join(ticketDir.path, 'A')),
              manifest: DartPackageManifest(pubspec: Pubspec('A')),
            ),
          ],
        );

        when(
          () => mockProcessRunner(
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

        // The conflicting files reported by git.
        when(
          () => mockProcessRunner(
            'git',
            ['diff', '--name-only', '--diff-filter=U'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer(
          (_) async => ProcessResult(0, 0, 'CHANGELOG.md\n.gg/.gg.json\n', ''),
        );

        final runner = CommandRunner<void>('test', 'do review ticket')
          ..addCommand(
            DoReviewCommand(
              ggLog: ggLog,
              canReviewCommand: mockCanReviewCommand,
              unlocalizeRefs: mockUnlocalizeRefs,
              localizeRefsToGit: mockLocalizeRefsToGit,
              sortedProcessingList: mockSortedProcessingList,
              ggDoCommit: mockGgDoCommit,
              ggDoPush: mockGgDoPush,
              processRunner: mockProcessRunner.call,
            ),
          );

        await expectLater(
          () async => runner.run([
            'review',
            '--verbose',
            '--input',
            ticketDir.path,
          ]),
          throwsA(
            isA<MergeConflictException>().having(
              (e) => e.toString(),
              'message',
              contains('gg do commit -m"Merge main" --no-log'),
            ),
          ),
        );

        expect(messages, contains('Please resolve merge conflicts:'));
        expect(messages, contains(' - A/CHANGELOG.md'));
        expect(messages, contains(' - A/.gg/.gg.json'));
        expect(
          messages,
          contains(
            'After merging execute: gg do commit -m"Merge main" --no-log',
          ),
        );

        // The conflicting merge is kept — no rollback, no "merge --abort".
        verifyNever(
          () => mockProcessRunner(
            'git',
            ['merge', '--abort'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        );
        expect(
          messages.any((m) => m.contains('Restoring the state')),
          isFalse,
        );
      },
    );

    test(
      'logs and throws when gg_multi can review fails',
      () async {
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockUnlocalizeRefs = MockUnlocalizeRefs();
        final mockLocalizeRefsToGit = MockLocalizeRefsToGit();
        final mockCanReviewCommand = MockCanReviewCommand();
        final mockGgDoCommit = MockGgDoCommit();
        final mockGgDoPush = MockGgDoPush();
        final mockProcessRunner = MockProcessRunner();
        stubGitHeadUnchanged(mockProcessRunner);

        when(
          () => mockSortedProcessingList.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(
              name: 'A',
              directory: Directory(path.join(ticketDir.path, 'A')),
              manifest: DartPackageManifest(pubspec: Pubspec('A')),
            ),
          ],
        );

        when(
          () => mockProcessRunner(
            'git',
            ['merge', 'origin/main'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer(
          (_) async => ProcessResult(0, 0, 'ok', ''),
        );

        when(
          () => mockCanReviewCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenThrow(Exception('can review failed'));

        final runner = CommandRunner<void>('test', 'do review ticket')
          ..addCommand(
            DoReviewCommand(
              ggLog: ggLog,
              canReviewCommand: mockCanReviewCommand,
              unlocalizeRefs: mockUnlocalizeRefs,
              localizeRefsToGit: mockLocalizeRefsToGit,
              sortedProcessingList: mockSortedProcessingList,
              ggDoCommit: mockGgDoCommit,
              ggDoPush: mockGgDoPush,
              processRunner: mockProcessRunner.call,
            ),
          );

        await expectLater(
          () async => await runner.run([
            'review',
            '--verbose',
            '--input',
            ticketDir.path,
          ]),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('gg_multi can review failed'),
            ),
          ),
        );

        expect(
          messages.any(
            (m) => m.contains(
              'gg_multi can review failed: '
              'Exception: can review failed',
            ),
          ),
          isTrue,
        );
      },
    );

    test('fails and logs when commit fails for a repo (stop immediately)',
        () async {
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockLocalizeRefsToGit = MockLocalizeRefsToGit();
      final mockCanReviewCommand = MockCanReviewCommand();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockProcessRunner = MockProcessRunner();
      stubGitHeadUnchanged(mockProcessRunner);

      when(
        () => mockCanReviewCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockSortedProcessingList.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer(
        (_) async => [
          Node(
            name: 'A',
            directory: Directory(path.join(ticketDir.path, 'A')),
            manifest: DartPackageManifest(pubspec: Pubspec('A')),
          ),
        ],
      );

      when(
        () => mockProcessRunner(
          'git',
          ['merge', 'origin/main'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

      when(
        () => mockLocalizeRefsToGit.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          gitRef: any(named: 'gitRef'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          force: any(named: 'force'),
          updateChangeLog: any(named: 'updateChangeLog'),
        ),
      ).thenThrow(Exception('commit failed'));

      when(
        () => mockGgDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      final runner = CommandRunner<void>('test', 'do review ticket')
        ..addCommand(
          DoReviewCommand(
            ggLog: ggLog,
            canReviewCommand: mockCanReviewCommand,
            unlocalizeRefs: mockUnlocalizeRefs,
            localizeRefsToGit: mockLocalizeRefsToGit,
            sortedProcessingList: mockSortedProcessingList,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            processRunner: mockProcessRunner.call,
          ),
        );
      await expectLater(
        () async => await runner.run([
          'review',
          '--verbose',
          '--input',
          ticketDir.path,
        ]),
        throwsA(isA<Exception>()),
      );

      expect(
        messages.any(
          (m) => m.contains('Failed to commit A: Exception: commit failed'),
        ),
        isTrue,
      );
      expect(
        messages.any(
          (m) => m.contains(
            '❌ Failed to review the following repositories in ticket',
          ),
        ),
        isFalse,
      );
    });

    test('fails and logs when push fails for a repo (stop immediately)',
        () async {
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockLocalizeRefsToGit = MockLocalizeRefsToGit();
      final mockCanReviewCommand = MockCanReviewCommand();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockProcessRunner = MockProcessRunner();
      stubGitHeadUnchanged(mockProcessRunner);

      when(
        () => mockCanReviewCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockSortedProcessingList.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer(
        (_) async => [
          Node(
            name: 'A',
            directory: Directory(path.join(ticketDir.path, 'A')),
            manifest: DartPackageManifest(pubspec: Pubspec('A')),
          ),
        ],
      );

      when(
        () => mockProcessRunner(
          'git',
          ['merge', 'origin/main'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

      when(
        () => mockLocalizeRefsToGit.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          gitRef: any(named: 'gitRef'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          force: any(named: 'force'),
          updateChangeLog: any(named: 'updateChangeLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenThrow(Exception('push failed'));

      when(
        () => mockProcessRunner(
          'git',
          ['ls-remote', '--heads', 'origin', 'TICKDR'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      final runner = CommandRunner<void>('test', 'do review ticket')
        ..addCommand(
          DoReviewCommand(
            ggLog: ggLog,
            canReviewCommand: mockCanReviewCommand,
            unlocalizeRefs: mockUnlocalizeRefs,
            localizeRefsToGit: mockLocalizeRefsToGit,
            sortedProcessingList: mockSortedProcessingList,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            processRunner: mockProcessRunner.call,
          ),
        );
      await expectLater(
        () async => await runner.run([
          'review',
          '--verbose',
          '--input',
          ticketDir.path,
        ]),
        throwsA(isA<Exception>()),
      );

      expect(
        messages.any(
          (m) => m.contains('Failed to push A: Exception: push failed'),
        ),
        isTrue,
      );
      expect(
        messages.any(
          (m) => m.contains(
            '❌ Failed to review the following repositories in ticket',
          ),
        ),
        isFalse,
      );
    });

    test(
      'covers catch branch for localize to git feature branch failure '
      '(stop immediately)',
      () async {
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockUnlocalizeRefs = MockUnlocalizeRefs();
        final mockLocalizeRefsToGit = MockLocalizeRefsToGit();
        final mockCanReviewCommand = MockCanReviewCommand();
        final mockGgDoCommit = MockGgDoCommit();
        final mockGgDoPush = MockGgDoPush();
        final mockProcessRunner = MockProcessRunner();
        stubGitHeadUnchanged(mockProcessRunner);

        when(
          () => mockCanReviewCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockSortedProcessingList.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(
              name: 'A',
              directory: Directory(path.join(ticketDir.path, 'A')),
              manifest: DartPackageManifest(pubspec: Pubspec('A')),
            ),
          ],
        );

        when(
          () => mockProcessRunner(
            'git',
            ['merge', 'origin/main'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        when(
          () => mockLocalizeRefsToGit.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            gitRef: any(named: 'gitRef'),
          ),
        ).thenThrow(Exception('localize git failed'));

        when(
          () => mockGgDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            force: any(named: 'force'),
            updateChangeLog: any(named: 'updateChangeLog'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => mockGgDoPush.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});
        final runner = CommandRunner<void>('test', 'do review ticket')
          ..addCommand(
            DoReviewCommand(
              ggLog: ggLog,
              canReviewCommand: mockCanReviewCommand,
              unlocalizeRefs: mockUnlocalizeRefs,
              localizeRefsToGit: mockLocalizeRefsToGit,
              sortedProcessingList: mockSortedProcessingList,
              ggDoCommit: mockGgDoCommit,
              ggDoPush: mockGgDoPush,
              processRunner: mockProcessRunner.call,
            ),
          );

        await expectLater(
          () async => await runner.run([
            'review',
            '--verbose',
            '--input',
            ticketDir.path,
          ]),
          throwsA(isA<Exception>()),
        );

        expect(
          messages.any(
            (m) => m.contains(
              'Failed to localize refs to git feature branch for A: '
              'Exception: localize git failed',
            ),
          ),
          isTrue,
        );
        expect(
          messages.any(
            (m) => m.contains(
              '❌ Failed to review the following repositories in ticket',
            ),
          ),
          isFalse,
        );
      },
    );

    test(
      'executes dart pub upgrade after localize and before commit, logs '
      'success',
      () async {
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockUnlocalizeRefs = MockUnlocalizeRefs();
        final mockLocalizeRefsToGit = MockLocalizeRefsToGit();
        final mockCanReviewCommand = MockCanReviewCommand();
        final mockGgDoCommit = MockGgDoCommit();
        final mockGgDoPush = MockGgDoPush();
        final mockProcessRunner = MockProcessRunner();
        stubGitHeadUnchanged(mockProcessRunner);

        final repoADir = Directory(path.join(ticketDir.path, 'A'));
        File(path.join(repoADir.path, 'pubspec.yaml')).writeAsStringSync(
          'name: A',
        );

        when(
          () => mockCanReviewCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockSortedProcessingList.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(
              name: 'A',
              directory: Directory(path.join(ticketDir.path, 'A')),
              manifest: DartPackageManifest(pubspec: Pubspec('A')),
            ),
          ],
        );

        when(
          () => mockProcessRunner(
            'git',
            ['merge', 'origin/main'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        when(
          () => mockLocalizeRefsToGit.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            gitRef: any(named: 'gitRef'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockGgDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            force: any(named: 'force'),
            updateChangeLog: any(named: 'updateChangeLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockGgDoPush.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockProcessRunner(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: path.join(ticketDir.path, 'A'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        when(
          () => mockProcessRunner(
            'git',
            ['ls-remote', '--heads', 'origin', 'TICKDR'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

        final runner = CommandRunner<void>('test', 'do review ticket')
          ..addCommand(
            DoReviewCommand(
              ggLog: ggLog,
              canReviewCommand: mockCanReviewCommand,
              unlocalizeRefs: mockUnlocalizeRefs,
              localizeRefsToGit: mockLocalizeRefsToGit,
              sortedProcessingList: mockSortedProcessingList,
              ggDoCommit: mockGgDoCommit,
              ggDoPush: mockGgDoPush,
              processRunner: mockProcessRunner.call,
            ),
          );

        await runner.run([
          'review',
          '--verbose',
          '--input',
          ticketDir.path,
        ]);

        expect(
          messages.any(
            (m) => m.contains('Executed dart pub upgrade in A.'),
          ),
          isTrue,
        );
      },
    );

    test(
      'fails and logs when dart pub upgrade fails (stop immediately)',
      () async {
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockUnlocalizeRefs = MockUnlocalizeRefs();
        final mockLocalizeRefsToGit = MockLocalizeRefsToGit();
        final mockCanReviewCommand = MockCanReviewCommand();
        final mockGgDoCommit = MockGgDoCommit();
        final mockGgDoPush = MockGgDoPush();
        final mockProcessRunner = MockProcessRunner();
        stubGitHeadUnchanged(mockProcessRunner);

        final repoADir = Directory(path.join(ticketDir.path, 'A'));
        File(path.join(repoADir.path, 'pubspec.yaml')).writeAsStringSync(
          'name: A',
        );

        when(
          () => mockCanReviewCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockSortedProcessingList.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(
              name: 'A',
              directory: Directory(path.join(ticketDir.path, 'A')),
              manifest: DartPackageManifest(pubspec: Pubspec('A')),
            ),
          ],
        );

        when(
          () => mockProcessRunner(
            'git',
            ['merge', 'origin/main'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        when(
          () => mockLocalizeRefsToGit.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            gitRef: any(named: 'gitRef'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockGgDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            force: any(named: 'force'),
            updateChangeLog: any(named: 'updateChangeLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockGgDoPush.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockProcessRunner(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: path.join(ticketDir.path, 'A'),
          ),
        ).thenAnswer(
          (_) async => ProcessResult(1, 1, '', 'upgrade error'),
        );

        final runner = CommandRunner<void>('test', 'do review ticket')
          ..addCommand(
            DoReviewCommand(
              ggLog: ggLog,
              canReviewCommand: mockCanReviewCommand,
              unlocalizeRefs: mockUnlocalizeRefs,
              localizeRefsToGit: mockLocalizeRefsToGit,
              sortedProcessingList: mockSortedProcessingList,
              ggDoCommit: mockGgDoCommit,
              ggDoPush: mockGgDoPush,
              processRunner: mockProcessRunner.call,
            ),
          );

        await expectLater(
          () async => await runner.run([
            'review',
            '--verbose',
            '--input',
            ticketDir.path,
          ]),
          throwsA(isA<Exception>()),
        );

        expect(
          messages.any(
            (m) => m.contains(
              'Failed to execute dart pub upgrade in A: upgrade error',
            ),
          ),
          isTrue,
        );
        expect(
          messages.any(
            (m) => m.contains(
              '❌ Failed to review the following repositories in ticket',
            ),
          ),
          isFalse,
        );
      },
    );

    test(
      'executes npm install for typescript repos after localize, logs '
      'success',
      () async {
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockUnlocalizeRefs = MockUnlocalizeRefs();
        final mockLocalizeRefsToGit = MockLocalizeRefsToGit();
        final mockCanReviewCommand = MockCanReviewCommand();
        final mockGgDoCommit = MockGgDoCommit();
        final mockGgDoPush = MockGgDoPush();
        final mockProcessRunner = MockProcessRunner();
        stubGitHeadUnchanged(mockProcessRunner);

        final repoADir = Directory(path.join(ticketDir.path, 'A'));
        File(path.join(repoADir.path, 'package.json')).writeAsStringSync(
          jsonEncode(<String, dynamic>{'name': 'A'}),
        );
        File(path.join(repoADir.path, 'tsconfig.json')).writeAsStringSync('{}');

        when(
          () => mockCanReviewCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockSortedProcessingList.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(
              name: 'A',
              directory: repoADir,
              manifest: TypeScriptPackageManifest(
                name: 'A',
                dependencies: const <String>[],
                devDependencies: const <String>[],
                rawJson: const <String, dynamic>{'name': 'A'},
              ),
            ),
          ],
        );

        when(
          () => mockProcessRunner(
            'git',
            ['merge', 'origin/main'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        when(
          () => mockLocalizeRefsToGit.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            gitRef: any(named: 'gitRef'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockGgDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            force: any(named: 'force'),
            updateChangeLog: any(named: 'updateChangeLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockGgDoPush.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockProcessRunner(
            'npm',
            ['install'],
            workingDirectory: repoADir.path,
            environment: any(named: 'environment'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        when(
          () => mockProcessRunner(
            'git',
            ['ls-remote', '--heads', 'origin', 'TICKDR'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

        final runner = CommandRunner<void>('test', 'do review ticket')
          ..addCommand(
            DoReviewCommand(
              ggLog: ggLog,
              canReviewCommand: mockCanReviewCommand,
              unlocalizeRefs: mockUnlocalizeRefs,
              localizeRefsToGit: mockLocalizeRefsToGit,
              sortedProcessingList: mockSortedProcessingList,
              ggDoCommit: mockGgDoCommit,
              ggDoPush: mockGgDoPush,
              processRunner: mockProcessRunner.call,
            ),
          );

        await runner.run([
          'review',
          '--verbose',
          '--input',
          ticketDir.path,
        ]);

        expect(
          messages.any(
            (m) => m.contains('Executed npm install in A.'),
          ),
          isTrue,
        );
        final captured = verify(
          () => mockProcessRunner(
            'npm',
            ['install'],
            workingDirectory: repoADir.path,
            environment: captureAny(named: 'environment'),
          ),
        ).captured;
        expect(captured, hasLength(1));
        // The install runs with pnpm's blockExoticSubdeps disabled, so the
        // git-referenced dependency chain that localizing creates installs.
        final env = captured.single as Map<String, String>;
        expect(env['PNPM_CONFIG_BLOCK_EXOTIC_SUBDEPS'], 'false');
      },
    );

    test(
      'surfaces the package manager stdout when install fails with an empty '
      'stderr (pnpm reports its errors on stdout)',
      () async {
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockUnlocalizeRefs = MockUnlocalizeRefs();
        final mockLocalizeRefsToGit = MockLocalizeRefsToGit();
        final mockCanReviewCommand = MockCanReviewCommand();
        final mockGgDoCommit = MockGgDoCommit();
        final mockGgDoPush = MockGgDoPush();
        final mockProcessRunner = MockProcessRunner();
        stubGitHeadUnchanged(mockProcessRunner);

        final repoADir = Directory(path.join(ticketDir.path, 'A'));
        File(path.join(repoADir.path, 'package.json')).writeAsStringSync(
          jsonEncode(<String, dynamic>{'name': 'A'}),
        );
        File(path.join(repoADir.path, 'tsconfig.json')).writeAsStringSync('{}');

        when(
          () => mockCanReviewCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockSortedProcessingList.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(
              name: 'A',
              directory: repoADir,
              manifest: TypeScriptPackageManifest(
                name: 'A',
                dependencies: const <String>[],
                devDependencies: const <String>[],
                rawJson: const <String, dynamic>{'name': 'A'},
              ),
            ),
          ],
        );

        when(
          () => mockProcessRunner(
            'git',
            ['merge', 'origin/main'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        when(
          () => mockLocalizeRefsToGit.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            gitRef: any(named: 'gitRef'),
          ),
        ).thenAnswer((_) async {});

        // The package manager fails but writes its diagnostic to stdout, not
        // stderr — exactly how pnpm reports ERR_PNPM_EXOTIC_SUBDEP.
        when(
          () => mockProcessRunner(
            'npm',
            ['install'],
            workingDirectory: repoADir.path,
            environment: any(named: 'environment'),
          ),
        ).thenAnswer(
          (_) async =>
              ProcessResult(1, 1, 'ERR_PNPM_EXOTIC_SUBDEP blocked', ''),
        );

        final runner = CommandRunner<void>('test', 'do review ticket')
          ..addCommand(
            DoReviewCommand(
              ggLog: ggLog,
              canReviewCommand: mockCanReviewCommand,
              unlocalizeRefs: mockUnlocalizeRefs,
              localizeRefsToGit: mockLocalizeRefsToGit,
              sortedProcessingList: mockSortedProcessingList,
              ggDoCommit: mockGgDoCommit,
              ggDoPush: mockGgDoPush,
              processRunner: mockProcessRunner.call,
            ),
          );

        await expectLater(
          () async => await runner.run([
            'review',
            '--verbose',
            '--input',
            ticketDir.path,
          ]),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('ERR_PNPM_EXOTIC_SUBDEP blocked'),
            ),
          ),
        );

        // The swallowed cause is surfaced from stdout, not left blank.
        expect(
          messages.any(
            (m) => m.contains(
              'Failed to execute npm install in A: '
              'ERR_PNPM_EXOTIC_SUBDEP blocked',
            ),
          ),
          isTrue,
        );
      },
    );

    test(
      'executes npm install AND dart pub upgrade for bridge repos '
      '(both manifests are refreshed)',
      () async {
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockUnlocalizeRefs = MockUnlocalizeRefs();
        final mockLocalizeRefsToGit = MockLocalizeRefsToGit();
        final mockCanReviewCommand = MockCanReviewCommand();
        final mockGgDoCommit = MockGgDoCommit();
        final mockGgDoPush = MockGgDoPush();
        final mockProcessRunner = MockProcessRunner();
        stubGitHeadUnchanged(mockProcessRunner);

        // A bridge repo carries pubspec.yaml AND package.json + tsconfig.json.
        final repoADir = Directory(path.join(ticketDir.path, 'A'));
        File(path.join(repoADir.path, 'pubspec.yaml')).writeAsStringSync(
          'name: A\n',
        );
        File(path.join(repoADir.path, 'package.json')).writeAsStringSync(
          jsonEncode(<String, dynamic>{'name': 'A'}),
        );
        File(path.join(repoADir.path, 'tsconfig.json')).writeAsStringSync('{}');

        when(
          () => mockCanReviewCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockSortedProcessingList.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(
              name: 'A',
              directory: repoADir,
              manifest: TypeScriptPackageManifest(
                name: 'A',
                dependencies: const <String>[],
                devDependencies: const <String>[],
                rawJson: const <String, dynamic>{'name': 'A'},
              ),
            ),
          ],
        );

        when(
          () => mockProcessRunner(
            'git',
            ['merge', 'origin/main'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        when(
          () => mockLocalizeRefsToGit.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            gitRef: any(named: 'gitRef'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockGgDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            force: any(named: 'force'),
            updateChangeLog: any(named: 'updateChangeLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockGgDoPush.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockProcessRunner(
            'npm',
            ['install'],
            workingDirectory: repoADir.path,
            environment: any(named: 'environment'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        when(
          () => mockProcessRunner(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: repoADir.path,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        when(
          () => mockProcessRunner(
            'git',
            ['ls-remote', '--heads', 'origin', 'TICKDR'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

        final runner = CommandRunner<void>('test', 'do review ticket')
          ..addCommand(
            DoReviewCommand(
              ggLog: ggLog,
              canReviewCommand: mockCanReviewCommand,
              unlocalizeRefs: mockUnlocalizeRefs,
              localizeRefsToGit: mockLocalizeRefsToGit,
              sortedProcessingList: mockSortedProcessingList,
              ggDoCommit: mockGgDoCommit,
              ggDoPush: mockGgDoPush,
              processRunner: mockProcessRunner.call,
            ),
          );

        await runner.run([
          'review',
          '--verbose',
          '--input',
          ticketDir.path,
        ]);

        // A bridge refreshes BOTH manifests: the TypeScript package manager
        // (npm install) AND the Dart side (dart pub upgrade).
        expect(
          messages.any(
            (m) => m.contains('Executed npm install in A.'),
          ),
          isTrue,
        );
        expect(
          messages.any(
            (m) => m.contains('Executed dart pub upgrade in A.'),
          ),
          isTrue,
        );
        verify(
          () => mockProcessRunner(
            'npm',
            ['install'],
            workingDirectory: repoADir.path,
            environment: any(named: 'environment'),
          ),
        ).called(1);
        verify(
          () => mockProcessRunner(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: repoADir.path,
          ),
        ).called(1);
      },
    );

    test(
      'uses quiet taskLog when verbose is false',
      () async {
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockUnlocalizeRefs = MockUnlocalizeRefs();
        final mockLocalizeRefsToGit = MockLocalizeRefsToGit();
        final mockCanReviewCommand = MockCanReviewCommand();
        final mockGgDoCommit = MockGgDoCommit();
        final mockGgDoPush = MockGgDoPush();
        final mockProcessRunner = MockProcessRunner();
        stubGitHeadUnchanged(mockProcessRunner);

        when(
          () => mockCanReviewCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockSortedProcessingList.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(
              name: 'A',
              directory: Directory(path.join(ticketDir.path, 'A')),
              manifest: DartPackageManifest(pubspec: Pubspec('A')),
            ),
          ],
        );

        when(
          () => mockProcessRunner(
            'git',
            ['merge', 'origin/main'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        when(
          () => mockLocalizeRefsToGit.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            gitRef: any(named: 'gitRef'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockGgDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            force: any(named: 'force'),
            updateChangeLog: any(named: 'updateChangeLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockGgDoPush.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockProcessRunner(
            'git',
            ['ls-remote', '--heads', 'origin', 'TICKDR'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

        final localMessages = <String>[];
        void localLog(String msg) => localMessages.add(rmConsoleColors(msg));

        final command = DoReviewCommand(
          ggLog: localLog,
          canReviewCommand: mockCanReviewCommand,
          unlocalizeRefs: mockUnlocalizeRefs,
          localizeRefsToGit: mockLocalizeRefsToGit,
          sortedProcessingList: mockSortedProcessingList,
          ggDoCommit: mockGgDoCommit,
          ggDoPush: mockGgDoPush,
          processRunner: mockProcessRunner.call,
        );

        await command.get(
          directory: ticketDir,
          ggLog: localLog,
          verbose: false,
        );

        expect(
          localMessages.any(
            (m) => m.contains(
              'Merging origin/main into feature branches',
            ),
          ),
          isTrue,
        );
      },
    );

    test(
      'integrates the remote feature branch before pushing when it exists',
      () async {
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockUnlocalizeRefs = MockUnlocalizeRefs();
        final mockLocalizeRefsToGit = MockLocalizeRefsToGit();
        final mockCanReviewCommand = MockCanReviewCommand();
        final mockGgDoCommit = MockGgDoCommit();
        final mockGgDoPush = MockGgDoPush();
        final mockProcessRunner = MockProcessRunner();
        stubGitHeadUnchanged(mockProcessRunner);

        when(
          () => mockCanReviewCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockSortedProcessingList.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(
              name: 'A',
              directory: Directory(path.join(ticketDir.path, 'A')),
              manifest: DartPackageManifest(pubspec: Pubspec('A')),
            ),
          ],
        );

        when(
          () => mockProcessRunner(
            'git',
            ['merge', 'origin/main'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        when(
          () => mockLocalizeRefsToGit.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            gitRef: any(named: 'gitRef'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockGgDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            force: any(named: 'force'),
            updateChangeLog: any(named: 'updateChangeLog'),
          ),
        ).thenAnswer((_) async {});

        // The remote feature branch already exists ...
        when(
          () => mockProcessRunner(
            'git',
            ['ls-remote', '--heads', 'origin', 'TICKDR'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer(
          (_) async => ProcessResult(0, 0, 'abc123\trefs/heads/TICKDR', ''),
        );

        // ... is not contained in the local history and is no leftover ...
        stubIntegrateProbes(mockProcessRunner);

        // ... so a rebase pull integrates it and succeeds.
        when(
          () => mockProcessRunner(
            'git',
            ['pull', '--rebase', 'origin', 'TICKDR'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        when(
          () => mockGgDoPush.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        final runner = CommandRunner<void>('test', 'do review ticket')
          ..addCommand(
            DoReviewCommand(
              ggLog: ggLog,
              canReviewCommand: mockCanReviewCommand,
              unlocalizeRefs: mockUnlocalizeRefs,
              localizeRefsToGit: mockLocalizeRefsToGit,
              sortedProcessingList: mockSortedProcessingList,
              ggDoCommit: mockGgDoCommit,
              ggDoPush: mockGgDoPush,
              processRunner: mockProcessRunner.call,
            ),
          );

        await runner.run([
          'review',
          '--verbose',
          '--input',
          ticketDir.path,
        ]);

        expect(
          messages.any(
            (m) => m.contains('Integrated origin/TICKDR into A before push'),
          ),
          isTrue,
        );
        expect(
          messages.any((m) => m.contains('Pushed A')),
          isTrue,
        );
        verify(
          () => mockProcessRunner(
            'git',
            ['pull', '--rebase', 'origin', 'TICKDR'],
            workingDirectory: path.join(ticketDir.path, 'A'),
          ),
        ).called(1);
      },
    );

    test(
      'skips the integration when the remote branch is already contained '
      'in the local history',
      () async {
        final git = MockProcessRunner();
        final mocks = stubReviewUpTo(git, ticketDir: ticketDir);
        stubIntegrateProbes(git, remoteContainedInHead: true);

        await reviewRunner(
          ggLog: ggLog,
          ticketDir: ticketDir,
          mockProcessRunner: git,
          mockGgDoPush: mocks.push,
        ).run(['review', '--verbose', '--input', ticketDir.path]);

        verifyNever(
          () => git(
            'git',
            ['pull', '--rebase', 'origin', 'TICKDR'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        );
        expect(messages.any((m) => m.contains('Pushed A')), isTrue);
      },
    );

    test(
      'replaces an obsolete remote branch — one whose commits are on main or '
      'gg bookkeeping — instead of rebasing onto it',
      () async {
        final git = MockProcessRunner();
        final mocks = stubReviewUpTo(git, ticketDir: ticketDir);
        stubIntegrateProbes(git, mainContainedInHead: true);
        stubObsoleteAnalysis(
          git,
          // »work« was squash-merged into main, so its patch is found there.
          cherry: '- work\n+ ggcommit',
          extraCommits: 'work\tFix the rm bug\n'
              'ggcommit\t#gg: changed references to git',
        );
        when(
          () => git(
            'git',
            [
              'push',
              '--force-with-lease=TICKDR:abc123',
              '--set-upstream',
              'origin',
              'HEAD:refs/heads/TICKDR',
            ],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        await reviewRunner(
          ggLog: ggLog,
          ticketDir: ticketDir,
          mockProcessRunner: git,
          mockGgDoPush: mocks.push,
        ).run(['review', '--verbose', '--input', ticketDir.path]);

        verifyNever(
          () => git(
            'git',
            ['pull', '--rebase', 'origin', 'TICKDR'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        );
        verify(
          () => git(
            'git',
            [
              'push',
              '--force-with-lease=TICKDR:abc123',
              '--set-upstream',
              'origin',
              'HEAD:refs/heads/TICKDR',
            ],
            workingDirectory: path.join(ticketDir.path, 'A'),
          ),
        ).called(1);
        expect(
          messages.any(
            (m) => m.contains(
              'origin/TICKDR of A was a leftover of an already merged ticket',
            ),
          ),
          isTrue,
        );
      },
    );

    test(
      'rebases when the remote branch still holds a commit that is neither '
      'on main nor gg bookkeeping',
      () async {
        final git = MockProcessRunner();
        final mocks = stubReviewUpTo(git, ticketDir: ticketDir);
        stubIntegrateProbes(git, mainContainedInHead: true);
        stubObsoleteAnalysis(
          git,
          cherry: '+ work',
          extraCommits: 'work\tSomebody else pushed this',
        );
        when(
          () => git(
            'git',
            ['pull', '--rebase', 'origin', 'TICKDR'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        await reviewRunner(
          ggLog: ggLog,
          ticketDir: ticketDir,
          mockProcessRunner: git,
          mockGgDoPush: mocks.push,
        ).run(['review', '--verbose', '--input', ticketDir.path]);

        verify(
          () => git(
            'git',
            ['pull', '--rebase', 'origin', 'TICKDR'],
            workingDirectory: path.join(ticketDir.path, 'A'),
          ),
        ).called(1);
      },
    );

    test(
      'rebases when the remote branch adds no commit to the local history',
      () async {
        final git = MockProcessRunner();
        final mocks = stubReviewUpTo(git, ticketDir: ticketDir);
        stubIntegrateProbes(git, mainContainedInHead: true);
        stubObsoleteAnalysis(git, extraCommits: '');
        when(
          () => git(
            'git',
            ['pull', '--rebase', 'origin', 'TICKDR'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        await reviewRunner(
          ggLog: ggLog,
          ticketDir: ticketDir,
          mockProcessRunner: git,
          mockGgDoPush: mocks.push,
        ).run(['review', '--verbose', '--input', ticketDir.path]);

        verify(
          () => git(
            'git',
            ['pull', '--rebase', 'origin', 'TICKDR'],
            workingDirectory: path.join(ticketDir.path, 'A'),
          ),
        ).called(1);
      },
    );

    test(
      'fails with a manual-deletion hint when replacing the obsolete remote '
      'branch is rejected',
      () async {
        final git = MockProcessRunner();
        final mocks = stubReviewUpTo(git, ticketDir: ticketDir);
        stubIntegrateProbes(git, mainContainedInHead: true);
        stubObsoleteAnalysis(
          git,
          cherry: '- work',
          extraCommits: 'work\tFix the rm bug',
        );
        when(
          () => git(
            'git',
            [
              'push',
              '--force-with-lease=TICKDR:abc123',
              '--set-upstream',
              'origin',
              'HEAD:refs/heads/TICKDR',
            ],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer(
          (_) async => ProcessResult(1, 1, '', 'stale info'),
        );

        await expectLater(
          () async => reviewRunner(
            ggLog: ggLog,
            ticketDir: ticketDir,
            mockProcessRunner: git,
            mockGgDoPush: mocks.push,
          ).run(['review', '--verbose', '--input', ticketDir.path]),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('git push origin --delete TICKDR'),
            ),
          ),
        );

        expect(
          messages.any(
            (m) => m.contains(
              'Failed to replace the obsolete branch origin/TICKDR of A',
            ),
          ),
          isTrue,
        );
      },
    );

    test(
      'aborts the rebase and fails clearly when integrating the remote '
      'feature branch conflicts (no force push)',
      () async {
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockUnlocalizeRefs = MockUnlocalizeRefs();
        final mockLocalizeRefsToGit = MockLocalizeRefsToGit();
        final mockCanReviewCommand = MockCanReviewCommand();
        final mockGgDoCommit = MockGgDoCommit();
        final mockGgDoPush = MockGgDoPush();
        final mockProcessRunner = MockProcessRunner();
        stubGitHeadUnchanged(mockProcessRunner);

        when(
          () => mockCanReviewCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockSortedProcessingList.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(
              name: 'A',
              directory: Directory(path.join(ticketDir.path, 'A')),
              manifest: DartPackageManifest(pubspec: Pubspec('A')),
            ),
          ],
        );

        when(
          () => mockProcessRunner(
            'git',
            ['merge', 'origin/main'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        when(
          () => mockLocalizeRefsToGit.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            gitRef: any(named: 'gitRef'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockGgDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            force: any(named: 'force'),
            updateChangeLog: any(named: 'updateChangeLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockProcessRunner(
            'git',
            ['ls-remote', '--heads', 'origin', 'TICKDR'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer(
          (_) async => ProcessResult(0, 0, 'abc123\trefs/heads/TICKDR', ''),
        );

        stubIntegrateProbes(mockProcessRunner);

        when(
          () => mockProcessRunner(
            'git',
            ['pull', '--rebase', 'origin', 'TICKDR'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer(
          (_) async => ProcessResult(1, 1, '', 'CONFLICT (content): merge'),
        );

        when(
          () => mockProcessRunner(
            'git',
            ['rebase', '--abort'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        when(
          () => mockGgDoPush.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        final runner = CommandRunner<void>('test', 'do review ticket')
          ..addCommand(
            DoReviewCommand(
              ggLog: ggLog,
              canReviewCommand: mockCanReviewCommand,
              unlocalizeRefs: mockUnlocalizeRefs,
              localizeRefsToGit: mockLocalizeRefsToGit,
              sortedProcessingList: mockSortedProcessingList,
              ggDoCommit: mockGgDoCommit,
              ggDoPush: mockGgDoPush,
              processRunner: mockProcessRunner.call,
            ),
          );

        await expectLater(
          () async => runner.run([
            'review',
            '--verbose',
            '--input',
            ticketDir.path,
          ]),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('could not rebase onto origin/TICKDR'),
            ),
          ),
        );

        expect(
          messages.any(
            (m) => m.contains(
              'Failed to integrate origin/TICKDR into A before push',
            ),
          ),
          isTrue,
        );
        verify(
          () => mockProcessRunner(
            'git',
            ['rebase', '--abort'],
            workingDirectory: path.join(ticketDir.path, 'A'),
          ),
        ).called(1);
        verifyNever(
          () => mockGgDoPush.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        );
      },
    );

    test(
      'runs "gg can commit" after a merge that moved HEAD and proceeds when '
      'it passes',
      () async {
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockUnlocalizeRefs = MockUnlocalizeRefs();
        final mockLocalizeRefsToGit = MockLocalizeRefsToGit();
        final mockCanReviewCommand = MockCanReviewCommand();
        final mockGgDoCommit = MockGgDoCommit();
        final mockGgDoPush = MockGgDoPush();
        final mockGgCanCommit = MockGgCanCommit();
        final mockProcessRunner = MockProcessRunner();
        stubGitFetchMain(mockProcessRunner);

        // HEAD moves during the merge → the post-merge verification runs.
        // Call 0 is the pre-review snapshot, call 1 the pre-merge hash.
        var headCalls = 0;
        when(
          () => mockProcessRunner(
            'git',
            ['rev-parse', 'HEAD'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer(
          (_) async =>
              ProcessResult(0, 0, headCalls++ <= 1 ? 'before' : 'after', ''),
        );
        when(
          () => mockProcessRunner(
            'git',
            ['rev-parse', '--abbrev-ref', 'HEAD'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'TICKDR', ''));
        when(
          () => mockProcessRunner(
            'git',
            ['status', '--porcelain'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

        when(
          () => mockCanReviewCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockSortedProcessingList.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(
              name: 'A',
              directory: Directory(path.join(ticketDir.path, 'A')),
              manifest: DartPackageManifest(pubspec: Pubspec('A')),
            ),
          ],
        );

        when(
          () => mockProcessRunner(
            'git',
            ['merge', 'origin/main'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        when(
          () => mockGgCanCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            force: any(named: 'force'),
            saveState: any(named: 'saveState'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockProcessRunner(
            'git',
            ['ls-remote', '--heads', 'origin', 'TICKDR'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

        when(
          () => mockLocalizeRefsToGit.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            gitRef: any(named: 'gitRef'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockGgDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            force: any(named: 'force'),
            updateChangeLog: any(named: 'updateChangeLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockGgDoPush.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        final runner = CommandRunner<void>('test', 'do review ticket')
          ..addCommand(
            DoReviewCommand(
              ggLog: ggLog,
              canReviewCommand: mockCanReviewCommand,
              unlocalizeRefs: mockUnlocalizeRefs,
              localizeRefsToGit: mockLocalizeRefsToGit,
              sortedProcessingList: mockSortedProcessingList,
              ggDoCommit: mockGgDoCommit,
              ggDoPush: mockGgDoPush,
              ggCanCommit: mockGgCanCommit,
              processRunner: mockProcessRunner.call,
            ),
          );

        await runner.run([
          'review',
          '--verbose',
          '--input',
          ticketDir.path,
        ]);

        expect(
          messages.any(
            (m) => m.contains(
              'Verified A still passes "gg can commit" after merging main',
            ),
          ),
          isTrue,
        );
        verify(
          () => mockGgCanCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            saveState: false,
          ),
        ).called(1);
        expect(messages.any((m) => m.contains('Pushed A')), isTrue);
      },
    );

    test(
      'aborts the review when "gg can commit" fails after a merge that '
      'moved HEAD',
      () async {
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockUnlocalizeRefs = MockUnlocalizeRefs();
        final mockLocalizeRefsToGit = MockLocalizeRefsToGit();
        final mockCanReviewCommand = MockCanReviewCommand();
        final mockGgDoCommit = MockGgDoCommit();
        final mockGgDoPush = MockGgDoPush();
        final mockGgCanCommit = MockGgCanCommit();
        final mockProcessRunner = MockProcessRunner();
        stubGitFetchMain(mockProcessRunner);

        // Call 0 is the pre-review snapshot, call 1 the pre-merge hash.
        var headCalls = 0;
        when(
          () => mockProcessRunner(
            'git',
            ['rev-parse', 'HEAD'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer(
          (_) async =>
              ProcessResult(0, 0, headCalls++ <= 1 ? 'before' : 'after', ''),
        );
        when(
          () => mockProcessRunner(
            'git',
            ['rev-parse', '--abbrev-ref', 'HEAD'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'TICKDR', ''));
        when(
          () => mockProcessRunner(
            'git',
            ['status', '--porcelain'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

        // The rollback tolerates a failing `git merge/rebase --abort` (nothing
        // to abort) and resets the moved HEAD back to the snapshot.
        when(
          () => mockProcessRunner(
            'git',
            ['merge', '--abort'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 1, '', 'no merge'));
        when(
          () => mockProcessRunner(
            'git',
            ['rebase', '--abort'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 1, '', 'no rebase'));
        when(
          () => mockProcessRunner(
            'git',
            ['reset', '--hard', 'before'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

        when(
          () => mockSortedProcessingList.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(
              name: 'A',
              directory: Directory(path.join(ticketDir.path, 'A')),
              manifest: DartPackageManifest(pubspec: Pubspec('A')),
            ),
          ],
        );

        when(
          () => mockProcessRunner(
            'git',
            ['merge', 'origin/main'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        when(
          () => mockGgCanCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            force: any(named: 'force'),
            saveState: any(named: 'saveState'),
          ),
        ).thenThrow(Exception('Duplicate mapping key'));

        when(
          () => mockLocalizeRefsToGit.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            gitRef: any(named: 'gitRef'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockGgDoPush.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        final runner = CommandRunner<void>('test', 'do review ticket')
          ..addCommand(
            DoReviewCommand(
              ggLog: ggLog,
              canReviewCommand: mockCanReviewCommand,
              unlocalizeRefs: mockUnlocalizeRefs,
              localizeRefsToGit: mockLocalizeRefsToGit,
              sortedProcessingList: mockSortedProcessingList,
              ggDoCommit: mockGgDoCommit,
              ggDoPush: mockGgDoPush,
              ggCanCommit: mockGgCanCommit,
              processRunner: mockProcessRunner.call,
            ),
          );

        await expectLater(
          () async => runner.run([
            'review',
            '--verbose',
            '--input',
            ticketDir.path,
          ]),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('merged state no longer passes "gg can commit"'),
            ),
          ),
        );

        expect(
          messages.any(
            (m) => m.contains('Merging main into A broke "gg can commit"'),
          ),
          isTrue,
        );
        // The failed review rolled the repo back to the pre-review snapshot.
        expect(
          messages.any(
            (m) => m.contains('Restored the state before the review in A'),
          ),
          isTrue,
        );
        verify(
          () => mockProcessRunner(
            'git',
            ['reset', '--hard', 'before'],
            workingDirectory: path.join(ticketDir.path, 'A'),
          ),
        ).called(1);
        verifyNever(
          () => mockLocalizeRefsToGit.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            gitRef: any(named: 'gitRef'),
          ),
        );
        verifyNever(
          () => mockGgDoPush.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        );
      },
    );
  });

  group('DoReviewCommand rollback on failure', () {
    late MockSortedProcessingList mockSortedProcessingList;
    late MockUnlocalizeRefs mockUnlocalizeRefs;
    late MockLocalizeRefsToGit mockLocalizeRefsToGit;
    late MockCanReviewCommand mockCanReviewCommand;
    late MockGgDoCommit mockGgDoCommit;
    late MockGgDoPush mockGgDoPush;
    late MockGgCanCommit mockGgCanCommit;
    late MockProcessRunner m;

    /// Creates a runner wired with all mocks of this group.
    CommandRunner<void> buildRunner() => CommandRunner<void>(
          'test',
          'do review ticket',
        )..addCommand(
            DoReviewCommand(
              ggLog: ggLog,
              canReviewCommand: mockCanReviewCommand,
              unlocalizeRefs: mockUnlocalizeRefs,
              localizeRefsToGit: mockLocalizeRefsToGit,
              sortedProcessingList: mockSortedProcessingList,
              ggDoCommit: mockGgDoCommit,
              ggDoPush: mockGgDoPush,
              ggCanCommit: mockGgCanCommit,
              processRunner: m.call,
            ),
          );

    /// Makes the processing list return the repos [names].
    void stubRepos(List<String> names) {
      when(
        () => mockSortedProcessingList.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer(
        (_) async => [
          for (final name in names)
            Node(
              name: name,
              directory: Directory(path.join(ticketDir.path, name)),
              manifest: DartPackageManifest(pubspec: Pubspec(name)),
            ),
        ],
      );
    }

    setUp(() {
      mockSortedProcessingList = MockSortedProcessingList();
      mockUnlocalizeRefs = MockUnlocalizeRefs();
      mockLocalizeRefsToGit = MockLocalizeRefsToGit();
      mockCanReviewCommand = MockCanReviewCommand();
      mockGgDoCommit = MockGgDoCommit();
      mockGgDoPush = MockGgDoPush();
      mockGgCanCommit = MockGgCanCommit();
      m = MockProcessRunner();
      stubGitFetchMain(m);

      when(
        () => mockCanReviewCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockLocalizeRefsToGit.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          gitRef: any(named: 'gitRef'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockGgDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          force: any(named: 'force'),
          updateChangeLog: any(named: 'updateChangeLog'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockGgDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockGgCanCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
          saveState: any(named: 'saveState'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => m(
          'git',
          ['ls-remote', '--heads', 'origin', 'TICKDR'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => m(
          'git',
          ['rebase', '--abort'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => m(
          'git',
          ['merge', '--abort'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
    });

    test('resets only the repos the failed review changed', () async {
      stubRepos(['A', 'B']);
      final dirA = path.join(ticketDir.path, 'A');
      final dirB = path.join(ticketDir.path, 'B');

      // A: the snapshot sees headA0, every later call the merged headA1.
      var headCallsA = 0;
      when(
        () => m('git', ['rev-parse', 'HEAD'], workingDirectory: dirA),
      ).thenAnswer(
        (_) async =>
            ProcessResult(0, 0, headCallsA++ == 0 ? 'headA0' : 'headA1', ''),
      );
      // B: never changes.
      when(
        () => m('git', ['rev-parse', 'HEAD'], workingDirectory: dirB),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'headB0', ''));
      when(
        () => m(
          'git',
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'TICKDR', ''));
      when(
        () => m(
          'git',
          ['status', '--porcelain'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      // Merging A succeeds, merging B fails and aborts the review.
      when(
        () => m('git', ['merge', 'origin/main'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => m('git', ['merge', 'origin/main'], workingDirectory: dirB),
      ).thenAnswer((_) async => ProcessResult(1, 1, '', 'merge failed'));

      when(
        () => m('git', ['reset', '--hard', 'headA0'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      await expectLater(
        () async => buildRunner().run(
          ['review', '--verbose', '--input', ticketDir.path],
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Failed to merge main in: B'),
          ),
        ),
      );

      // A is reset to its snapshot, the untouched B is left alone.
      verify(
        () => m('git', ['reset', '--hard', 'headA0'], workingDirectory: dirA),
      ).called(1);
      verifyNever(
        () => m(
          'git',
          any(that: contains('reset')),
          workingDirectory: dirB,
        ),
      );
      expect(
        messages.any(
          (msg) => msg.contains('Restored the state before the review in A'),
        ),
        isTrue,
      );
      expect(messages.any((msg) => msg.contains('Unchanged: B')), isTrue);
    });

    test('restores stashed uncommitted changes of a dirty repo', () async {
      stubRepos(['A']);
      final dirA = path.join(ticketDir.path, 'A');

      // The snapshot and the pre-merge hash see h0, the merge moves HEAD.
      var headCalls = 0;
      when(
        () => m('git', ['rev-parse', 'HEAD'], workingDirectory: dirA),
      ).thenAnswer(
        (_) async => ProcessResult(0, 0, headCalls++ <= 1 ? 'h0' : 'h1', ''),
      );
      when(
        () => m(
          'git',
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          workingDirectory: dirA,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'TICKDR', ''));
      // The repo carries uncommitted changes → the snapshot stashes them
      // (push-with-untracked, record the hash, re-apply, drop).
      when(
        () => m('git', ['status', '--porcelain'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, ' M lib/a.dart', ''));
      when(
        () => m(
          'git',
          [
            'stash',
            'push',
            '--include-untracked',
            '--message',
            'gg-multi snapshot',
          ],
          workingDirectory: dirA,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => m('git', ['rev-parse', 'stash@{0}'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'stashsha', ''));
      when(
        () => m(
          'git',
          ['stash', 'apply', '--index', 'stash@{0}'],
          workingDirectory: dirA,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => m('git', ['stash', 'drop', 'stash@{0}'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      when(
        () => m('git', ['merge', 'origin/main'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => m('git', ['reset', '--hard', 'h0'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => m(
          'git',
          ['stash', 'apply', '--index', 'stashsha'],
          workingDirectory: dirA,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      when(
        () => mockLocalizeRefsToGit.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          gitRef: any(named: 'gitRef'),
        ),
      ).thenThrow(Exception('localize failed'));

      await expectLater(
        () async => buildRunner().run(
          ['review', '--verbose', '--input', ticketDir.path],
        ),
        throwsA(isA<Exception>()),
      );

      verify(
        () => m('git', ['reset', '--hard', 'h0'], workingDirectory: dirA),
      ).called(1);
      verify(
        () => m(
          'git',
          ['stash', 'apply', '--index', 'stashsha'],
          workingDirectory: dirA,
        ),
      ).called(1);
      expect(
        messages.any(
          (msg) => msg.contains('Restored the state before the review in A'),
        ),
        isTrue,
      );
    });

    test('captures and restores untracked-only changes via stash', () async {
      stubRepos(['A']);
      final dirA = path.join(ticketDir.path, 'A');

      var headCalls = 0;
      when(
        () => m('git', ['rev-parse', 'HEAD'], workingDirectory: dirA),
      ).thenAnswer(
        (_) async => ProcessResult(0, 0, headCalls++ <= 1 ? 'h0' : 'h1', ''),
      );
      when(
        () => m(
          'git',
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          workingDirectory: dirA,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'TICKDR', ''));
      // Untracked files only → `git stash push --include-untracked` records
      // them (unlike `git stash create`), so the rollback re-applies them.
      when(
        () => m('git', ['status', '--porcelain'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, '?? new.txt', ''));
      when(
        () => m(
          'git',
          [
            'stash',
            'push',
            '--include-untracked',
            '--message',
            'gg-multi snapshot',
          ],
          workingDirectory: dirA,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => m('git', ['rev-parse', 'stash@{0}'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'untrackedsha', ''));
      when(
        () => m(
          'git',
          ['stash', 'apply', '--index', 'stash@{0}'],
          workingDirectory: dirA,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => m('git', ['stash', 'drop', 'stash@{0}'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      when(
        () => m('git', ['merge', 'origin/main'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => m('git', ['reset', '--hard', 'h0'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => m(
          'git',
          ['stash', 'apply', '--index', 'untrackedsha'],
          workingDirectory: dirA,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      when(
        () => mockLocalizeRefsToGit.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          gitRef: any(named: 'gitRef'),
        ),
      ).thenThrow(Exception('localize failed'));

      await expectLater(
        () async => buildRunner().run(
          ['review', '--verbose', '--input', ticketDir.path],
        ),
        throwsA(isA<Exception>()),
      );

      verify(
        () => m('git', ['reset', '--hard', 'h0'], workingDirectory: dirA),
      ).called(1);
      verify(
        () => m(
          'git',
          ['stash', 'apply', '--index', 'untrackedsha'],
          workingDirectory: dirA,
        ),
      ).called(1);
    });

    test('reports pushes that cannot be rolled back', () async {
      stubRepos(['A', 'B']);
      stubGitHeadUnchanged(m);

      when(
        () => m(
          'git',
          ['merge', 'origin/main'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

      // A commits and pushes fine, committing B fails.
      when(
        () => mockGgDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          force: any(named: 'force'),
          updateChangeLog: any(named: 'updateChangeLog'),
        ),
      ).thenAnswer((invocation) async {
        final dir = invocation.namedArguments[#directory] as Directory;
        if (path.basename(dir.path) == 'B') {
          throw Exception('commit failed');
        }
      });

      await expectLater(
        () async => buildRunner().run(
          ['review', '--verbose', '--input', ticketDir.path],
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Failed to review in: B'),
          ),
        ),
      );

      expect(
        messages.any(
          (msg) => msg.contains('Already pushed and not rolled back: A'),
        ),
        isTrue,
      );
    });

    test('logs a manual-recovery hint when the restore itself fails', () async {
      stubRepos(['A']);
      final dirA = path.join(ticketDir.path, 'A');

      var headCalls = 0;
      when(
        () => m('git', ['rev-parse', 'HEAD'], workingDirectory: dirA),
      ).thenAnswer(
        (_) async => ProcessResult(0, 0, headCalls++ <= 1 ? 'h0' : 'h1', ''),
      );
      when(
        () => m(
          'git',
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          workingDirectory: dirA,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'TICKDR', ''));
      // A dirty repo → the manual-recovery hint must also surface the stash
      // hash, otherwise following it would wipe the uncommitted changes.
      when(
        () => m('git', ['status', '--porcelain'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, ' M lib/a.dart', ''));
      when(
        () => m(
          'git',
          [
            'stash',
            'push',
            '--include-untracked',
            '--message',
            'gg-multi snapshot',
          ],
          workingDirectory: dirA,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => m('git', ['rev-parse', 'stash@{0}'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'stashsha', ''));
      when(
        () => m(
          'git',
          ['stash', 'apply', '--index', 'stash@{0}'],
          workingDirectory: dirA,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => m('git', ['stash', 'drop', 'stash@{0}'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => m('git', ['merge', 'origin/main'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => m('git', ['reset', '--hard', 'h0'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(1, 1, '', 'reset boom'));

      when(
        () => mockLocalizeRefsToGit.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          gitRef: any(named: 'gitRef'),
        ),
      ).thenThrow(Exception('localize failed'));

      await expectLater(
        () async => buildRunner().run(
          ['review', '--verbose', '--input', ticketDir.path],
        ),
        // The review failure stays the primary error.
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('localize refs to git failed'),
          ),
        ),
      );

      expect(
        messages.any(
          (msg) =>
              msg.contains('Restoring the state before the review failed') &&
              msg.contains('git reset --hard h0') &&
              msg.contains('git stash apply --index stashsha'),
        ),
        isTrue,
      );
    });

    test('aborts before changing anything when saving the state fails',
        () async {
      stubRepos(['A']);
      final dirA = path.join(ticketDir.path, 'A');

      when(
        () => m('git', ['rev-parse', 'HEAD'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'h0', ''));
      when(
        () => m(
          'git',
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          workingDirectory: dirA,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 1, '', 'not a repo'));

      await expectLater(
        () async => buildRunner().run(
          ['review', '--verbose', '--input', ticketDir.path],
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Failed to save the state of A before the review'),
          ),
        ),
      );

      verifyNever(
        () => m(
          'git',
          ['merge', 'origin/main'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
    });

    test('checks out the original branch when the rollback finds another one',
        () async {
      stubRepos(['A']);
      final dirA = path.join(ticketDir.path, 'A');

      var headCalls = 0;
      when(
        () => m('git', ['rev-parse', 'HEAD'], workingDirectory: dirA),
      ).thenAnswer(
        (_) async => ProcessResult(0, 0, headCalls++ <= 1 ? 'h0' : 'h1', ''),
      );
      // The snapshot sees TICKDR, the rollback finds a detached HEAD.
      var branchCalls = 0;
      when(
        () => m(
          'git',
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          workingDirectory: dirA,
        ),
      ).thenAnswer(
        (_) async =>
            ProcessResult(0, 0, branchCalls++ == 0 ? 'TICKDR' : 'HEAD', ''),
      );
      when(
        () => m('git', ['status', '--porcelain'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => m('git', ['merge', 'origin/main'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => m('git', ['checkout', 'TICKDR'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => m('git', ['reset', '--hard', 'h0'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      when(
        () => mockLocalizeRefsToGit.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          gitRef: any(named: 'gitRef'),
        ),
      ).thenThrow(Exception('localize failed'));

      await expectLater(
        () async => buildRunner().run(
          ['review', '--verbose', '--input', ticketDir.path],
        ),
        throwsA(isA<Exception>()),
      );

      verify(
        () => m('git', ['checkout', 'TICKDR'], workingDirectory: dirA),
      ).called(1);
      verify(
        () => m('git', ['reset', '--hard', 'h0'], workingDirectory: dirA),
      ).called(1);
    });

    test('restores a detached-HEAD snapshot at its commit', () async {
      stubRepos(['A']);
      final dirA = path.join(ticketDir.path, 'A');

      // Snapshot on 'dh0', the merge moves HEAD to 'dh1'.
      var headCalls = 0;
      when(
        () => m('git', ['rev-parse', 'HEAD'], workingDirectory: dirA),
      ).thenAnswer(
        (_) async => ProcessResult(0, 0, headCalls++ <= 1 ? 'dh0' : 'dh1', ''),
      );
      // The snapshot sees a detached HEAD (literal "HEAD"); the rollback later
      // finds some branch checked out.
      var branchCalls = 0;
      when(
        () => m(
          'git',
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          workingDirectory: dirA,
        ),
      ).thenAnswer(
        (_) async =>
            ProcessResult(0, 0, branchCalls++ == 0 ? 'HEAD' : 'main', ''),
      );
      when(
        () => m('git', ['status', '--porcelain'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => m('git', ['merge', 'origin/main'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      // The detached snapshot stored the commit, so restore checks out 'dh0'.
      when(
        () => m('git', ['checkout', 'dh0'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => m('git', ['reset', '--hard', 'dh0'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      when(
        () => mockLocalizeRefsToGit.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          gitRef: any(named: 'gitRef'),
        ),
      ).thenThrow(Exception('localize failed'));

      await expectLater(
        () async => buildRunner().run(
          ['review', '--verbose', '--input', ticketDir.path],
        ),
        throwsA(isA<Exception>()),
      );

      verify(
        () => m('git', ['checkout', 'dh0'], workingDirectory: dirA),
      ).called(1);
      verify(
        () => m('git', ['reset', '--hard', 'dh0'], workingDirectory: dirA),
      ).called(1);
    });
  });
}
