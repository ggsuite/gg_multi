// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights
// Reserved.
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
import 'package:kidney_core/src/commands/do/publish.dart';
import 'package:kidney_core/src/commands/can/publish.dart';
import 'package:kidney_core/src/backend/status_utils.dart';

import '../../rm_console_colors_helper.dart';

/// Mock for gg DoMerge
class MockGgDoMerge extends Mock implements gg.DoMerge {}

/// Mock for gg DoPublish
class MockGgDoPublish extends Mock implements gg.DoPublish {}

/// Mock for gg DoCommit
class MockGgDoCommit extends Mock implements gg.DoCommit {}

/// Mock for gg DoPush
class MockGgDoPush extends Mock implements gg.DoPush {}

/// Mock for SortedProcessingList
class MockSortedProcessingList extends Mock implements SortedProcessingList {}

/// Mock for CanPublishCommand
class MockCanPublishCommand extends Mock implements CanPublishCommand {}

/// Mock for UnlocalizeRefs
class MockUnlocalizeRefs extends Mock implements UnlocalizeRefs {}

/// Mocks for version/ref helpers
class MockGetVersion extends Mock implements GetVersion {}

class MockSetRefVersion extends Mock implements SetRefVersion {}

class MockGetRefVersion extends Mock implements GetRefVersion {}

class FakeDirectory extends Fake implements Directory {}

