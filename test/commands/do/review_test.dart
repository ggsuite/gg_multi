// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg/gg.dart' as gg;
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_localize_refs/gg_localize_refs.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:test/test.dart';
import 'package:kidney_core/src/commands/do/review.dart';
import 'package:kidney_core/src/commands/can/review.dart';
import 'package:kidney_core/src/backend/status_utils.dart';

import '../../rm_console_colors_helper.dart';

class MockSortedProcessingList extends Mock implements SortedProcessingList {}

class MockUnlocalizeRefs extends Mock implements UnlocalizeRefs {}

class MockLocalizeRefs extends Mock implements LocalizeRefs {}

class MockCanReviewCommand extends Mock implements CanReviewCommand {}

class MockGgDoCommit extends Mock implements gg.DoCommit {}

class MockGgDoPush extends Mock implements gg.DoPush {}

class FakeDirectory extends Fake implements Directory {}

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
    tempDir = Directory.systemTemp.createTempSync('do_review_ticket_test_');
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
            'Exception: kidney_core can review failed',
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
      await runner.run(['review', '--input', emptyTicket.path]);
      expect(
        messages,
        contains('⚠️ No repositories found in ticket EMPTY.'),
      );
    });

    test(
        'performs full flow including commit and push successfully, '
        'sets status', () async {
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockLocalizeRefs = MockLocalizeRefs();
      final mockCanReviewCommand = MockCanReviewCommand();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();

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
            pubspec: Pubspec('A'),
          ),
          Node(
            name: 'B',
            directory: Directory(path.join(ticketDir.path, 'B')),
            pubspec: Pubspec('B'),
          ),
        ],
      );

      when(
        () => mockUnlocalizeRefs.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockLocalizeRefs.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          git: any(named: 'git'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          logType: any(named: 'logType'),
          updateChangeLog: any(named: 'updateChangeLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async {});

      final runner = CommandRunner<void>('test', 'do review ticket')
        ..addCommand(
          DoReviewCommand(
            ggLog: ggLog,
            canReviewCommand: mockCanReviewCommand,
            unlocalizeRefs: mockUnlocalizeRefs,
            localizeRefs: mockLocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
          ),
        );
      await runner.run(['review', '--input', ticketDir.path]);
      expect(
        messages,
        contains('✅ All repositories in ticket TICKDR reviewed successfully.'),
      );
      expect(
        messages.any((m) => m.contains('Unlocalized refs for A')),
        isTrue,
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

      // Verify status files updated to git-localized
      for (final repoName in ['A', 'B']) {
        final statusFile =
            File(path.join(ticketDir.path, repoName, '.kidney_status'));
        if (statusFile.existsSync()) {
          final content =
              jsonDecode(statusFile.readAsStringSync()) as Map<String, dynamic>;
          expect(content['status'], StatusUtils.statusGitLocalized);
        }
      }

      // Verify commit called with the required message at least once
      verify(
        () => mockGgDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: 'kidney: changed references to git',
          logType: any(named: 'logType'),
          updateChangeLog: any(named: 'updateChangeLog'),
        ),
      ).called(greaterThan(0));

      // Verify push called
      verify(
        () => mockGgDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
        ),
      ).called(greaterThan(0));
    });

    test('fails and logs when commit fails for a repo', () async {
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockLocalizeRefs = MockLocalizeRefs();
      final mockCanReviewCommand = MockCanReviewCommand();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();

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
            pubspec: Pubspec('A'),
          ),
        ],
      );

      when(
        () => mockUnlocalizeRefs.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockLocalizeRefs.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          git: any(named: 'git'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          logType: any(named: 'logType'),
          updateChangeLog: any(named: 'updateChangeLog'),
        ),
      ).thenThrow(Exception('commit failed'));

      final runner = CommandRunner<void>('test', 'do review ticket')
        ..addCommand(
          DoReviewCommand(
            ggLog: ggLog,
            canReviewCommand: mockCanReviewCommand,
            unlocalizeRefs: mockUnlocalizeRefs,
            localizeRefs: mockLocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
          ),
        );
      await expectLater(
        () async => await runner.run(['review', '--input', ticketDir.path]),
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
            '❌ Failed to review the following repositories in ticket TICKDR:',
          ),
        ),
        isTrue,
      );
    });

    test('fails and logs when push fails for a repo', () async {
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockLocalizeRefs = MockLocalizeRefs();
      final mockCanReviewCommand = MockCanReviewCommand();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();

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
            pubspec: Pubspec('A'),
          ),
        ],
      );

      when(
        () => mockUnlocalizeRefs.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockLocalizeRefs.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          git: any(named: 'git'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          logType: any(named: 'logType'),
          updateChangeLog: any(named: 'updateChangeLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
        ),
      ).thenThrow(Exception('push failed'));

      final runner = CommandRunner<void>('test', 'do review ticket')
        ..addCommand(
          DoReviewCommand(
            ggLog: ggLog,
            canReviewCommand: mockCanReviewCommand,
            unlocalizeRefs: mockUnlocalizeRefs,
            localizeRefs: mockLocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
          ),
        );
      await expectLater(
        () async => await runner.run(['review', '--input', ticketDir.path]),
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
            '❌ Failed to review the following repositories in ticket TICKDR:',
          ),
        ),
        isTrue,
      );
    });

    test('logs when unlocalize fails for a repo (covers catch branch)',
        () async {
      // This test specifically hits the catch branch that logs
      // "Failed to unlocalize refs for <repo>: <error>" so that
      // coverage reaches 100% for DoReviewCommand.
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockLocalizeRefs = MockLocalizeRefs();
      final mockCanReviewCommand = MockCanReviewCommand();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();

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
            pubspec: Pubspec('A'),
          ),
        ],
      );

      // Make unlocalize throw to exercise the catch block
      when(
        () => mockUnlocalizeRefs.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenThrow(Exception('boom'));

      // The rest should never be called, but set up harmless stubs
      when(
        () => mockLocalizeRefs.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          git: any(named: 'git'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockGgDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          logType: any(named: 'logType'),
          updateChangeLog: any(named: 'updateChangeLog'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockGgDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async {});

      final runner = CommandRunner<void>('test', 'do review ticket')
        ..addCommand(
          DoReviewCommand(
            ggLog: ggLog,
            canReviewCommand: mockCanReviewCommand,
            unlocalizeRefs: mockUnlocalizeRefs,
            localizeRefs: mockLocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
          ),
        );

      await expectLater(
        () async => await runner.run(['review', '--input', ticketDir.path]),
        throwsA(isA<Exception>()),
      );

      // Assert that the specific unlocalize error log was written
      expect(
        messages.any(
          (m) => m.contains('Failed to unlocalize refs for A: Exception: boom'),
        ),
        isTrue,
      );
    });

    test('covers catch branch for localize --git failure', () async {
      // New test to explicitly cover the branch at
      // lib/src/commands/do/review.dart around failure to localize with --git
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockLocalizeRefs = MockLocalizeRefs();
      final mockCanReviewCommand = MockCanReviewCommand();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();

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
            pubspec: Pubspec('A'),
          ),
        ],
      );

      // Unlocalize works
      when(
        () => mockUnlocalizeRefs.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      // Localize with --git fails -> should log the specific error branch
      when(
        () => mockLocalizeRefs.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          git: any(named: 'git'),
        ),
      ).thenThrow(Exception('localize git failed'));

      // Remaining stubs
      when(
        () => mockGgDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          logType: any(named: 'logType'),
          updateChangeLog: any(named: 'updateChangeLog'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockGgDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async {});

      final runner = CommandRunner<void>('test', 'do review ticket')
        ..addCommand(
          DoReviewCommand(
            ggLog: ggLog,
            canReviewCommand: mockCanReviewCommand,
            unlocalizeRefs: mockUnlocalizeRefs,
            localizeRefs: mockLocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
          ),
        );

      await expectLater(
        () async => await runner.run(['review', '--input', ticketDir.path]),
        throwsA(isA<Exception>()),
      );

      expect(
        messages.any(
          (m) => m.contains(
            'Failed to localize refs with --git for A: '
            'Exception: localize git failed',
          ),
        ),
        isTrue,
      );
    });
  });
}
