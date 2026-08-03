// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
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

class MockGgCanCommit extends Mock implements gg.CanCommit {}

class MockGgCanMerge extends Mock implements gg.CanMerge {}

class MockGgCanPublish extends Mock implements gg.CanPublish {}

class MockGgNpmLoggedIn extends Mock implements gg.NpmLoggedIn {}

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

  void ggLog(String msg) => messages.add(rmC(msg));

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

      final mockGgCanPublish = MockGgCanPublish();
      when(
        () => mockGgCanPublish.exec(
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
            ggCanPublish: mockGgCanPublish,
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
        contains('✓ All repos can be published'),
      );
      verify(
        () => mockGgCanPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).called(2);
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
            '✗ Cannot merge B: Exception: Merge check failed for B',
          ),
        ),
        isTrue,
      );
      expect(
        messages.any(
          (m) => m.contains(
            '✗ Merge check failed in:',
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

    test('fails when a repo is not publish-ready (e.g. not logged in to npm)',
        () async {
      final mockGgCanCommit = MockGgCanCommit();
      final mockGgCanMerge = MockGgCanMerge();
      final mockGgCanPublish = MockGgCanPublish();
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

      // Repo B is not logged in to npm.
      when(
        () => mockGgCanPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((invocation) {
        final repoDir = invocation.namedArguments[#directory] as Directory;
        if (path.basename(repoDir.path) == 'B') {
          throw Exception('Not logged in to the npm registry');
        }
        return Future.value();
      });

      final runner = CommandRunner<void>('test', 'can publish ticket')
        ..addCommand(
          CanPublishCommand(
            ggLog: ggLog,
            ggCanCommit: mockGgCanCommit,
            ggCanMerge: mockGgCanMerge,
            ggCanPublish: mockGgCanPublish,
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
        messages.any((m) => m.contains('✗ Cannot publish B')),
        isTrue,
      );
      expect(
        messages.any(
          (m) => m.contains('Not logged in to the npm registry'),
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

        final mockGgCanPublish = MockGgCanPublish();
        when(
          () => mockGgCanPublish.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        final localMessages = <String>[];
        void localLog(String msg) => localMessages.add(rmC(msg));

        final command = CanPublishCommand(
          ggLog: localLog,
          ggCanCommit: mockGgCanCommit,
          ggCanMerge: mockGgCanMerge,
          ggCanPublish: mockGgCanPublish,
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

        // The per-repo "Can publish?" check is now the final status line.
        expect(
          localMessages.last,
          contains(
            '✓ Can publish?',
          ),
        );
      },
    );
  });

  // ...........................................................................
  group('CanPublishCommand (per repo gate)', () {
    late MockGgCanMerge mockGgCanMerge;
    late MockGgCanPublish mockGgCanPublish;
    late MockGgNpmLoggedIn mockGgNpmLoggedIn;
    late MockGgMergeMainIntoFeat mockGgMergeMainIntoFeat;
    late MockSortedProcessingList mockSortedProcessingList;
    late MockProcessRunner mockProcessRunner;
    late MockDidCommitCommand mockDidCommitCommand;
    late MockDoPushCommand mockDoPushCommand;

    /// A command whose collaborators all succeed, so a test only has to
    /// override the one it is about.
    CanPublishCommand command() => CanPublishCommand(
          ggLog: ggLog,
          ggCanMerge: mockGgCanMerge,
          ggCanPublish: mockGgCanPublish,
          ggNpmLoggedIn: mockGgNpmLoggedIn,
          ggMergeMainIntoFeat: mockGgMergeMainIntoFeat,
          sortedProcessingList: mockSortedProcessingList,
          processRunner: mockProcessRunner.call,
          didCommitCommand: mockDidCommitCommand,
          doPushCommand: mockDoPushCommand,
        );

    Directory repoDir(String name) =>
        Directory(path.join(ticketDir.path, name));

    setUp(() {
      mockGgCanMerge = MockGgCanMerge();
      mockGgCanPublish = MockGgCanPublish();
      mockGgNpmLoggedIn = MockGgNpmLoggedIn();
      mockGgMergeMainIntoFeat = MockGgMergeMainIntoFeat();
      mockSortedProcessingList = MockSortedProcessingList();
      mockProcessRunner = MockProcessRunner();
      mockDidCommitCommand = MockDidCommitCommand();
      mockDoPushCommand = MockDoPushCommand();

      when(
        () => mockSortedProcessingList.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer(
        (_) async => [
          Node(
            name: 'A',
            directory: repoDir('A'),
            manifest: DartPackageManifest(pubspec: Pubspec('A')),
          ),
          Node(
            name: 'B',
            directory: repoDir('B'),
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

      for (final stub in [
        () => mockDidCommitCommand.exec(
              directory: any(named: 'directory'),
              ggLog: any(named: 'ggLog'),
            ),
        () => mockGgMergeMainIntoFeat.exec(
              directory: any(named: 'directory'),
              ggLog: any(named: 'ggLog'),
            ),
        () => mockDoPushCommand.exec(
              directory: any(named: 'directory'),
              ggLog: any(named: 'ggLog'),
            ),
        () => mockGgCanMerge.exec(
              directory: any(named: 'directory'),
              ggLog: any(named: 'ggLog'),
            ),
        () => mockGgCanPublish.exec(
              directory: any(named: 'directory'),
              ggLog: any(named: 'ggLog'),
            ),
        () => mockGgNpmLoggedIn.exec(
              directory: any(named: 'directory'),
              ggLog: any(named: 'ggLog'),
            ),
      ]) {
        when(stub).thenAnswer((_) async {});
      }
    });

    group('checkTicket(includeCanPublish: false)', () {
      test('runs the ticket wide steps but not gg can publish', () async {
        await command().checkTicket(
          directory: ticketDir,
          ggLog: ggLog,
          verbose: true,
          includeCanPublish: false,
        );

        verify(
          () => mockGgCanMerge.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).called(2);
        verify(
          () => mockDoPushCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).called(1);

        // The deferred step must not even print its status line.
        verifyNever(
          () => mockGgCanPublish.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        );
        expect(messages.any((m) => m.contains('Can merge?')), isTrue);
        expect(messages.any((m) => m.contains('Can publish?')), isFalse);
      });

      test('still checks the npm login of every repo', () async {
        await command().checkTicket(
          directory: ticketDir,
          ggLog: ggLog,
          verbose: true,
          includeCanPublish: false,
        );

        verify(
          () => mockGgNpmLoggedIn.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).called(2);
        expect(messages.any((m) => m.contains('Logged in to npm?')), isTrue);
      });
    });

    test('get() still runs the complete check', () async {
      final runner = CommandRunner<void>('test', 'can publish ticket')
        ..addCommand(command());
      await runner.run(['publish', '--verbose', '--input', ticketDir.path]);

      verify(
        () => mockGgCanPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).called(2);
      verify(
        () => mockGgNpmLoggedIn.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).called(2);
      expect(messages, contains('✓ All repos can be published'));
    });

    test('throws when a repo is not logged in to npm', () async {
      when(
        () => mockGgNpmLoggedIn.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((invocation) {
        final dir = invocation.namedArguments[#directory] as Directory;
        if (path.basename(dir.path) == 'B') {
          throw Exception('Not logged in to the npm registry');
        }
        return Future.value();
      });

      await expectLater(
        () => command().checkTicket(
          directory: ticketDir,
          ggLog: ggLog,
          verbose: true,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Not logged in to npm: B ('),
          ),
        ),
      );
      expect(
        messages.any((m) => m.contains('✗ Not logged in to npm for B')),
        isTrue,
      );

      // The npm sweep runs before `Can publish?`, so that step never starts.
      verifyNever(
        () => mockGgCanPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      );
    });

    group('checkRepo()', () {
      test('passes for a publish-ready repo', () async {
        final dir = repoDir('A');
        await command().checkRepo(directory: dir, ggLog: ggLog);

        verify(
          () => mockGgCanPublish.exec(
            directory: dir,
            ggLog: any(named: 'ggLog'),
          ),
        ).called(1);
        expect(messages.join('\n'), '\nA:');
      });

      test('throws the ticket wide message for one repo', () async {
        when(
          () => mockGgCanPublish.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenThrow(Exception('pana failed'));

        await expectLater(
          () => command().checkRepo(directory: repoDir('B'), ggLog: ggLog),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              'Exception: Cannot publish: B (Exception: pana failed)',
            ),
          ),
        );
        expect(
          messages,
          contains('✗ Cannot publish B: Exception: pana failed'),
        );
      });

      test('works outside a ticket folder', () async {
        // It takes a repository, so it must not look for a ticket around it.
        final loneRepo = Directory(path.join(tempDir.path, 'lone'))
          ..createSync();
        await command().checkRepo(directory: loneRepo, ggLog: ggLog);

        verify(
          () => mockGgCanPublish.exec(
            directory: loneRepo,
            ggLog: any(named: 'ggLog'),
          ),
        ).called(1);
      });
    });
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