void main() {
  late Directory tempDir;
  late Directory ticketsDir;
  late Directory ticketDir;
  final messages = <String>[];

  setUpAll(() {
    registerFallbackValue(FakeDirectory());
  });

  // Collects log messages while removing color codes.
  void ggLog(String msg) => messages.add(rmConsoleColors(msg));

  setUp(() {
    messages.clear();
    tempDir = Directory.systemTemp.createTempSync('do_publish_ticket_test_');
    ticketsDir = Directory(path.join(tempDir.path, 'tickets'))..createSync();
    ticketDir = Directory(path.join(ticketsDir.path, 'TICKPB'))..createSync();
    Directory(path.join(ticketDir.path, 'A')).createSync();
    Directory(path.join(ticketDir.path, 'B')).createSync();
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('DoPublishCommand (ticket-wide)', () {
    test('fails outside any ticket folder', () async {
      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
          ),
        );
      await expectLater(
        () async => await runner.run(
          [
            'publish',
            '--force',
            '--input',
            tempDir.path,
          ],
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            'Exception: This command must be executed inside a '
                'ticket folder.',
          ),
        ),
      );
    });

    test('logs when there are no repositories', () async {
      final emptyTicket = Directory(path.join(ticketsDir.path, 'EMPTY'))
        ..createSync();
      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
          ),
        );
      await runner.run(['publish', '--force', '--input', emptyTicket.path]);
      expect(
        messages,
        contains('⚠️ No repositories found in ticket EMPTY.'),
      );
    });

    test('publishes all repos successfully', () async {
      final mockGgDoMerge = MockGgDoMerge();
      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockGetVersion = MockGetVersion();
      final mockSetRefVersion = MockSetRefVersion();
      final mockGetRefVersion = MockGetRefVersion();

      when(
        () => mockCanPublishCommand.exec(
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
          force: any(named: 'force'),
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

      when(
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGetVersion.get(
          directory: any(named: 'directory'),
        ),
      ).thenAnswer((_) async => '1.0.0');

      when(
        () => mockGetRefVersion.get(
          directory: any(named: 'directory'),
          ref: any(named: 'ref'),
        ),
      ).thenAnswer((_) async => null);

      when(
        () => mockSetRefVersion.get(
          directory: any(named: 'directory'),
          ref: any(named: 'ref'),
          version: any(named: 'version'),
        ),
      ).thenAnswer((_) async {});

      // Set initial status to git-localized for each repo
      for (final repoName in ['A', 'B']) {
        final statusFile =
            File(path.join(ticketDir.path, repoName, '.kidney_status'))
              ..createSync(recursive: true);
        statusFile.writeAsStringSync(
          jsonEncode({'status': StatusUtils.statusGitLocalized}),
        );
      }

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            ggDoMerge: mockGgDoMerge,
            ggDoPublish: mockGgDoPublish,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            unlocalizeRefs: mockUnlocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            getVersionCommand: mockGetVersion,
            setRefVersionCommand: mockSetRefVersion,
            getRefVersionCommand: mockGetRefVersion,
          ),
        );
      await runner.run(['publish', '--force', '--input', ticketDir.path]);
      expect(
        messages,
        contains('✅ All repositories in ticket TICKPB published '
            'successfully.'),
      );
      expect(
        messages.any((m) => m.contains('Publishing A in ticket TICKPB...')),
        isTrue,
      );
      expect(
        messages.any((m) => m.contains('Publishing B in ticket TICKPB...')),
        isTrue,
      );

      // Verify status files updated to merged
      for (final repoName in ['A', 'B']) {
        final statusFile =
            File(path.join(ticketDir.path, repoName, '.kidney_status'));
        final content =
            jsonDecode(statusFile.readAsStringSync()) as Map<String, dynamic>;
        expect(content['status'], StatusUtils.statusMerged);
      }
    });

    test('aborts if can publish fails', () async {
      final mockGgDoMerge = MockGgDoMerge();
      final mockGgDoPublish = MockGgDoPublish();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockGetVersion = MockGetVersion();
      final mockSetRefVersion = MockSetRefVersion();
      final mockGetRefVersion = MockGetRefVersion();

      when(
        () => mockCanPublishCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenThrow(Exception('can publish failed'));

      when(
        () => mockGetVersion.get(
          directory: any(named: 'directory'),
        ),
      ).thenAnswer((_) async => '1.0.0');
      when(
        () => mockGetRefVersion.get(
          directory: any(named: 'directory'),
          ref: any(named: 'ref'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => mockSetRefVersion.get(
          directory: any(named: 'directory'),
          ref: any(named: 'ref'),
          version: any(named: 'version'),
        ),
      ).thenAnswer((_) async {});

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            ggDoMerge: mockGgDoMerge,
            ggDoPublish: mockGgDoPublish,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            getVersionCommand: mockGetVersion,
            setRefVersionCommand: mockSetRefVersion,
            getRefVersionCommand: mockGetRefVersion,
          ),
        );
      await expectLater(
        () async =>
            await runner.run(['publish', '--force', '--input', ticketDir.path]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('kidney_core can publish failed:'),
          ),
        ),
      );
    });

    test('aborts on gg do merge failure for specific repos', () async {
      final mockGgDoMerge = MockGgDoMerge();
      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockGetVersion = MockGetVersion();
      final mockSetRefVersion = MockSetRefVersion();
      final mockGetRefVersion = MockGetRefVersion();

      when(
        () => mockCanPublishCommand.exec(
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
          force: any(named: 'force'),
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
      ).thenAnswer((invocation) {
        final repoDir = invocation.namedArguments[#directory] as Directory;
        if (path.basename(repoDir.path) == 'B') {
          throw Exception('Merge failed for B');
        }
        return Future.value();
      });

      when(
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGetVersion.get(
          directory: any(named: 'directory'),
        ),
      ).thenAnswer((_) async => '1.0.0');
      when(
        () => mockGetRefVersion.get(
          directory: any(named: 'directory'),
          ref: any(named: 'ref'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => mockSetRefVersion.get(
          directory: any(named: 'directory'),
          ref: any(named: 'ref'),
          version: any(named: 'version'),
        ),
      ).thenAnswer((_) async {});

      // Set initial status to git-localized for each repo
      for (final repoName in ['A', 'B']) {
        final statusFile =
            File(path.join(ticketDir.path, repoName, '.kidney_status'))
              ..createSync(recursive: true);
        statusFile.writeAsStringSync(
          jsonEncode({'status': StatusUtils.statusGitLocalized}),
        );
      }

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            ggDoMerge: mockGgDoMerge,
            ggDoPublish: mockGgDoPublish,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            unlocalizeRefs: mockUnlocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            getVersionCommand: mockGetVersion,
            setRefVersionCommand: mockSetRefVersion,
            getRefVersionCommand: mockGetRefVersion,
          ),
        );
      await expectLater(
        () async => await runner.run([
          'publish',
          '--force',
          '--input',
          ticketDir.path,
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Exception: Failed to merge B: Exception: Merge '
                'failed for B'),
          ),
        ),
      );

      // Verify status for A was updated to merged, but not for B
      final statusFileA =
          File(path.join(ticketDir.path, 'A', '.kidney_status'));
      final contentA =
          jsonDecode(statusFileA.readAsStringSync()) as Map<String, dynamic>;
      expect(contentA['status'], StatusUtils.statusMerged);

      final statusFileB =
          File(path.join(ticketDir.path, 'B', '.kidney_status'));
      final contentB =
          jsonDecode(statusFileB.readAsStringSync()) as Map<String, dynamic>;
      expect(contentB['status'], StatusUtils.statusGitLocalized);
    });

    test('aborts on do publish failure for specific repos', () async {
      final mockGgDoMerge = MockGgDoMerge();
      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockGetVersion = MockGetVersion();
      final mockSetRefVersion = MockSetRefVersion();
      final mockGetRefVersion = MockGetRefVersion();

      when(
        () => mockCanPublishCommand.exec(
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
          force: any(named: 'force'),
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

      when(
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((invocation) {
        final repoDir = invocation.namedArguments[#directory] as Directory;
        if (path.basename(repoDir.path) == 'B') {
          throw Exception('Publish failed for B');
        }
        return Future.value();
      });

      when(
        () => mockGetVersion.get(
          directory: any(named: 'directory'),
        ),
      ).thenAnswer((_) async => '1.0.0');
      when(
        () => mockGetRefVersion.get(
          directory: any(named: 'directory'),
          ref: any(named: 'ref'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => mockSetRefVersion.get(
          directory: any(named: 'directory'),
          ref: any(named: 'ref'),
          version: any(named: 'version'),
        ),
      ).thenAnswer((_) async {});

      // Set initial status to git-localized for each repo
      for (final repoName in ['A', 'B']) {
        final statusFile =
            File(path.join(ticketDir.path, repoName, '.kidney_status'))
              ..createSync(recursive: true);
        statusFile.writeAsStringSync(
          jsonEncode({'status': StatusUtils.statusGitLocalized}),
        );
      }

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            ggDoMerge: mockGgDoMerge,
            ggDoPublish: mockGgDoPublish,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            unlocalizeRefs: mockUnlocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            getVersionCommand: mockGetVersion,
            setRefVersionCommand: mockSetRefVersion,
            getRefVersionCommand: mockGetRefVersion,
          ),
        );
      await expectLater(
        () async => await runner.run([
          'publish',
          '--force',
          '--input',
          ticketDir.path,
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Exception: Failed to publish B: Exception: '
                'Publish failed for B'),
          ),
        ),
      );

      // Verify status for A was updated to merged,
      // for B also since merge succeeded but publish failed
      final statusFileA =
          File(path.join(ticketDir.path, 'A', '.kidney_status'));
      final contentA =
          jsonDecode(statusFileA.readAsStringSync()) as Map<String, dynamic>;
      expect(contentA['status'], StatusUtils.statusMerged);

      final statusFileB =
          File(path.join(ticketDir.path, 'B', '.kidney_status'));
      final contentB =
          jsonDecode(statusFileB.readAsStringSync()) as Map<String, dynamic>;
      expect(
        contentB['status'],
        StatusUtils.statusMerged,
      );
    });

    test('aborts on unlocalize refs failure for specific repos', () async {
      final mockGgDoMerge = MockGgDoMerge();
      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockGetVersion = MockGetVersion();
      final mockSetRefVersion = MockSetRefVersion();
      final mockGetRefVersion = MockGetRefVersion();

      when(
        () => mockCanPublishCommand.exec(
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
      ).thenAnswer((invocation) {
        final repoDir = invocation.namedArguments[#directory] as Directory;
        if (path.basename(repoDir.path) == 'B') {
          throw Exception('Unlocalize failed for B');
        }
        return Future.value();
      });

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
          force: any(named: 'force'),
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

      when(
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGetVersion.get(
          directory: any(named: 'directory'),
        ),
      ).thenAnswer((_) async => '1.0.0');
      when(
        () => mockGetRefVersion.get(
          directory: any(named: 'directory'),
          ref: any(named: 'ref'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => mockSetRefVersion.get(
          directory: any(named: 'directory'),
          ref: any(named: 'ref'),
          version: any(named: 'version'),
        ),
      ).thenAnswer((_) async {});

      // Set initial status to git-localized for each repo
      for (final repoName in ['A', 'B']) {
        final statusFile =
            File(path.join(ticketDir.path, repoName, '.kidney_status'))
              ..createSync(recursive: true);
        statusFile.writeAsStringSync(
          jsonEncode({'status': StatusUtils.statusGitLocalized}),
        );
      }

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            ggDoMerge: mockGgDoMerge,
            ggDoPublish: mockGgDoPublish,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            unlocalizeRefs: mockUnlocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            getVersionCommand: mockGetVersion,
            setRefVersionCommand: mockSetRefVersion,
            getRefVersionCommand: mockGetRefVersion,
          ),
        );
      await expectLater(
        () async => await runner.run([
          'publish',
          '--force',
          '--input',
          ticketDir.path,
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Exception: Failed to unlocalize refs for B: Exception: '
                'Unlocalize failed for B'),
          ),
        ),
      );

      // Verify status for A was updated to merged, but not for B
      final statusFileA =
          File(path.join(ticketDir.path, 'A', '.kidney_status'));
      final contentA =
          jsonDecode(statusFileA.readAsStringSync()) as Map<String, dynamic>;
      expect(contentA['status'], StatusUtils.statusMerged);

      final statusFileB =
          File(path.join(ticketDir.path, 'B', '.kidney_status'));
      final contentB =
          jsonDecode(statusFileB.readAsStringSync()) as Map<String, dynamic>;
      expect(contentB['status'], StatusUtils.statusGitLocalized);
    });

    test('aborts on do commit failure for specific repos', () async {
      final mockGgDoMerge = MockGgDoMerge();
      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockGetVersion = MockGetVersion();
      final mockSetRefVersion = MockSetRefVersion();
      final mockGetRefVersion = MockGetRefVersion();

      when(
        () => mockCanPublishCommand.exec(
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
        () => mockGgDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((invocation) {
        final repoDir = invocation.namedArguments[#directory] as Directory;
        if (path.basename(repoDir.path) == 'B') {
          throw Exception('Commit failed for B');
        }
        return Future.value();
      });

      when(
        () => mockGgDoPush.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          force: any(named: 'force'),
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

      when(
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGetVersion.get(
          directory: any(named: 'directory'),
        ),
      ).thenAnswer((_) async => '1.0.0');
      when(
        () => mockGetRefVersion.get(
          directory: any(named: 'directory'),
          ref: any(named: 'ref'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => mockSetRefVersion.get(
          directory: any(named: 'directory'),
          ref: any(named: 'ref'),
          version: any(named: 'version'),
        ),
      ).thenAnswer((_) async {});

      // Set initial status to git-localized for each repo
      for (final repoName in ['A', 'B']) {
        final statusFile =
            File(path.join(ticketDir.path, repoName, '.kidney_status'))
              ..createSync(recursive: true);
        statusFile.writeAsStringSync(
          jsonEncode({'status': StatusUtils.statusGitLocalized}),
        );
      }

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            ggDoMerge: mockGgDoMerge,
            ggDoPublish: mockGgDoPublish,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            unlocalizeRefs: mockUnlocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            getVersionCommand: mockGetVersion,
            setRefVersionCommand: mockSetRefVersion,
            getRefVersionCommand: mockGetRefVersion,
          ),
        );
      await expectLater(
        () async => await runner.run([
          'publish',
          '--force',
          '--input',
          ticketDir.path,
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Exception: Failed to commit B: Exception: '
                'Commit failed for B'),
          ),
        ),
      );

      // Verify status for A was updated to merged, but not for B
      final statusFileA =
          File(path.join(ticketDir.path, 'A', '.kidney_status'));
      final contentA =
          jsonDecode(statusFileA.readAsStringSync()) as Map<String, dynamic>;
      expect(contentA['status'], StatusUtils.statusMerged);

      final statusFileB =
          File(path.join(ticketDir.path, 'B', '.kidney_status'));
      final contentB =
          jsonDecode(statusFileB.readAsStringSync()) as Map<String, dynamic>;
      expect(contentB['status'], StatusUtils.statusGitLocalized);
    });

    test('aborts on do push failure for specific repos', () async {
      final mockGgDoMerge = MockGgDoMerge();
      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockGetVersion = MockGetVersion();
      final mockSetRefVersion = MockSetRefVersion();
      final mockGetRefVersion = MockGetRefVersion();

      when(
        () => mockCanPublishCommand.exec(
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
          force: any(named: 'force'),
        ),
      ).thenAnswer((invocation) {
        final repoDir = invocation.namedArguments[#directory] as Directory;
        if (path.basename(repoDir.path) == 'B') {
          throw Exception('Push failed for B');
        }
        return Future.value();
      });

      when(
        () => mockGgDoMerge.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          automerge: any(named: 'automerge'),
          local: any(named: 'local'),
          message: any(named: 'message'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGetVersion.get(
          directory: any(named: 'directory'),
        ),
      ).thenAnswer((_) async => '1.0.0');
      when(
        () => mockGetRefVersion.get(
          directory: any(named: 'directory'),
          ref: any(named: 'ref'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => mockSetRefVersion.get(
          directory: any(named: 'directory'),
          ref: any(named: 'ref'),
          version: any(named: 'version'),
        ),
      ).thenAnswer((_) async {});

      // Set initial status to git-localized for each repo
      for (final repoName in ['A', 'B']) {
        final statusFile =
            File(path.join(ticketDir.path, repoName, '.kidney_status'))
              ..createSync(recursive: true);
        statusFile.writeAsStringSync(
          jsonEncode({'status': StatusUtils.statusGitLocalized}),
        );
      }

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            ggDoMerge: mockGgDoMerge,
            ggDoPublish: mockGgDoPublish,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            unlocalizeRefs: mockUnlocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            getVersionCommand: mockGetVersion,
            setRefVersionCommand: mockSetRefVersion,
            getRefVersionCommand: mockGetRefVersion,
          ),
        );
      await expectLater(
        () async => await runner.run([
          'publish',
          '--force',
          '--input',
          ticketDir.path,
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Exception: Failed to push B: Exception: Push '
                'failed for B'),
          ),
        ),
      );

      // Verify status for A was updated to merged, but not for B
      final statusFileA =
          File(path.join(ticketDir.path, 'A', '.kidney_status'));
      final contentA =
          jsonDecode(statusFileA.readAsStringSync()) as Map<String, dynamic>;
      expect(contentA['status'], StatusUtils.statusMerged);

      final statusFileB =
          File(path.join(ticketDir.path, 'B', '.kidney_status'));
      final contentB =
          jsonDecode(statusFileB.readAsStringSync()) as Map<String, dynamic>;
      expect(contentB['status'], StatusUtils.statusGitLocalized);
    });

    test('skips repo already merged', () async {
      final mockGgDoMerge = MockGgDoMerge();
      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockGetVersion = MockGetVersion();
      final mockSetRefVersion = MockSetRefVersion();
      final mockGetRefVersion = MockGetRefVersion();

      when(
        () => mockCanPublishCommand.exec(
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
          force: any(named: 'force'),
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
      when(
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      // Set A to merged, B to git-localized
      final statusFileA = File(path.join(ticketDir.path, 'A', '.kidney_status'))
        ..createSync(recursive: true);
      statusFileA.writeAsStringSync(
        jsonEncode({'status': StatusUtils.statusMerged}),
      );
      final statusFileB = File(path.join(ticketDir.path, 'B', '.kidney_status'))
        ..createSync(recursive: true);
      statusFileB.writeAsStringSync(
        jsonEncode({'status': StatusUtils.statusGitLocalized}),
      );

      when(
        () => mockGetVersion.get(
          directory: any(named: 'directory'),
        ),
      ).thenAnswer((_) async => '1.0.0');
      when(
        () => mockGetRefVersion.get(
          directory: any(named: 'directory'),
          ref: any(named: 'ref'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => mockSetRefVersion.get(
          directory: any(named: 'directory'),
          ref: any(named: 'ref'),
          version: any(named: 'version'),
        ),
      ).thenAnswer((_) async {});

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            ggDoMerge: mockGgDoMerge,
            ggDoPublish: mockGgDoPublish,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            unlocalizeRefs: mockUnlocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            getVersionCommand: mockGetVersion,
            setRefVersionCommand: mockSetRefVersion,
            getRefVersionCommand: mockGetRefVersion,
          ),
        );

      await runner.run(['publish', '--force', '--input', ticketDir.path]);

      // A must be skipped with an info message
      expect(
        messages.any(
          (m) => m.contains(
            'Repository A in ticket TICKPB is already merged.',
          ),
        ),
        isTrue,
      );
      // No publish log for A
      expect(
        messages.any(
          (m) => m.contains('Publishing A in ticket TICKPB...'),
        ),
        isFalse,
      );
      // B still processed
      expect(
        messages.any(
          (m) => m.contains('Publishing B in ticket TICKPB...'),
        ),
        isTrue,
      );
    });

    test('aborts when GetVersion throws', () async {
      final mockGgDoMerge = MockGgDoMerge();
      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockGetVersion = MockGetVersion();
      final mockSetRefVersion = MockSetRefVersion();
      final mockGetRefVersion = MockGetRefVersion();

      when(
        () => mockCanPublishCommand.exec(
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

      // Make GetVersion throw to hit the catch branch
      when(
        () => mockGetVersion.get(
          directory: any(named: 'directory'),
        ),
      ).thenThrow(Exception('version read failed'));

      // Provide harmless stubs for the rest
      when(
        () => mockGetRefVersion.get(
          directory: any(named: 'directory'),
          ref: any(named: 'ref'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => mockSetRefVersion.get(
          directory: any(named: 'directory'),
          ref: any(named: 'ref'),
          version: any(named: 'version'),
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
          force: any(named: 'force'),
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
      when(
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      // Ensure initial status is correct
      final statusFileA = File(path.join(ticketDir.path, 'A', '.kidney_status'))
        ..createSync(recursive: true);
      statusFileA.writeAsStringSync(
        jsonEncode({'status': StatusUtils.statusGitLocalized}),
      );

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            ggDoMerge: mockGgDoMerge,
            ggDoPublish: mockGgDoPublish,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            unlocalizeRefs: mockUnlocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            getVersionCommand: mockGetVersion,
            setRefVersionCommand: mockSetRefVersion,
            getRefVersionCommand: mockGetRefVersion,
          ),
        );

      await expectLater(
        () async => await runner.run([
          'publish',
          '--force',
          '--input',
          ticketDir.path,
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Failed to get version of A: Exception: '
                'version read failed'),
          ),
        ),
      );
    });

    test(
      'updates dependency ref versions when a known ref is used later',
      () async {
        final mockGgDoMerge = MockGgDoMerge();
        final mockGgDoPublish = MockGgDoPublish();
        final mockGgDoCommit = MockGgDoCommit();
        final mockGgDoPush = MockGgDoPush();
        final mockUnlocalizeRefs = MockUnlocalizeRefs();
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockProcessRunner = MockProcessRunner();
        final mockCanPublishCommand = MockCanPublishCommand();
        final mockGetVersion = MockGetVersion();
        final mockSetRefVersion = MockSetRefVersion();
        final mockGetRefVersion = MockGetRefVersion();

        // can publish ok
        when(
          () => mockCanPublishCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        // processing order A, then B
        final aDir = Directory(path.join(ticketDir.path, 'A'));
        final bDir = Directory(path.join(ticketDir.path, 'B'));
        when(
          () => mockSortedProcessingList.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(name: 'A', directory: aDir, pubspec: Pubspec('A')),
            Node(name: 'B', directory: bDir, pubspec: Pubspec('B')),
          ],
        );

        // unlocalize ok
        when(
          () => mockUnlocalizeRefs.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        // version of A known
        when(
          () => mockGetVersion.get(directory: aDir),
        ).thenAnswer((_) async => '1.2.3');
        when(
          () => mockGetVersion.get(directory: bDir),
        ).thenAnswer((_) async => '0.0.1');

        // B depends on A -> return non-null spec for B/A
        when(
          () => mockGetRefVersion.get(
            directory: bDir,
            ref: 'A',
          ),
        ).thenAnswer((_) async => '^any');
        // all other getRefVersion calls return null
        when(
          () => mockGetRefVersion.get(
            directory: any(named: 'directory'),
            ref: any(named: 'ref'),
          ),
        ).thenAnswer((_) async => null);

        // setRefVersion stub
        when(
          () => mockSetRefVersion.get(
            directory: any(named: 'directory'),
            ref: any(named: 'ref'),
            version: any(named: 'version'),
          ),
        ).thenAnswer((_) async {});

        // commit/push/merge/publish ok
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
            force: any(named: 'force'),
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
        when(
          () => mockGgDoPublish.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        // initial status
        for (final repo in ['A', 'B']) {
          final f = File(path.join(ticketDir.path, repo, '.kidney_status'))
            ..createSync(recursive: true);
          f.writeAsStringSync(
            jsonEncode({'status': StatusUtils.statusGitLocalized}),
          );
        }

        final runner = CommandRunner<void>('test', 'do publish ticket')
          ..addCommand(
            DoPublishCommand(
              ggLog: ggLog,
              ggDoMerge: mockGgDoMerge,
              ggDoPublish: mockGgDoPublish,
              ggDoCommit: mockGgDoCommit,
              ggDoPush: mockGgDoPush,
              unlocalizeRefs: mockUnlocalizeRefs,
              sortedProcessingList: mockSortedProcessingList,
              processRunner: mockProcessRunner.call,
              canPublishCommand: mockCanPublishCommand,
              getVersionCommand: mockGetVersion,
              setRefVersionCommand: mockSetRefVersion,
              getRefVersionCommand: mockGetRefVersion,
            ),
          );

        await runner.run([
          'publish',
          '--force',
          '--input',
          ticketDir.path,
        ]);

        // Verify setRefVersion was called for B with ref A and ^1.2.3
        verify(
          () => mockSetRefVersion.get(
            directory: bDir,
            ref: 'A',
            version: '^1.2.3',
          ),
        ).called(1);
      },
    );
  });
}

// Mock for ProcessRunner
class MockProcessRunner extends Mock {
  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  });
}
