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
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:test/test.dart';
import 'package:kidney_core/src/commands/can/publish.dart';
import 'package:kidney_core/src/commands/can/commit.dart';
import 'package:kidney_core/src/commands/do/push.dart';
import 'package:kidney_core/src/backend/status_utils.dart';

import '../../rm_console_colors_helper.dart';

class MockGgCanCommit extends Mock implements gg.CanCommit {}

class MockGgCanMerge extends Mock implements gg.CanMerge {}

class MockSortedProcessingList extends Mock implements SortedProcessingList {}

class MockCanCommitCommand extends Mock implements CanCommitCommand {}

class MockDoPushCommand extends Mock implements DoPushCommand {}

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
    tempDir = Directory.systemTemp.createTempSync(
      'can_publish_ticket_test_',
    );
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

  group('CanPublishCommand (ticket-wide)', () {
    test('fails outside any ticket folder', () async {
      final runner = CommandRunner<void>('test', 'can publish ticket')
        ..addCommand(
          CanPublishCommand(
            ggLog: ggLog,
          ),
        );
      await expectLater(
        () async => await runner.run(['publish', '--input', tempDir.path]),
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
      final runner = CommandRunner<void>('test', 'can publish ticket')
        ..addCommand(
          CanPublishCommand(
            ggLog: ggLog,
          ),
        );
      await runner.run(['publish', '--input', emptyTicket.path]);
      expect(
        messages,
        contains('⚠️ No repositories found in ticket EMPTY.'),
      );
    });

    test('checks status correctly and fails if not git-localized', () async {
      // Set status for A to wrong
      final statusFileA = File(
        path.join(ticketDir.path, 'A', '.kidney_status'),
      )..createSync(recursive: true);
      statusFileA.writeAsStringSync(jsonEncode({'status': 'wrong'}));
      // Set status for B to git-localized
      final statusFileB = File(
        path.join(ticketDir.path, 'B', '.kidney_status'),
      )..createSync(recursive: true);
      statusFileB.writeAsStringSync(
        jsonEncode({'status': StatusUtils.statusGitLocalized}),
      );

      final mockGgCanCommit = MockGgCanCommit();
      final mockGgCanMerge = MockGgCanMerge();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanCommitCommand = MockCanCommitCommand();
      final mockDoPushCommand = MockDoPushCommand();

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

      final runner = CommandRunner<void>('test', 'can publish ticket')
        ..addCommand(
          CanPublishCommand(
            ggLog: ggLog,
            ggCanCommit: mockGgCanCommit,
            ggCanMerge: mockGgCanMerge,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canCommitCommand: mockCanCommitCommand,
            doPushCommand: mockDoPushCommand,
          ),
        );
      await expectLater(
        () async => await runner.run([
          'publish',
          '--verbose',
          '--input',
          ticketDir.path,
        ]),
        throwsA(isA<Exception>()),
      );
      expect(
        messages.any(
          (m) => m.contains(
            'The following repos do not have '
            'the required status "git-localized":',
          ),
        ),
        isTrue,
      );
      expect(messages.any((m) => m.contains(' - A')), isTrue);
      expect(
        messages.any(
          (m) => m.contains(
            'Please execute kidney_core review before merging',
          ),
        ),
        isTrue,
      );
    });

    test('checks uncommitted changes and fails if found', () async {
      // Set status for all repos to git-localized
      for (final repoName in ['A', 'B']) {
        final statusFile = File(
          path.join(ticketDir.path, repoName, '.kidney_status'),
        )..createSync(recursive: true);
        statusFile.writeAsStringSync(
          jsonEncode({'status': StatusUtils.statusGitLocalized}),
        );
      }

      final mockGgCanCommit = MockGgCanCommit();
      final mockGgCanMerge = MockGgCanMerge();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanCommitCommand = MockCanCommitCommand();
      final mockDoPushCommand = MockDoPushCommand();

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

      // Simulate uncommitted changes in A
      when(
        () => mockProcessRunner(
          'git',
          ['status', '--porcelain'],
          workingDirectory: path.join(ticketDir.path, 'A'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, ' M file.txt', ''));
      when(
        () => mockProcessRunner(
          'git',
          ['status', '--porcelain'],
          workingDirectory: path.join(ticketDir.path, 'B'),
        ),
      ).thenAnswer((_) async => ProcessResult(2, 0, '', ''));

      final runner = CommandRunner<void>('test', 'can publish ticket')
        ..addCommand(
          CanPublishCommand(
            ggLog: ggLog,
            ggCanCommit: mockGgCanCommit,
            ggCanMerge: mockGgCanMerge,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canCommitCommand: mockCanCommitCommand,
            doPushCommand: mockDoPushCommand,
          ),
        );
      await expectLater(
        () async => await runner.run([
          'publish',
          '--verbose',
          '--input',
          ticketDir.path,
        ]),
        throwsA(isA<Exception>()),
      );
      expect(
        messages.any(
          (m) => m.contains(
            'Uncommitted changes found in the following repos:',
          ),
        ),
        isTrue,
      );
      expect(messages.any((m) => m.contains(' - A')), isTrue);
    });

    test('executes can commit, do push, and can merge successfully', () async {
      // Set status for all repos to git-localized
      for (final repoName in ['A', 'B']) {
        final statusFile = File(
          path.join(ticketDir.path, repoName, '.kidney_status'),
        )..createSync(recursive: true);
        statusFile.writeAsStringSync(
          jsonEncode({'status': StatusUtils.statusGitLocalized}),
        );
      }

      final mockGgCanCommit = MockGgCanCommit();
      final mockGgCanMerge = MockGgCanMerge();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanCommitCommand = MockCanCommitCommand();
      final mockDoPushCommand = MockDoPushCommand();

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
        () => mockProcessRunner(
          'git',
          ['status', '--porcelain'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      when(
        () => mockCanCommitCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockDoPushCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgCanMerge.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      final runner = CommandRunner<void>('test', 'can publish ticket')
        ..addCommand(
          CanPublishCommand(
            ggLog: ggLog,
            ggCanCommit: mockGgCanCommit,
            ggCanMerge: mockGgCanMerge,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canCommitCommand: mockCanCommitCommand,
            doPushCommand: mockDoPushCommand,
          ),
        );
      await runner.run([
        'publish',
        '--verbose',
        '--input',
        ticketDir.path,
      ]);
      expect(
        messages,
        contains('✅ All repositories in ticket TICKPB can be published.'),
      );
      expect(
        messages.any(
          (m) => m.contains(
            'Checking if A in ticket TICKPB can be merged...',
          ),
        ),
        isTrue,
      );
      expect(
        messages.any(
          (m) => m.contains(
            'Checking if B in ticket TICKPB can be merged...',
          ),
        ),
        isTrue,
      );
    });

    test('fails on can merge check for specific repos', () async {
      // Set status for all repos to git-localized
      for (final repoName in ['A', 'B']) {
        final statusFile = File(
          path.join(ticketDir.path, repoName, '.kidney_status'),
        )..createSync(recursive: true);
        statusFile.writeAsStringSync(
          jsonEncode({'status': StatusUtils.statusGitLocalized}),
        );
      }

      final mockGgCanCommit = MockGgCanCommit();
      final mockGgCanMerge = MockGgCanMerge();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanCommitCommand = MockCanCommitCommand();
      final mockDoPushCommand = MockDoPushCommand();

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
        () => mockProcessRunner(
          'git',
          ['status', '--porcelain'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      when(
        () => mockCanCommitCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockDoPushCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgCanMerge.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((invocation) {
        final repoDir = invocation.namedArguments[#directory] as Directory;
        if (path.basename(repoDir.path) == 'B') {
          throw Exception('Merge check failed for B');
        }
        return Future.value();
      });

      final runner = CommandRunner<void>('test', 'can publish ticket')
        ..addCommand(
          CanPublishCommand(
            ggLog: ggLog,
            ggCanCommit: mockGgCanCommit,
            ggCanMerge: mockGgCanMerge,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canCommitCommand: mockCanCommitCommand,
            doPushCommand: mockDoPushCommand,
          ),
        );
      await expectLater(
        () async => await runner.run([
          'publish',
          '--verbose',
          '--input',
          ticketDir.path,
        ]),
        throwsA(isA<Exception>()),
      );
      expect(
        messages.any(
          (m) => m.contains(
            '❌ Cannot merge B: Exception: Merge check failed for B',
          ),
        ),
        isTrue,
      );
      expect(
        messages.any(
          (m) => m.contains(
            '❌ Failed to check merge for the '
            'following repositories in ticket TICKPB:',
          ),
        ),
        isTrue,
      );
      expect(messages.any((m) => m.contains(' - B')), isTrue);
    });

    test('fails when can commit throws exception', () async {
      // Set status for all repos to git-localized
      for (final repoName in ['A', 'B']) {
        final statusFile = File(
          path.join(ticketDir.path, repoName, '.kidney_status'),
        )..createSync(recursive: true);
        statusFile.writeAsStringSync(
          jsonEncode({'status': StatusUtils.statusGitLocalized}),
        );
      }

      final mockGgCanCommit = MockGgCanCommit();
      final mockGgCanMerge = MockGgCanMerge();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanCommitCommand = MockCanCommitCommand();
      final mockDoPushCommand = MockDoPushCommand();

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
        () => mockProcessRunner(
          'git',
          ['status', '--porcelain'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      when(
        () => mockCanCommitCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenThrow(Exception('Can commit failed'));

      when(
        () => mockDoPushCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgCanMerge.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      final runner = CommandRunner<void>('test', 'can publish ticket')
        ..addCommand(
          CanPublishCommand(
            ggLog: ggLog,
            ggCanCommit: mockGgCanCommit,
            ggCanMerge: mockGgCanMerge,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canCommitCommand: mockCanCommitCommand,
            doPushCommand: mockDoPushCommand,
          ),
        );
      await expectLater(
        () async => await runner.run([
          'publish',
          '--verbose',
          '--input',
          ticketDir.path,
        ]),
        throwsA(isA<Exception>()),
      );
      expect(
        messages.any(
          (m) => m.contains(
            'kidney_core can commit failed: Exception: Can commit failed',
          ),
        ),
        isTrue,
      );
    });

    test('fails when do push throws exception', () async {
      // Set status for all repos to git-localized
      for (final repoName in ['A', 'B']) {
        final statusFile = File(
          path.join(ticketDir.path, repoName, '.kidney_status'),
        )..createSync(recursive: true);
        statusFile.writeAsStringSync(
          jsonEncode({'status': StatusUtils.statusGitLocalized}),
        );
      }

      final mockGgCanCommit = MockGgCanCommit();
      final mockGgCanMerge = MockGgCanMerge();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanCommitCommand = MockCanCommitCommand();
      final mockDoPushCommand = MockDoPushCommand();

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
        () => mockProcessRunner(
          'git',
          ['status', '--porcelain'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      when(
        () => mockCanCommitCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockDoPushCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenThrow(Exception('do push failed'));

      when(
        () => mockGgCanMerge.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      final runner = CommandRunner<void>('test', 'can publish ticket')
        ..addCommand(
          CanPublishCommand(
            ggLog: ggLog,
            ggCanCommit: mockGgCanCommit,
            ggCanMerge: mockGgCanMerge,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canCommitCommand: mockCanCommitCommand,
            doPushCommand: mockDoPushCommand,
          ),
        );
      await expectLater(
        () async => await runner.run([
          'publish',
          '--verbose',
          '--input',
          ticketDir.path,
        ]),
        throwsA(isA<Exception>()),
      );
      expect(
        messages.any(
          (m) => m.contains(
            'kidney_core do push failed: Exception: do push failed',
          ),
        ),
        isTrue,
      );
      // Ensure can merge is not called
      verifyNever(
        () => mockGgCanMerge.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      );
    });

    test(
      'uses quiet taskLog when verbose is false',
      () async {
        // Prepare git-localized status
        for (final name in ['A', 'B']) {
          final statusFile = File(
            path.join(ticketDir.path, name, '.kidney_status'),
          )..createSync(recursive: true);
          statusFile.writeAsStringSync(
            jsonEncode(
              {
                'status': StatusUtils.statusGitLocalized,
              },
            ),
          );
        }

        final mockGgCanCommit = MockGgCanCommit();
        final mockGgCanMerge = MockGgCanMerge();
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockProcessRunner = MockProcessRunner();
        final mockCanCommitCommand = MockCanCommitCommand();
        final mockDoPushCommand = MockDoPushCommand();

        when(
          () => mockSortedProcessingList.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(
              name: 'A',
              directory: Directory(
                path.join(ticketDir.path, 'A'),
              ),
              pubspec: Pubspec('A'),
            ),
            Node(
              name: 'B',
              directory: Directory(
                path.join(ticketDir.path, 'B'),
              ),
              pubspec: Pubspec('B'),
            ),
          ],
        );

        when(
          () => mockProcessRunner(
            'git',
            ['status', '--porcelain'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer(
          (_) async => ProcessResult(1, 0, '', ''),
        );

        when(
          () => mockCanCommitCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockDoPushCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockGgCanMerge.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        final localMessages = <String>[];
        void localLog(String msg) => localMessages.add(rmConsoleColors(msg));

        final command = CanPublishCommand(
          ggLog: localLog,
          ggCanCommit: mockGgCanCommit,
          ggCanMerge: mockGgCanMerge,
          sortedProcessingList: mockSortedProcessingList,
          processRunner: mockProcessRunner.call,
          canCommitCommand: mockCanCommitCommand,
          doPushCommand: mockDoPushCommand,
        );

        await command.get(
          directory: ticketDir,
          ggLog: localLog,
          verbose: false,
        );

        expect(
          localMessages.last,
          contains(
            '✅ can merge?',
          ),
        );
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
