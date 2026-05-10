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
import 'package:gg_multi/src/backend/status_utils.dart';

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

class MockProcessRunner extends Mock {
  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  });
}

void main() {
  late Directory tempDir;
  late Directory ticketsDir;
  late Directory ticketDir;
  final messages = <String>[];

  setUpAll(() {
    registerFallbackValue(FakeDirectory());
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
        contains('⚠️ No repositories found in ticket EMPTY.'),
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

        for (final repoName in ['A', 'B']) {
          final statusFile = File(
            path.join(ticketDir.path, repoName, '.gg_multi_status'),
          );
          if (statusFile.existsSync()) {
            final content = jsonDecode(
              statusFile.readAsStringSync(),
            ) as Map<String, dynamic>;
            expect(content['status'], StatusUtils.statusGitLocalized);
          }
        }

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
              'Failed to merge main into some '
              'repositories in ticket TICKDR',
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
              'Exception: gg_multi can review failed',
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
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

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
        verify(
          () => mockProcessRunner(
            'npm',
            ['install'],
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
  });
}
