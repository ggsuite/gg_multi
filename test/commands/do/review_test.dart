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

class MockGgDoMerge extends Mock implements gg.DoMerge {}

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

/// Stubs `git rev-parse HEAD` on [m] to return a constant value, so the merge
/// step sees an unchanged HEAD and skips the post-merge `gg can commit`
/// verification.
void stubGitHeadUnchanged(MockProcessRunner m) {
  when(
    () => m(
      'git',
      ['rev-parse', 'HEAD'],
      workingDirectory: any(named: 'workingDirectory'),
    ),
  ).thenAnswer((_) async => ProcessResult(0, 0, 'samehead', ''));
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
        final mockGgDoMerge = MockGgDoMerge();
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
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockGgDoPush.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockGgDoMerge.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            automerge: any(named: 'automerge'),
            local: any(named: 'local'),
            message: any(named: 'message'),
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
            message: 'gg_multi: changed references to git',
            force: any(named: 'force'),
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
      final mockGgDoMerge = MockGgDoMerge();
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
        ),
      ).thenThrow(Exception('commit failed'));

      when(
        () => mockGgDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgDoMerge.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          automerge: any(named: 'automerge'),
          local: any(named: 'local'),
          message: any(named: 'message'),
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
      final mockGgDoMerge = MockGgDoMerge();
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

      when(
        () => mockGgDoMerge.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          automerge: any(named: 'automerge'),
          local: any(named: 'local'),
          message: any(named: 'message'),
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
        final mockGgDoMerge = MockGgDoMerge();
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
          ),
        ).thenAnswer((_) async {});
        when(
          () => mockGgDoPush.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => mockGgDoMerge.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            automerge: any(named: 'automerge'),
            local: any(named: 'local'),
            message: any(named: 'message'),
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
        final mockGgDoMerge = MockGgDoMerge();

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

        when(
          () => mockGgDoMerge.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            automerge: any(named: 'automerge'),
            local: any(named: 'local'),
            message: any(named: 'message'),
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
        final mockGgDoMerge = MockGgDoMerge();

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

        when(
          () => mockGgDoMerge.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            automerge: any(named: 'automerge'),
            local: any(named: 'local'),
            message: any(named: 'message'),
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

        // HEAD moves during the merge → the post-merge verification runs.
        var headCalls = 0;
        when(
          () => mockProcessRunner(
            'git',
            ['rev-parse', 'HEAD'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer(
          (_) async =>
              ProcessResult(0, 0, headCalls++ == 0 ? 'before' : 'after', ''),
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

        var headCalls = 0;
        when(
          () => mockProcessRunner(
            'git',
            ['rev-parse', 'HEAD'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer(
          (_) async =>
              ProcessResult(0, 0, headCalls++ == 0 ? 'before' : 'after', ''),
        );

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
}
