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
import 'package:kidney_core/src/backend/pub_dev_checker.dart';
import 'package:kidney_core/src/commands/do/push.dart';
import 'package:kidney_core/src/commands/do/review.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:test/test.dart';
import 'package:kidney_core/src/commands/do/publish.dart';
import 'package:kidney_core/src/commands/can/publish.dart';
import 'package:kidney_core/src/backend/status_utils.dart';

import '../../rm_console_colors_helper.dart';

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

/// Mock for DoPushCommand
class MockDoPushCommand extends Mock implements DoPushCommand {}

/// Mock for DoReviewCommand
class MockDoReviewCommand extends Mock implements DoReviewCommand {}

/// Mock for UnlocalizeRefs
class MockUnlocalizeRefs extends Mock implements ChangeRefsToPubDev {}

/// Mocks for version/ref helpers
class MockGetVersion extends Mock implements GetVersion {}

class MockSetRefVersion extends Mock implements SetRefVersion {}

class MockGetRefVersion extends Mock implements GetRefVersion {}

class MockPubDevChecker extends Mock implements PubDevChecker {}

class FakeDirectory extends Fake implements Directory {}

class MockDirectory extends Mock implements Directory {}

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
      final mockDoReviewCommand = MockDoReviewCommand();
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockSortedProcessingList = MockSortedProcessingList();

      when(
        () => mockDoReviewCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          verbose: any(named: 'verbose'),
        ),
      ).thenAnswer((_) async {});

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
      ).thenAnswer((_) async => <Node>[]);

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            doReviewCommand: mockDoReviewCommand,
            canPublishCommand: mockCanPublishCommand,
            sortedProcessingList: mockSortedProcessingList,
            confirmDeleteTicket: (_) => false,
          ),
        );
      await runner.run(['publish', '--input', emptyTicket.path]);
      expect(
        messages,
        contains('⚠️ No repositories found in ticket EMPTY.'),
      );
    });

    test('runs kidney_core do review before kidney_core can publish', () async {
      final mockDoReviewCommand = MockDoReviewCommand();
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockSortedProcessingList = MockSortedProcessingList();

      when(
        () => mockDoReviewCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          verbose: any(named: 'verbose'),
        ),
      ).thenAnswer((_) async {});

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
      ).thenAnswer((_) async => <Node>[]);

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            doReviewCommand: mockDoReviewCommand,
            canPublishCommand: mockCanPublishCommand,
            sortedProcessingList: mockSortedProcessingList,
            confirmDeleteTicket: (_) => false,
          ),
        );

      await runner.run([
        'publish',
        '--input',
        ticketDir.path,
      ]);

      verifyInOrder([
        () => mockDoReviewCommand.exec(
              directory: any(named: 'directory'),
              ggLog: any(named: 'ggLog'),
              verbose: any(named: 'verbose'),
            ),
        () => mockCanPublishCommand.exec(
              directory: any(named: 'directory'),
              ggLog: any(named: 'ggLog'),
            ),
      ]);
    });

    test('aborts if do review fails before can publish', () async {
      final mockDoReviewCommand = MockDoReviewCommand();
      final mockCanPublishCommand = MockCanPublishCommand();

      when(
        () => mockDoReviewCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          verbose: any(named: 'verbose'),
        ),
      ).thenThrow(Exception('review failed'));

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            doReviewCommand: mockDoReviewCommand,
            canPublishCommand: mockCanPublishCommand,
            confirmDeleteTicket: (_) => false,
          ),
        );

      await expectLater(
        () async => await runner.run([
          'publish',
          '--input',
          ticketDir.path,
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('kidney_core do review failed: Exception: review failed'),
          ),
        ),
      );

      verifyNever(
        () => mockCanPublishCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      );
    });

    test('publishes all repos successfully and deletes them from ticket',
        () async {
      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockDoReviewCommand = MockDoReviewCommand();
      final mockGetVersion = MockGetVersion();
      final mockSetRefVersion = MockSetRefVersion();
      final mockGetRefVersion = MockGetRefVersion();
      final mockPubDevChecker = MockPubDevChecker();

      when(
        () => mockDoReviewCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          verbose: any(named: 'verbose'),
        ),
      ).thenAnswer((_) async {});

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
            manifest: DartPackageManifest(pubspec: Pubspec('A')),
          ),
          Node(
            name: 'B',
            directory: Directory(path.join(ticketDir.path, 'B')),
            manifest: DartPackageManifest(
              pubspec: Pubspec(
                'B',
                dependencies: <String, Dependency>{
                  'A': HostedDependency(
                    version: VersionConstraint.parse('^1.0.0'),
                  ),
                },
              ),
            ),
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
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
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

      when(
        () => mockPubDevChecker.getPackagePublishInfo(
          packageName: any(named: 'packageName'),
        ),
      ).thenAnswer(
        (invocation) async {
          final packageName = invocation.namedArguments[#packageName] as String;
          return PackagePublishInfo(
            packageName: packageName,
            waitsForPubDev: true,
          );
        },
      );

      when(
        () => mockPubDevChecker.waitUntilVersionAvailable(
          packageName: any(named: 'packageName'),
          version: any(named: 'version'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockProcessRunner(
          'git',
          ['push', 'origin', '--delete', 'TICKPB'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            ggDoPublish: mockGgDoPublish,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            unlocalizeRefs: mockUnlocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            doReviewCommand: mockDoReviewCommand,
            getVersionCommand: mockGetVersion,
            setRefVersionCommand: mockSetRefVersion,
            getRefVersionCommand: mockGetRefVersion,
            pubDevChecker: mockPubDevChecker,
            editMessage: (initialMessage) async => initialMessage,
            confirmDeleteTicket: (_) => true,
          ),
        );
      await runner.run([
        'publish',
        '--input',
        ticketDir.path,
        '--verbose',
      ]);

      expect(
        messages,
        contains(
          '✅ All repositories in ticket TICKPB published successfully.',
        ),
      );
      expect(
        messages.any((m) => m.contains('Publishing A')),
        isTrue,
      );
      expect(
        messages.any((m) => m.contains('Publishing B')),
        isTrue,
      );

      // Repositories must be deleted from ticket workspace after publish.
      expect(
        Directory(path.join(ticketDir.path, 'A')).existsSync(),
        isFalse,
      );
      expect(
        Directory(path.join(ticketDir.path, 'B')).existsSync(),
        isFalse,
      );
    });

    test('uses explicit get message as initial value for interactive edit',
        () async {
      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockDoReviewCommand = MockDoReviewCommand();
      final mockGetVersion = MockGetVersion();
      final mockSetRefVersion = MockSetRefVersion();
      final mockGetRefVersion = MockGetRefVersion();
      final mockPubDevChecker = MockPubDevChecker();
      final editedMessages = <String>[];

      when(
        () => mockDoReviewCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          verbose: any(named: 'verbose'),
        ),
      ).thenAnswer((_) async {});

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
            manifest: DartPackageManifest(pubspec: Pubspec('A')),
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
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
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
      when(
        () => mockPubDevChecker.getPackagePublishInfo(
          packageName: any(named: 'packageName'),
        ),
      ).thenAnswer(
        (_) async => const PackagePublishInfo(
          packageName: 'A',
          waitsForPubDev: false,
        ),
      );

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            ggDoPublish: mockGgDoPublish,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            unlocalizeRefs: mockUnlocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            doReviewCommand: mockDoReviewCommand,
            getVersionCommand: mockGetVersion,
            setRefVersionCommand: mockSetRefVersion,
            getRefVersionCommand: mockGetRefVersion,
            pubDevChecker: mockPubDevChecker,
            editMessage: (initialMessage) async {
              editedMessages.add(initialMessage);
              return 'edited explicit message';
            },
            confirmDeleteTicket: (_) => false,
          ),
        );

      await runner.run([
        'publish',
        '--input',
        ticketDir.path,
        '--message',
        'explicit message',
      ]);

      expect(editedMessages, equals(<String>['explicit message']));
      verify(
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: 'edited explicit message',
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
        ),
      ).called(1);
    });

    test('uses ticket description as initial value when message is null',
        () async {
      File(path.join(ticketDir.path, '.ticket')).writeAsStringSync(
        jsonEncode(
          <String, String>{
            'issue_id': 'TICKPB',
            'description': 'ticket description',
          },
        ),
      );

      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockDoReviewCommand = MockDoReviewCommand();
      final mockGetVersion = MockGetVersion();
      final mockSetRefVersion = MockSetRefVersion();
      final mockGetRefVersion = MockGetRefVersion();
      final mockPubDevChecker = MockPubDevChecker();
      final editedMessages = <String>[];

      when(
        () => mockDoReviewCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          verbose: any(named: 'verbose'),
        ),
      ).thenAnswer((_) async {});

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
            manifest: DartPackageManifest(pubspec: Pubspec('A')),
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
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
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
      when(
        () => mockPubDevChecker.getPackagePublishInfo(
          packageName: any(named: 'packageName'),
        ),
      ).thenAnswer(
        (_) async => const PackagePublishInfo(
          packageName: 'A',
          waitsForPubDev: false,
        ),
      );

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            ggDoPublish: mockGgDoPublish,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            unlocalizeRefs: mockUnlocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            doReviewCommand: mockDoReviewCommand,
            getVersionCommand: mockGetVersion,
            setRefVersionCommand: mockSetRefVersion,
            getRefVersionCommand: mockGetRefVersion,
            pubDevChecker: mockPubDevChecker,
            editMessage: (initialMessage) async {
              editedMessages.add(initialMessage);
              return 'edited ticket message';
            },
            confirmDeleteTicket: (_) => false,
          ),
        );

      await runner.run([
        'publish',
        '--input',
        ticketDir.path,
      ]);

      expect(editedMessages, equals(<String>['ticket description']));
      verify(
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: 'edited ticket message',
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
        ),
      ).called(1);
    });

    test('does not wait for dependency with publish_to none', () async {
      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockDoReviewCommand = MockDoReviewCommand();
      final mockGetVersion = MockGetVersion();
      final mockSetRefVersion = MockSetRefVersion();
      final mockGetRefVersion = MockGetRefVersion();
      final mockPubDevChecker = MockPubDevChecker();

      final aDir = Directory(path.join(ticketDir.path, 'A'));
      final bDir = Directory(path.join(ticketDir.path, 'B'));

      when(
        () => mockDoReviewCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          verbose: any(named: 'verbose'),
        ),
      ).thenAnswer((_) async {});

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
            directory: aDir,
            manifest: DartPackageManifest(pubspec: Pubspec('A')),
          ),
          Node(
            name: 'B',
            directory: bDir,
            manifest: DartPackageManifest(
              pubspec: Pubspec(
                'B',
                dependencies: <String, Dependency>{
                  'A': HostedDependency(
                    version: VersionConstraint.parse('^1.0.0'),
                  ),
                },
              ),
            ),
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
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
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

      when(
        () => mockPubDevChecker.getPackagePublishInfo(packageName: 'A'),
      ).thenAnswer(
        (_) async => const PackagePublishInfo(
          packageName: 'A',
          waitsForPubDev: false,
        ),
      );
      when(
        () => mockPubDevChecker.getPackagePublishInfo(packageName: 'B'),
      ).thenAnswer(
        (_) async => const PackagePublishInfo(
          packageName: 'B',
          waitsForPubDev: true,
        ),
      );

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            ggDoPublish: mockGgDoPublish,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            unlocalizeRefs: mockUnlocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            doReviewCommand: mockDoReviewCommand,
            getVersionCommand: mockGetVersion,
            setRefVersionCommand: mockSetRefVersion,
            getRefVersionCommand: mockGetRefVersion,
            pubDevChecker: mockPubDevChecker,
            editMessage: (initialMessage) async => initialMessage,
            confirmDeleteTicket: (_) => false,
          ),
        );

      await runner.run([
        'publish',
        '--input',
        ticketDir.path,
      ]);

      verifyNever(
        () => mockPubDevChecker.waitUntilVersionAvailable(
          packageName: any(named: 'packageName'),
          version: any(named: 'version'),
          ggLog: any(named: 'ggLog'),
        ),
      );
    });

    test('aborts if can publish fails', () async {
      final mockGgDoPublish = MockGgDoPublish();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockDoReviewCommand = MockDoReviewCommand();
      final mockGetVersion = MockGetVersion();
      final mockSetRefVersion = MockSetRefVersion();
      final mockGetRefVersion = MockGetRefVersion();
      final mockPubDevChecker = MockPubDevChecker();

      when(
        () => mockDoReviewCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          verbose: any(named: 'verbose'),
        ),
      ).thenAnswer((_) async {});

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
            ggDoPublish: mockGgDoPublish,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            doReviewCommand: mockDoReviewCommand,
            getVersionCommand: mockGetVersion,
            setRefVersionCommand: mockSetRefVersion,
            getRefVersionCommand: mockGetRefVersion,
            pubDevChecker: mockPubDevChecker,
            editMessage: (initialMessage) async => initialMessage,
            confirmDeleteTicket: (_) => false,
          ),
        );
      await expectLater(
        () async => await runner.run(['publish', '--input', ticketDir.path]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('kidney_core can publish failed:'),
          ),
        ),
      );
    });

    test('aborts on gg do publish failure for specific repo and keeps folder',
        () async {
      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockDoReviewCommand = MockDoReviewCommand();
      final mockGetVersion = MockGetVersion();
      final mockSetRefVersion = MockSetRefVersion();
      final mockGetRefVersion = MockGetRefVersion();
      final mockPubDevChecker = MockPubDevChecker();

      when(
        () => mockDoReviewCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          verbose: any(named: 'verbose'),
        ),
      ).thenAnswer((_) async {});

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
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
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
      when(
        () => mockPubDevChecker.getPackagePublishInfo(
          packageName: any(named: 'packageName'),
        ),
      ).thenAnswer(
        (invocation) async {
          final packageName = invocation.namedArguments[#packageName] as String;
          return PackagePublishInfo(
            packageName: packageName,
            waitsForPubDev: true,
          );
        },
      );
      when(
        () => mockPubDevChecker.waitUntilVersionAvailable(
          packageName: any(named: 'packageName'),
          version: any(named: 'version'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      // Set initial status to git-localized for each repo so we can see
      // the transition to merged for A.
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
            ggDoPublish: mockGgDoPublish,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            unlocalizeRefs: mockUnlocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            doReviewCommand: mockDoReviewCommand,
            getVersionCommand: mockGetVersion,
            setRefVersionCommand: mockSetRefVersion,
            getRefVersionCommand: mockGetRefVersion,
            pubDevChecker: mockPubDevChecker,
            editMessage: (initialMessage) async => initialMessage,
            confirmDeleteTicket: (_) => true,
          ),
        );
      await expectLater(
        () async => await runner.run([
          'publish',
          '--input',
          ticketDir.path,
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Exception: Publish failed for B'),
          ),
        ),
      );

      // Repositories should still exist in
      // ticket workspace after failed publish attempt.
      expect(
        Directory(path.join(ticketDir.path, 'A')).existsSync(),
        isTrue,
      );
      expect(
        Directory(path.join(ticketDir.path, 'B')).existsSync(),
        isTrue,
      );
    });

    test('aborts on unlocalize refs failure for specific repos', () async {
      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockDoReviewCommand = MockDoReviewCommand();
      final mockGetVersion = MockGetVersion();
      final mockSetRefVersion = MockSetRefVersion();
      final mockGetRefVersion = MockGetRefVersion();
      final mockPubDevChecker = MockPubDevChecker();

      when(
        () => mockDoReviewCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          verbose: any(named: 'verbose'),
        ),
      ).thenAnswer((_) async {});

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
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
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
      when(
        () => mockPubDevChecker.getPackagePublishInfo(
          packageName: any(named: 'packageName'),
        ),
      ).thenAnswer(
        (invocation) async {
          final packageName = invocation.namedArguments[#packageName] as String;
          return PackagePublishInfo(
            packageName: packageName,
            waitsForPubDev: true,
          );
        },
      );
      when(
        () => mockPubDevChecker.waitUntilVersionAvailable(
          packageName: any(named: 'packageName'),
          version: any(named: 'version'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      // Set initial status to git-localized for each repo so we can see
      // the transition to merged for A.
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
            ggDoPublish: mockGgDoPublish,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            unlocalizeRefs: mockUnlocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            doReviewCommand: mockDoReviewCommand,
            getVersionCommand: mockGetVersion,
            setRefVersionCommand: mockSetRefVersion,
            getRefVersionCommand: mockGetRefVersion,
            pubDevChecker: mockPubDevChecker,
            editMessage: (initialMessage) async => initialMessage,
            confirmDeleteTicket: (_) => true,
          ),
        );
      await expectLater(
        () async => await runner.run([
          'publish',
          '--input',
          ticketDir.path,
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Failed to unlocalize refs for B: '
                'Exception: Unlocalize failed for B'),
          ),
        ),
      );
    });

    test('aborts when GetVersion throws', () async {
      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockDoReviewCommand = MockDoReviewCommand();
      final mockGetVersion = MockGetVersion();
      final mockSetRefVersion = MockSetRefVersion();
      final mockGetRefVersion = MockGetRefVersion();
      final mockPubDevChecker = MockPubDevChecker();

      when(
        () => mockDoReviewCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          verbose: any(named: 'verbose'),
        ),
      ).thenAnswer((_) async {});

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
            manifest: DartPackageManifest(pubspec: Pubspec('A')),
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
        () => mockGetVersion.get(
          directory: any(named: 'directory'),
        ),
      ).thenThrow(Exception('version read failed'));

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
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockPubDevChecker.getPackagePublishInfo(
          packageName: any(named: 'packageName'),
        ),
      ).thenAnswer(
        (invocation) async {
          final packageName = invocation.namedArguments[#packageName] as String;
          return PackagePublishInfo(
            packageName: packageName,
            waitsForPubDev: true,
          );
        },
      );

      final statusFileA = File(path.join(ticketDir.path, 'A', '.kidney_status'))
        ..createSync(recursive: true);
      statusFileA.writeAsStringSync(
        jsonEncode({'status': StatusUtils.statusGitLocalized}),
      );

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            ggDoPublish: mockGgDoPublish,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            unlocalizeRefs: mockUnlocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            doReviewCommand: mockDoReviewCommand,
            getVersionCommand: mockGetVersion,
            setRefVersionCommand: mockSetRefVersion,
            getRefVersionCommand: mockGetRefVersion,
            pubDevChecker: mockPubDevChecker,
            editMessage: (initialMessage) async => initialMessage,
            confirmDeleteTicket: (_) => true,
          ),
        );

      await expectLater(
        () async => await runner.run([
          'publish',
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
        final mockGgDoPublish = MockGgDoPublish();
        final mockGgDoCommit = MockGgDoCommit();
        final mockGgDoPush = MockGgDoPush();
        final mockUnlocalizeRefs = MockUnlocalizeRefs();
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockProcessRunner = MockProcessRunner();
        final mockCanPublishCommand = MockCanPublishCommand();
        final mockDoReviewCommand = MockDoReviewCommand();
        final mockGetVersion = MockGetVersion();
        final mockSetRefVersion = MockSetRefVersion();
        final mockGetRefVersion = MockGetRefVersion();
        final mockPubDevChecker = MockPubDevChecker();

        when(
          () => mockDoReviewCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            verbose: any(named: 'verbose'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockCanPublishCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        final aDir = Directory(path.join(ticketDir.path, 'A'));
        final bDir = Directory(path.join(ticketDir.path, 'B'));
        when(
          () => mockSortedProcessingList.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(
              name: 'A',
              directory: aDir,
              manifest: DartPackageManifest(pubspec: Pubspec('A')),
            ),
            Node(
              name: 'B',
              directory: bDir,
              manifest: DartPackageManifest(pubspec: Pubspec('B')),
            ),
          ],
        );

        when(
          () => mockUnlocalizeRefs.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(() => mockGetVersion.get(directory: aDir))
            .thenAnswer((_) async => '1.2.3');
        when(() => mockGetVersion.get(directory: bDir))
            .thenAnswer((_) async => '0.0.1');

        // General stub must be registered before the specific one so that
        // the specific stub for (bDir, 'A') wins. Mocktail uses the
        // last registered matching stub.
        when(
          () => mockGetRefVersion.get(
            directory: any(named: 'directory'),
            ref: any(named: 'ref'),
          ),
        ).thenAnswer((_) async => null);

        when(
          () => mockGetRefVersion.get(
            directory: bDir,
            ref: 'A',
          ),
        ).thenAnswer((_) async => '^any');

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
          () => mockGgDoPublish.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => mockPubDevChecker.getPackagePublishInfo(
            packageName: any(named: 'packageName'),
          ),
        ).thenAnswer(
          (invocation) async {
            final packageName =
                invocation.namedArguments[#packageName] as String;
            return PackagePublishInfo(
              packageName: packageName,
              waitsForPubDev: true,
            );
          },
        );
        when(
          () => mockPubDevChecker.waitUntilVersionAvailable(
            packageName: any(named: 'packageName'),
            version: any(named: 'version'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

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
              ggDoPublish: mockGgDoPublish,
              ggDoCommit: mockGgDoCommit,
              ggDoPush: mockGgDoPush,
              unlocalizeRefs: mockUnlocalizeRefs,
              sortedProcessingList: mockSortedProcessingList,
              processRunner: mockProcessRunner.call,
              canPublishCommand: mockCanPublishCommand,
              doReviewCommand: mockDoReviewCommand,
              getVersionCommand: mockGetVersion,
              setRefVersionCommand: mockSetRefVersion,
              getRefVersionCommand: mockGetRefVersion,
              pubDevChecker: mockPubDevChecker,
              editMessage: (initialMessage) async => initialMessage,
              confirmDeleteTicket: (_) => false,
            ),
          );

        await runner.run([
          'publish',
          '--input',
          ticketDir.path,
        ]);

        verify(
          () => mockSetRefVersion.get(
            directory: bDir,
            ref: 'A',
            version: '^1.2.3',
          ),
        ).called(1);
      },
    );

    test(
      'aborts when updating dependent ref version fails',
      () async {
        final mockGgDoPublish = MockGgDoPublish();
        final mockGgDoCommit = MockGgDoCommit();
        final mockGgDoPush = MockGgDoPush();
        final mockUnlocalizeRefs = MockUnlocalizeRefs();
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockProcessRunner = MockProcessRunner();
        final mockCanPublishCommand = MockCanPublishCommand();
        final mockDoReviewCommand = MockDoReviewCommand();
        final mockGetVersion = MockGetVersion();
        final mockSetRefVersion = MockSetRefVersion();
        final mockGetRefVersion = MockGetRefVersion();
        final mockPubDevChecker = MockPubDevChecker();

        when(
          () => mockDoReviewCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            verbose: any(named: 'verbose'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockCanPublishCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        final aDir = Directory(path.join(ticketDir.path, 'A'));
        final bDir = Directory(path.join(ticketDir.path, 'B'));
        when(
          () => mockSortedProcessingList.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(
              name: 'A',
              directory: aDir,
              manifest: DartPackageManifest(pubspec: Pubspec('A')),
            ),
            Node(
              name: 'B',
              directory: bDir,
              manifest: DartPackageManifest(pubspec: Pubspec('B')),
            ),
          ],
        );

        when(
          () => mockUnlocalizeRefs.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(() => mockGetVersion.get(directory: aDir))
            .thenAnswer((_) async => '2.0.0');
        when(() => mockGetVersion.get(directory: bDir))
            .thenAnswer((_) async => '0.1.0');

        when(
          () => mockGetRefVersion.get(
            directory: any(named: 'directory'),
            ref: any(named: 'ref'),
          ),
        ).thenAnswer((_) async => null);
        when(
          () => mockGetRefVersion.get(
            directory: bDir,
            ref: 'A',
          ),
        ).thenAnswer((_) async => '^any');

        when(
          () => mockSetRefVersion.get(
            directory: bDir,
            ref: 'A',
            version: '^2.0.0',
          ),
        ).thenThrow(Exception('update failed'));

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
          () => mockGgDoPublish.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => mockPubDevChecker.getPackagePublishInfo(
            packageName: any(named: 'packageName'),
          ),
        ).thenAnswer(
          (invocation) async {
            final packageName =
                invocation.namedArguments[#packageName] as String;
            return PackagePublishInfo(
              packageName: packageName,
              waitsForPubDev: true,
            );
          },
        );
        when(
          () => mockPubDevChecker.waitUntilVersionAvailable(
            packageName: any(named: 'packageName'),
            version: any(named: 'version'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

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
              ggDoPublish: mockGgDoPublish,
              ggDoCommit: mockGgDoCommit,
              ggDoPush: mockGgDoPush,
              unlocalizeRefs: mockUnlocalizeRefs,
              sortedProcessingList: mockSortedProcessingList,
              processRunner: mockProcessRunner.call,
              canPublishCommand: mockCanPublishCommand,
              doReviewCommand: mockDoReviewCommand,
              getVersionCommand: mockGetVersion,
              setRefVersionCommand: mockSetRefVersion,
              getRefVersionCommand: mockGetRefVersion,
              pubDevChecker: mockPubDevChecker,
              editMessage: (initialMessage) async => initialMessage,
              confirmDeleteTicket: (_) => false,
            ),
          );

        await expectLater(
          () async => await runner.run([
            'publish',
            '--input',
            ticketDir.path,
          ]),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Failed to update version of A in B: '
                  'Exception: update failed'),
            ),
          ),
        );
      },
    );

    test(
      'logs error when deleting repository directory from ticket fails',
      () async {
        final mockGgDoPublish = MockGgDoPublish();
        final mockGgDoCommit = MockGgDoCommit();
        final mockGgDoPush = MockGgDoPush();
        final mockUnlocalizeRefs = MockUnlocalizeRefs();
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockProcessRunner = MockProcessRunner();
        final mockCanPublishCommand = MockCanPublishCommand();
        final mockDoReviewCommand = MockDoReviewCommand();
        final mockGetVersion = MockGetVersion();
        final mockSetRefVersion = MockSetRefVersion();
        final mockGetRefVersion = MockGetRefVersion();
        final mockPubDevChecker = MockPubDevChecker();
        final mockDirB = MockDirectory();

        when(
          () => mockDoReviewCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            verbose: any(named: 'verbose'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockCanPublishCommand.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        final dirA = Directory(path.join(ticketDir.path, 'A'));
        when(
          () => mockSortedProcessingList.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(
              name: 'A',
              directory: dirA,
              manifest: DartPackageManifest(pubspec: Pubspec('A')),
            ),
            Node(
              name: 'B',
              directory: mockDirB,
              manifest: DartPackageManifest(pubspec: Pubspec('B')),
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
          () => mockGgDoPublish.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => mockPubDevChecker.getPackagePublishInfo(
            packageName: any(named: 'packageName'),
          ),
        ).thenAnswer(
          (invocation) async {
            final packageName =
                invocation.namedArguments[#packageName] as String;
            return PackagePublishInfo(
              packageName: packageName,
              waitsForPubDev: true,
            );
          },
        );
        when(
          () => mockPubDevChecker.waitUntilVersionAvailable(
            packageName: any(named: 'packageName'),
            version: any(named: 'version'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(() => mockDirB.path).thenReturn(
          path.join(ticketDir.path, 'B'),
        );
        when(() => mockDirB.existsSync()).thenReturn(true);
        when(
          () => mockDirB.deleteSync(recursive: true),
        ).thenThrow(Exception('delete failed'));
        when(
          () => mockProcessRunner(
            'git',
            ['push', 'origin', '--delete', 'TICKPB'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

        final runner = CommandRunner<void>('test', 'do publish ticket')
          ..addCommand(
            DoPublishCommand(
              ggLog: ggLog,
              ggDoPublish: mockGgDoPublish,
              ggDoCommit: mockGgDoCommit,
              ggDoPush: mockGgDoPush,
              unlocalizeRefs: mockUnlocalizeRefs,
              sortedProcessingList: mockSortedProcessingList,
              processRunner: mockProcessRunner.call,
              canPublishCommand: mockCanPublishCommand,
              doReviewCommand: mockDoReviewCommand,
              getVersionCommand: mockGetVersion,
              setRefVersionCommand: mockSetRefVersion,
              getRefVersionCommand: mockGetRefVersion,
              pubDevChecker: mockPubDevChecker,
              editMessage: (initialMessage) async => initialMessage,
              confirmDeleteTicket: (_) => true,
            ),
          );

        await runner.run([
          'publish',
          '--input',
          ticketDir.path,
        ]);

        expect(
          messages.any(
            (m) => m.contains(
              'Failed to delete repository B from ticket TICKPB: '
              'Exception: delete failed',
            ),
          ),
          isTrue,
        );
      },
    );

    test('logs error when remote branch deletion fails', () async {
      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockDoReviewCommand = MockDoReviewCommand();
      final mockGetVersion = MockGetVersion();
      final mockSetRefVersion = MockSetRefVersion();
      final mockGetRefVersion = MockGetRefVersion();
      final mockPubDevChecker = MockPubDevChecker();

      when(
        () => mockDoReviewCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          verbose: any(named: 'verbose'),
        ),
      ).thenAnswer((_) async {});
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
            manifest: DartPackageManifest(pubspec: Pubspec('A')),
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
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
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
      when(
        () => mockPubDevChecker.getPackagePublishInfo(
          packageName: any(named: 'packageName'),
        ),
      ).thenAnswer(
        (_) async => const PackagePublishInfo(
          packageName: 'A',
          waitsForPubDev: false,
        ),
      );
      when(
        () => mockProcessRunner(
          'git',
          ['push', 'origin', '--delete', 'TICKPB'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 1, '', 'branch delete fail'));

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            ggDoPublish: mockGgDoPublish,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            unlocalizeRefs: mockUnlocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            doReviewCommand: mockDoReviewCommand,
            getVersionCommand: mockGetVersion,
            setRefVersionCommand: mockSetRefVersion,
            getRefVersionCommand: mockGetRefVersion,
            pubDevChecker: mockPubDevChecker,
            editMessage: (initialMessage) async => initialMessage,
            confirmDeleteTicket: (_) => true,
          ),
        );

      await runner.run([
        'publish',
        '--input',
        ticketDir.path,
      ]);

      expect(
        messages.any(
          (m) => m.contains(
            'Failed to delete repository A from ticket TICKPB: '
            'Exception: Failed to delete remote branch TICKPB '
            'for A: branch delete fail',
          ),
        ),
        isTrue,
      );
      expect(Directory(path.join(ticketDir.path, 'A')).existsSync(), isTrue);
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
