// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:gg_publish/gg_publish.dart' as gg_publish;
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:test/test.dart';
import 'package:gg_multi/src/commands/can/publish.dart';
import 'package:gg_multi/src/commands/did/commit.dart';
import 'package:gg_multi/src/commands/do/push.dart';

import '../../rm_console_colors_helper.dart';

class MockGgCanCommit extends Mock implements gg.CanCommit {}

class MockGgCanMerge extends Mock implements gg.CanMerge {}

class MockGgMergeMainIntoFeat extends Mock
    implements gg_publish.MergeMainIntoFeat {}

class MockSortedProcessingList extends Mock implements SortedProcessingList {}

class MockDidCommitCommand extends Mock implements DidCommitCommand {}

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
        contains('⚠️ No repos in this ticket'),
      );
    });

    test('checks uncommitted changes and fails if found', () async {
      final mockGgCanCommit = MockGgCanCommit();
      final mockGgCanMerge = MockGgCanMerge();
      final mockGgMergeMainIntoFeat = MockGgMergeMainIntoFeat();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockDidCommitCommand = MockDidCommitCommand();
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
            manifest: DartPackageManifest(pubspec: Pubspec('A')),
          ),
          Node(
            name: 'B',
            directory: Directory(path.join(ticketDir.path, 'B')),
            manifest: DartPackageManifest(pubspec: Pubspec('B')),
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
            ggMergeMainIntoFeat: mockGgMergeMainIntoFeat,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            didCommitCommand: mockDidCommitCommand,
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
            'Uncommitted changes in:',
          ),
        ),
        isTrue,
      );
      expect(messages.any((m) => m.contains(' - A')), isTrue);
    });

    test(
        'executes did commit, merge main into feat, '
        'do push, and can merge successfully', () async {
      final mockGgCanCommit = MockGgCanCommit();
      final mockGgCanMerge = MockGgCanMerge();
      final mockGgMergeMainIntoFeat = MockGgMergeMainIntoFeat();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockDidCommitCommand = MockDidCommitCommand();
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
          ['status', '--porcelain'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      when(
        () => mockDidCommitCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgMergeMainIntoFeat.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {
        return;
      });

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
            ggMergeMainIntoFeat: mockGgMergeMainIntoFeat,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            didCommitCommand: mockDidCommitCommand,
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
        contains('✅ All repos can be published'),
      );
      verify(
        () => mockGgMergeMainIntoFeat.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).called(2);
      expect(
        messages.any((m) => m.contains('A:')),
        isTrue,
      );
      expect(
        messages.any((m) => m.contains('B:')),
        isTrue,
      );
    });

    test('fails on can merge check for specific repos', () async {
      final mockGgCanCommit = MockGgCanCommit();
      final mockGgCanMerge = MockGgCanMerge();
      final mockGgMergeMainIntoFeat = MockGgMergeMainIntoFeat();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockDidCommitCommand = MockDidCommitCommand();
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
          ['status', '--porcelain'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      when(
        () => mockDidCommitCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgMergeMainIntoFeat.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {
        return;
      });

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
            ggMergeMainIntoFeat: mockGgMergeMainIntoFeat,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            didCommitCommand: mockDidCommitCommand,
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
            '❌ Merge check failed in:',
          ),
        ),
        isTrue,
      );
      expect(messages.any((m) => m.contains(' - B')), isTrue);
    });

    test('fails when did commit throws exception', () async {
      final mockGgCanCommit = MockGgCanCommit();
      final mockGgCanMerge = MockGgCanMerge();
      final mockGgMergeMainIntoFeat = MockGgMergeMainIntoFeat();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockDidCommitCommand = MockDidCommitCommand();
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
          ['status', '--porcelain'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      when(
        () => mockDidCommitCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenThrow(Exception('Did commit failed'));

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
            ggMergeMainIntoFeat: mockGgMergeMainIntoFeat,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            didCommitCommand: mockDidCommitCommand,
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
            'gg_multi did commit failed: Exception: Did commit failed',
          ),
        ),
        isTrue,
      );
    });

    test('fails when merge main into feat throws exception', () async {
      final mockGgCanCommit = MockGgCanCommit();
      final mockGgCanMerge = MockGgCanMerge();
      final mockGgMergeMainIntoFeat = MockGgMergeMainIntoFeat();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockDidCommitCommand = MockDidCommitCommand();
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
          ['status', '--porcelain'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      when(
        () => mockDidCommitCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgMergeMainIntoFeat.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((invocation) {
        final repoDir = invocation.namedArguments[#directory] as Directory;
        if (path.basename(repoDir.path) == 'B') {
          throw Exception('Merge main into feat failed');
        }
        return Future.value();
      });

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
            ggMergeMainIntoFeat: mockGgMergeMainIntoFeat,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            didCommitCommand: mockDidCommitCommand,
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
            'gg merge main into feat failed for B in ticket '
            'TICKPB: Exception: Merge main into feat failed',
          ),
        ),
        isTrue,
      );
      verifyNever(
        () => mockDoPushCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      );
    });

    test('fails when do push throws exception', () async {
      final mockGgCanCommit = MockGgCanCommit();
      final mockGgCanMerge = MockGgCanMerge();
      final mockGgMergeMainIntoFeat = MockGgMergeMainIntoFeat();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockDidCommitCommand = MockDidCommitCommand();
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
          ['status', '--porcelain'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      when(
        () => mockDidCommitCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgMergeMainIntoFeat.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {
        return;
      });

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
            ggMergeMainIntoFeat: mockGgMergeMainIntoFeat,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            didCommitCommand: mockDidCommitCommand,
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
            'gg_multi do push failed: Exception: do push failed',
          ),
        ),
        isTrue,
      );
    });

    test(
      'uses quiet taskLog when verbose is false',
      () async {
        final mockGgCanCommit = MockGgCanCommit();
        final mockGgCanMerge = MockGgCanMerge();
        final mockGgMergeMainIntoFeat = MockGgMergeMainIntoFeat();
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockProcessRunner = MockProcessRunner();
        final mockDidCommitCommand = MockDidCommitCommand();
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
              manifest: DartPackageManifest(pubspec: Pubspec('A')),
            ),
            Node(
              name: 'B',
              directory: Directory(
                path.join(ticketDir.path, 'B'),
              ),
              manifest: DartPackageManifest(pubspec: Pubspec('B')),
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
          () => mockDidCommitCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockGgMergeMainIntoFeat.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {
          return;
        });

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
          ggMergeMainIntoFeat: mockGgMergeMainIntoFeat,
          sortedProcessingList: mockSortedProcessingList,
          processRunner: mockProcessRunner.call,
          didCommitCommand: mockDidCommitCommand,
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
            '✅ Running do push',
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
