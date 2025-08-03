// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
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

    test('performs unlocalize and localize successfully, sets status',
        () async {
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockLocalizeRefs = MockLocalizeRefs();
      final mockCanReviewCommand = MockCanReviewCommand();

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

      final runner = CommandRunner<void>('test', 'do review ticket')
        ..addCommand(
          DoReviewCommand(
            ggLog: ggLog,
            canReviewCommand: mockCanReviewCommand,
            unlocalizeRefs: mockUnlocalizeRefs,
            localizeRefs: mockLocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
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
        messages.any((m) => m.contains('Unlocalized refs for B')),
        isTrue,
      );
      expect(
        messages.any((m) => m.contains('Localized refs for B')),
        isTrue,
      );

      // Verify status files updated
      for (final repoName in ['A', 'B']) {
        final statusFile =
            File(path.join(ticketDir.path, repoName, '.kidney_status'));
        if (statusFile.existsSync()) {
          final content =
              jsonDecode(statusFile.readAsStringSync()) as Map<String, dynamic>;
          expect(content['status'], StatusUtils.statusGitLocalized);
        }
      }
    });

    test('fails and logs for repos where unlocalize fails', () async {
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockLocalizeRefs = MockLocalizeRefs();
      final mockCanReviewCommand = MockCanReviewCommand();

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

      // Fail unlocalize for B
      when(
        () => mockUnlocalizeRefs.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((invocation) {
        final repoDir = invocation.namedArguments[#directory] as Directory;
        if (path.basename(repoDir.path) == 'B') {
          throw Exception('Unlocalize failed for B');
        }
        return Future.value();
      });

      when(
        () => mockLocalizeRefs.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          git: any(named: 'git'),
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
          ),
        );
      await expectLater(
        () async => await runner.run(['review', '--input', ticketDir.path]),
        throwsA(isA<Exception>()),
      );
      expect(
        messages.any(
          (m) => m.contains(
            'Failed to unlocalize refs for '
            'B: Exception: Unlocalize failed for B',
          ),
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
      expect(messages.any((m) => m.contains(' - B')), isTrue);

      // Verify status for A was updated to git-localized, but not for B
      final statusFileA =
          File(path.join(ticketDir.path, 'A', '.kidney_status'));
      if (statusFileA.existsSync()) {
        final content =
            jsonDecode(statusFileA.readAsStringSync()) as Map<String, dynamic>;
        expect(content['status'], StatusUtils.statusGitLocalized);
      }
      final statusFileB =
          File(path.join(ticketDir.path, 'B', '.kidney_status'));
      expect(statusFileB.existsSync(), isFalse);
    });

    test('fails and logs for repos where localize fails', () async {
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockLocalizeRefs = MockLocalizeRefs();
      final mockCanReviewCommand = MockCanReviewCommand();

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

      // Fail localize for B
      when(
        () => mockLocalizeRefs.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          git: any(named: 'git'),
        ),
      ).thenAnswer((invocation) {
        final repoDir = invocation.namedArguments[#directory] as Directory;
        if (path.basename(repoDir.path) == 'B') {
          throw Exception('Localize failed for B');
        }
        return Future.value();
      });

      final runner = CommandRunner<void>('test', 'do review ticket')
        ..addCommand(
          DoReviewCommand(
            ggLog: ggLog,
            canReviewCommand: mockCanReviewCommand,
            unlocalizeRefs: mockUnlocalizeRefs,
            localizeRefs: mockLocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
          ),
        );
      await expectLater(
        () async => await runner.run(['review', '--input', ticketDir.path]),
        throwsA(isA<Exception>()),
      );
      expect(
        messages.any(
          (m) => m.contains(
            'Failed to localize refs with --git for B: '
            'Exception: Localize failed for B',
          ),
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
      expect(messages.any((m) => m.contains(' - B')), isTrue);

      // Verify status for A was updated to git-localized, for B to unlocalized
      final statusFileA =
          File(path.join(ticketDir.path, 'A', '.kidney_status'));
      if (statusFileA.existsSync()) {
        final content =
            jsonDecode(statusFileA.readAsStringSync()) as Map<String, dynamic>;
        expect(content['status'], StatusUtils.statusGitLocalized);
      }
      final statusFileB =
          File(path.join(ticketDir.path, 'B', '.kidney_status'));
      if (statusFileB.existsSync()) {
        final content =
            jsonDecode(statusFileB.readAsStringSync()) as Map<String, dynamic>;
        expect(content['status'], StatusUtils.statusUnlocalized);
      }
    });
  });
}
