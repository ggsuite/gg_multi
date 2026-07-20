// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights
// Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart' as gg;
// ignore: lines_longer_than_80_chars
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_localize_refs/gg_localize_refs.dart';
import 'package:gg_multi/src/backend/npm_registry_checker.dart';
import 'package:gg_multi/src/backend/pub_dev_checker.dart';
import 'package:gg_multi/src/commands/do/configure_publish.dart'
    show DoConfigurePublishCommand;
import 'package:gg_multi/src/commands/do/push.dart';
import 'package:gg_multi/src/commands/do/review.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:test/test.dart';
import 'package:gg_multi/src/commands/do/publish.dart';
import 'package:gg_multi/src/commands/can/publish.dart';

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

/// Mock for DoConfigurePublishCommand
class MockConfigurePublishCommand extends Mock
    implements DoConfigurePublishCommand {}

/// Mock for UnlocalizeRefs
class MockUnlocalizeRefs extends Mock implements ChangeRefsToPubDev {}

/// Mock for RestorePublishTo
class MockRestorePublishTo extends Mock implements RestorePublishTo {}

/// Mocks for version/ref helpers
class MockGetVersion extends Mock implements GetVersion {}

class MockSetRefVersion extends Mock implements SetRefVersion {}

class MockGetRefVersion extends Mock implements GetRefVersion {}

class MockPubDevChecker extends Mock implements PubDevChecker {}

/// Mock for [NpmRegistryChecker].
class MockNpmRegistryChecker extends Mock implements NpmRegistryChecker {}

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
    File(path.join(ticketDir.path, 'A', 'pubspec.yaml'))
        .writeAsStringSync('name: A\n');
    // B is a Flutter package to cover the Flutter switch in refresh.
    File(path.join(ticketDir.path, 'B', 'pubspec.yaml'))
        .writeAsStringSync('name: B\nflutter:\n');
    // A ready-made runtime publish config so the tests exercise `do publish`
    // non-interactively — it reuses .gg/.gg-publish.json when present instead
    // of invoking the interactive `do configure-publish`.
    Directory(path.join(ticketDir.path, '.gg')).createSync();
    File(path.join(ticketDir.path, '.gg', '.gg-publish.json'))
        .writeAsStringSync('''
{
  "version_increment": "patch",
  "merge_message": "test merge"
}
''');
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
            'Exception: Not inside a ticket folder',
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
      final mockConfigure = MockConfigurePublishCommand();

      // The empty ticket has no config file, so `do publish` configures it;
      // the mock returns an empty config without any interactive prompt.
      when(
        () => mockConfigure.configure(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => gg.PublishConfig());

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
            doConfigurePublishCommand: mockConfigure,
            confirmDeleteTicket: (_) => false,
          ),
        );
      await runner.run(['publish', '--input', emptyTicket.path]);
      expect(
        messages,
        contains('⚠️ No repos in this ticket'),
      );
    });

    test('runs gg_multi do review before gg_multi can publish', () async {
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

      // One repo, so the review gate is reached (an empty ticket returns
      // before it). The can-publish stub aborts the run right after the
      // ordered calls under test.
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
        () => mockCanPublishCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenThrow(Exception('stop after can publish'));

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

      await expectLater(
        () => runner.run(['publish', '--input', ticketDir.path]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('stop after can publish'),
          ),
        ),
      );

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
            contains('gg_multi do review failed: Exception: review failed'),
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
      _stubPubUpgrade(mockProcessRunner);
      _stubRepoSnapshot(mockProcessRunner);
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
          verbose: any(named: 'verbose'),
          versionIncrement: any(named: 'versionIncrement'),
          channel: any(named: 'channel'),
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
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
          '✅ All repos published',
        ),
      );
      expect(
        messages.any((m) => m.contains('A:')),
        isTrue,
      );
      expect(
        messages.any((m) => m.contains('B:')),
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

    test(
      '--config delete_ticket=true bypasses the interactive prompt',
      () async {
        // delete_ticket: true must bypass the interactive prompt.
        File(path.join(ticketDir.path, '.gg-publish.json'))
            .writeAsStringSync('''
{
  "version_increment": "patch",
  "merge_message": "via --config",
  "delete_ticket": true
}
''');

        final mockGgDoPublish = MockGgDoPublish();
        final mockGgDoCommit = MockGgDoCommit();
        final mockGgDoPush = MockGgDoPush();
        final mockUnlocalizeRefs = MockUnlocalizeRefs();
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockProcessRunner = MockProcessRunner();
        _stubPubUpgrade(mockProcessRunner);
        _stubRepoSnapshot(mockProcessRunner);
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
            verbose: any(named: 'verbose'),
            versionIncrement: any(named: 'versionIncrement'),
            channel: any(named: 'channel'),
            askBeforePublishing: any(named: 'askBeforePublishing'),
            resume: any(named: 'resume'),
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
            final packageName =
                invocation.namedArguments[#packageName] as String;
            return PackagePublishInfo(
              packageName: packageName,
              waitsForPubDev: false,
            );
          },
        );
        when(
          () => mockProcessRunner(
            'git',
            ['push', 'origin', '--delete', 'TICKPB'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

        var promptCalls = 0;

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
              confirmDeleteTicket: (_) {
                promptCalls++;
                return false;
              },
            ),
          );

        await runner.run([
          'publish',
          '--input',
          ticketDir.path,
          '--config',
          '.gg-publish.json',
        ]);

        expect(
          promptCalls,
          0,
          reason: 'config delete_ticket=true must skip the prompt',
        );
        expect(
          Directory(path.join(ticketDir.path, 'A')).existsSync(),
          isFalse,
          reason: 'config delete_ticket=true must delete the ticket repos',
        );
      },
    );

    test('waits on npm for a published TypeScript dependency', () async {
      // Make repo A a TypeScript project; B (Dart) depends on A.
      File(path.join(ticketDir.path, 'A', 'pubspec.yaml')).deleteSync();
      File(path.join(ticketDir.path, 'A', 'package.json'))
          .writeAsStringSync('{"name": "A", "version": "1.0.0"}');
      File(path.join(ticketDir.path, 'A', 'tsconfig.json'))
          .writeAsStringSync('{}');

      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      _stubPubUpgrade(mockProcessRunner);
      _stubRepoSnapshot(mockProcessRunner);
      when(
        () => mockProcessRunner(
          'npm',
          ['install'],
          workingDirectory: any(named: 'workingDirectory'),
          environment: any(named: 'environment'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockDoReviewCommand = MockDoReviewCommand();
      final mockGetVersion = MockGetVersion();
      final mockSetRefVersion = MockSetRefVersion();
      final mockGetRefVersion = MockGetRefVersion();
      final mockPubDevChecker = MockPubDevChecker();
      final mockNpmChecker = MockNpmRegistryChecker();

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
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
          verbose: any(named: 'verbose'),
          versionIncrement: any(named: 'versionIncrement'),
          channel: any(named: 'channel'),
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockGetVersion.get(directory: any(named: 'directory')),
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

      // The Dart repo B reports via pub.dev; the TypeScript repo A via npm.
      when(
        () => mockPubDevChecker.getPackagePublishInfo(
          packageName: any(named: 'packageName'),
        ),
      ).thenAnswer(
        (i) async => PackagePublishInfo(
          packageName: i.namedArguments[#packageName] as String,
          waitsForPubDev: false,
        ),
      );
      when(
        () => mockNpmChecker.getPackagePublishInfo(
          packageName: any(named: 'packageName'),
        ),
      ).thenAnswer(
        (i) async => PackagePublishInfo(
          packageName: i.namedArguments[#packageName] as String,
          waitsForPubDev: true,
        ),
      );
      when(
        () => mockNpmChecker.waitUntilVersionAvailable(
          packageName: any(named: 'packageName'),
          version: any(named: 'version'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

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
            npmChecker: mockNpmChecker,
            confirmDeleteTicket: (_) => false,
          ),
        );
      await runner.run(['publish', '--input', ticketDir.path, '--verbose']);

      // A's publish info is queried on npm, and B waits for A on npm.
      verify(
        () => mockNpmChecker.getPackagePublishInfo(packageName: 'A'),
      ).called(1);
      verify(
        () => mockNpmChecker.waitUntilVersionAvailable(
          packageName: 'A',
          version: '1.0.0',
          ggLog: any(named: 'ggLog'),
        ),
      ).called(1);
    });

    test('passes a per-repo merge message + increment to gg do publish',
        () async {
      // A per-repo override in the runtime config drives the merge message and
      // version increment gg_one receives (no interactive editor anymore).
      File(path.join(ticketDir.path, '.gg', '.gg-publish.json'))
          .writeAsStringSync('''
{
  "repos": {
    "A": { "version_increment": "minor", "merge_message": "per-repo msg" }
  }
}
''');

      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      _stubPubUpgrade(mockProcessRunner);
      _stubRepoSnapshot(mockProcessRunner);
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
          verbose: any(named: 'verbose'),
          versionIncrement: any(named: 'versionIncrement'),
          channel: any(named: 'channel'),
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
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
            confirmDeleteTicket: (_) => false,
          ),
        );

      await runner.run([
        'publish',
        '--input',
        ticketDir.path,
      ]);

      verify(
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: 'per-repo msg',
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
          verbose: any(named: 'verbose'),
          versionIncrement: 'minor',
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
        ),
      ).called(1);
    });

    test('forwards the release channel to gg do publish', () async {
      // Top-level channel: rc applies to repos without an override; a per-repo
      // channel override wins for that repo.
      File(path.join(ticketDir.path, '.gg', '.gg-publish.json'))
          .writeAsStringSync('''
{
  "version_increment": "minor",
  "merge_message": "msg",
  "channel": "rc",
  "repos": {
    "B": { "channel": "stable" }
  }
}
''');

      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      _stubPubUpgrade(mockProcessRunner);
      _stubRepoSnapshot(mockProcessRunner);
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
          verbose: any(named: 'verbose'),
          versionIncrement: any(named: 'versionIncrement'),
          channel: any(named: 'channel'),
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockGetVersion.get(directory: any(named: 'directory')),
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
            confirmDeleteTicket: (_) => false,
          ),
        );

      await runner.run(['publish', '--input', ticketDir.path]);

      // A inherits the top-level rc channel …
      verify(
        () => mockGgDoPublish.exec(
          directory: any(
            named: 'directory',
            that: predicate<Directory>((dir) => dir.path.endsWith('A')),
          ),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
          verbose: any(named: 'verbose'),
          versionIncrement: any(named: 'versionIncrement'),
          channel: 'rc',
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
        ),
      ).called(1);

      // … while B's per-repo override forces stable.
      verify(
        () => mockGgDoPublish.exec(
          directory: any(
            named: 'directory',
            that: predicate<Directory>((dir) => dir.path.endsWith('B')),
          ),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
          verbose: any(named: 'verbose'),
          versionIncrement: any(named: 'versionIncrement'),
          channel: 'stable',
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
        ),
      ).called(1);
    });

    test('falls back to the top-level merge message + increment', () async {
      // No per-repo override: forRepo falls back to the top-level defaults.
      File(path.join(ticketDir.path, '.gg', '.gg-publish.json'))
          .writeAsStringSync('''
{
  "version_increment": "major",
  "merge_message": "top-level msg"
}
''');

      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      _stubPubUpgrade(mockProcessRunner);
      _stubRepoSnapshot(mockProcessRunner);
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
          verbose: any(named: 'verbose'),
          versionIncrement: any(named: 'versionIncrement'),
          channel: any(named: 'channel'),
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
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
            confirmDeleteTicket: (_) => false,
          ),
        );

      await runner.run([
        'publish',
        '--input',
        ticketDir.path,
      ]);

      verify(
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: 'top-level msg',
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
          verbose: any(named: 'verbose'),
          versionIncrement: 'major',
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
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
      _stubPubUpgrade(mockProcessRunner);
      _stubRepoSnapshot(mockProcessRunner);
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
          verbose: any(named: 'verbose'),
          versionIncrement: any(named: 'versionIncrement'),
          channel: any(named: 'channel'),
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
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
      _stubPubUpgrade(mockProcessRunner);
      _stubRepoSnapshot(mockProcessRunner);
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

      // The repo list is resolved before the review gate now.
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
            confirmDeleteTicket: (_) => false,
          ),
        );
      await expectLater(
        () async => await runner.run(['publish', '--input', ticketDir.path]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('gg_multi can publish failed:'),
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
      _stubPubUpgrade(mockProcessRunner);
      _stubRepoSnapshot(mockProcessRunner);
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
          verbose: any(named: 'verbose'),
          versionIncrement: any(named: 'versionIncrement'),
          channel: any(named: 'channel'),
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
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

      // Repos must still exist in the ticket after a failed publish.
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
      _stubPubUpgrade(mockProcessRunner);
      _stubRepoSnapshot(mockProcessRunner);
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
          verbose: any(named: 'verbose'),
          versionIncrement: any(named: 'versionIncrement'),
          channel: any(named: 'channel'),
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
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
      _stubPubUpgrade(mockProcessRunner);
      _stubRepoSnapshot(mockProcessRunner);
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
          verbose: any(named: 'verbose'),
          versionIncrement: any(named: 'versionIncrement'),
          channel: any(named: 'channel'),
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
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
        _stubPubUpgrade(mockProcessRunner);
        _stubRepoSnapshot(mockProcessRunner);
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

        // General stub first; later (bDir, 'A') stub wins (mocktail).
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
            verbose: any(named: 'verbose'),
            versionIncrement: any(named: 'versionIncrement'),
            channel: any(named: 'channel'),
            askBeforePublishing: any(named: 'askBeforePublishing'),
            resume: any(named: 'resume'),
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
            version: '1.2.3',
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
        _stubPubUpgrade(mockProcessRunner);
        _stubRepoSnapshot(mockProcessRunner);
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
            version: '2.0.0',
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
            verbose: any(named: 'verbose'),
            versionIncrement: any(named: 'versionIncrement'),
            channel: any(named: 'channel'),
            askBeforePublishing: any(named: 'askBeforePublishing'),
            resume: any(named: 'resume'),
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
        _stubPubUpgrade(mockProcessRunner);
        _stubRepoSnapshot(mockProcessRunner);
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
            verbose: any(named: 'verbose'),
            versionIncrement: any(named: 'versionIncrement'),
            channel: any(named: 'channel'),
            askBeforePublishing: any(named: 'askBeforePublishing'),
            resume: any(named: 'resume'),
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
      _stubPubUpgrade(mockProcessRunner);
      _stubRepoSnapshot(mockProcessRunner);
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
          verbose: any(named: 'verbose'),
          versionIncrement: any(named: 'versionIncrement'),
          channel: any(named: 'channel'),
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
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

    test('invokes RestorePublishTo after unlocalize for each repo', () async {
      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockRestorePublishTo = MockRestorePublishTo();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      _stubPubUpgrade(mockProcessRunner);
      _stubRepoSnapshot(mockProcessRunner);
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

      final order = <String>[];
      when(
        () => mockUnlocalizeRefs.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {
        order.add('unlocalize');
      });
      when(
        () => mockRestorePublishTo.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {
        order.add('restore');
      });
      when(
        () => mockGgDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async {
        order.add('commit');
      });
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
          verbose: any(named: 'verbose'),
          versionIncrement: any(named: 'versionIncrement'),
          channel: any(named: 'channel'),
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockGetVersion.get(directory: any(named: 'directory')),
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
            restorePublishTo: mockRestorePublishTo,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            doReviewCommand: mockDoReviewCommand,
            getVersionCommand: mockGetVersion,
            setRefVersionCommand: mockSetRefVersion,
            getRefVersionCommand: mockGetRefVersion,
            pubDevChecker: mockPubDevChecker,
            confirmDeleteTicket: (_) => false,
          ),
        );

      await runner.run([
        'publish',
        '--input',
        ticketDir.path,
      ]);

      expect(order, ['unlocalize', 'restore', 'commit']);
    });

    test('aborts when RestorePublishTo throws', () async {
      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockRestorePublishTo = MockRestorePublishTo();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      _stubPubUpgrade(mockProcessRunner);
      _stubRepoSnapshot(mockProcessRunner);
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockDoReviewCommand = MockDoReviewCommand();

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
        () => mockRestorePublishTo.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenThrow(Exception('restore failed'));

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            ggDoPublish: mockGgDoPublish,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            unlocalizeRefs: mockUnlocalizeRefs,
            restorePublishTo: mockRestorePublishTo,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            doReviewCommand: mockDoReviewCommand,
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
            contains('Failed to restore publish_to for A'),
          ),
        ),
      );
    });

    test('aborts when dart pub upgrade fails for a repo', () async {
      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockRestorePublishTo = MockRestorePublishTo();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      _stubRepoSnapshot(mockProcessRunner);
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockDoReviewCommand = MockDoReviewCommand();

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
        () => mockRestorePublishTo.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      // Stub `dart pub upgrade` so it fails with non-zero exit code.
      when(
        () => mockProcessRunner(
          'dart',
          ['pub', 'upgrade'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(0, 1, '', 'pub upgrade exploded'),
      );

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            ggDoPublish: mockGgDoPublish,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            unlocalizeRefs: mockUnlocalizeRefs,
            restorePublishTo: mockRestorePublishTo,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            doReviewCommand: mockDoReviewCommand,
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
            contains('Failed to execute dart pub upgrade in A'),
          ),
        ),
      );

      verifyNever(
        () => mockGgDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          force: any(named: 'force'),
        ),
      );
    });

    test('runs npm install for typescript repos instead of dart pub upgrade',
        () async {
      // Swap pubspec for package.json+tsconfig so A becomes typescript.
      File(path.join(ticketDir.path, 'A', 'pubspec.yaml')).deleteSync();
      File(path.join(ticketDir.path, 'A', 'package.json')).writeAsStringSync(
        jsonEncode(<String, dynamic>{'name': 'A'}),
      );
      File(path.join(ticketDir.path, 'A', 'tsconfig.json'))
          .writeAsStringSync('{}');

      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockRestorePublishTo = MockRestorePublishTo();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      _stubRepoSnapshot(mockProcessRunner);
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockDoReviewCommand = MockDoReviewCommand();
      final mockGetVersion = MockGetVersion();
      final mockGetRefVersion = MockGetRefVersion();
      final mockSetRefVersion = MockSetRefVersion();
      final mockPubDevChecker = MockPubDevChecker();

      final repoADir = Directory(path.join(ticketDir.path, 'A'));

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
        () => mockUnlocalizeRefs.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockRestorePublishTo.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});
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
        () => mockProcessRunner(
          'npm',
          ['install'],
          workingDirectory: repoADir.path,
          environment: any(named: 'environment'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
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
          verbose: any(named: 'verbose'),
          versionIncrement: any(named: 'versionIncrement'),
          channel: any(named: 'channel'),
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockGetVersion.get(directory: any(named: 'directory')),
      ).thenAnswer((_) async => null);

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            ggDoPublish: mockGgDoPublish,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            unlocalizeRefs: mockUnlocalizeRefs,
            restorePublishTo: mockRestorePublishTo,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            doReviewCommand: mockDoReviewCommand,
            getVersionCommand: mockGetVersion,
            setRefVersionCommand: mockSetRefVersion,
            getRefVersionCommand: mockGetRefVersion,
            pubDevChecker: mockPubDevChecker,
            confirmDeleteTicket: (_) => false,
          ),
        );

      await runner.run(['publish', '--input', ticketDir.path]);

      // Capture env to assert PNPM_CONFIG_BLOCK_EXOTIC_SUBDEPS=false.
      final captured = verify(
        () => mockProcessRunner(
          'npm',
          ['install'],
          workingDirectory: repoADir.path,
          environment: captureAny(named: 'environment'),
        ),
      ).captured;
      expect(captured.length, 1);
      final env = captured.single as Map<String, String>;
      expect(env['PNPM_CONFIG_BLOCK_EXOTIC_SUBDEPS'], 'false');

      verifyNever(
        () => mockProcessRunner(
          'dart',
          ['pub', 'upgrade'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
    });

    test('runs BOTH npm install and dart pub upgrade for bridge repos',
        () async {
      // Keep pubspec.yaml AND add package.json + tsconfig -> A is a bridge,
      // whose Dart pubspec.lock must be refreshed alongside node_modules.
      File(path.join(ticketDir.path, 'A', 'package.json')).writeAsStringSync(
        jsonEncode(<String, dynamic>{'name': 'A'}),
      );
      File(path.join(ticketDir.path, 'A', 'tsconfig.json'))
          .writeAsStringSync('{}');

      final mockGgDoPublish = MockGgDoPublish();
      final mockGgDoCommit = MockGgDoCommit();
      final mockGgDoPush = MockGgDoPush();
      final mockUnlocalizeRefs = MockUnlocalizeRefs();
      final mockRestorePublishTo = MockRestorePublishTo();
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      _stubRepoSnapshot(mockProcessRunner);
      final mockCanPublishCommand = MockCanPublishCommand();
      final mockDoReviewCommand = MockDoReviewCommand();
      final mockGetVersion = MockGetVersion();
      final mockGetRefVersion = MockGetRefVersion();
      final mockSetRefVersion = MockSetRefVersion();
      final mockPubDevChecker = MockPubDevChecker();

      final repoADir = Directory(path.join(ticketDir.path, 'A'));

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
        () => mockUnlocalizeRefs.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockRestorePublishTo.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});
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
        () => mockProcessRunner(
          'npm',
          ['install'],
          workingDirectory: repoADir.path,
          environment: any(named: 'environment'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => mockProcessRunner(
          'dart',
          ['pub', 'upgrade'],
          workingDirectory: repoADir.path,
          environment: any(named: 'environment'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
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
          verbose: any(named: 'verbose'),
          versionIncrement: any(named: 'versionIncrement'),
          channel: any(named: 'channel'),
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockGetVersion.get(directory: any(named: 'directory')),
      ).thenAnswer((_) async => null);

      final runner = CommandRunner<void>('test', 'do publish ticket')
        ..addCommand(
          DoPublishCommand(
            ggLog: ggLog,
            ggDoPublish: mockGgDoPublish,
            ggDoCommit: mockGgDoCommit,
            ggDoPush: mockGgDoPush,
            unlocalizeRefs: mockUnlocalizeRefs,
            restorePublishTo: mockRestorePublishTo,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            canPublishCommand: mockCanPublishCommand,
            doReviewCommand: mockDoReviewCommand,
            getVersionCommand: mockGetVersion,
            setRefVersionCommand: mockSetRefVersion,
            getRefVersionCommand: mockGetRefVersion,
            pubDevChecker: mockPubDevChecker,
            confirmDeleteTicket: (_) => false,
          ),
        );

      await runner.run(['publish', '--input', ticketDir.path]);

      // The bridge refreshes BOTH: the TypeScript install (with the pnpm env
      // override) AND the Dart pubspec.lock via dart pub upgrade.
      final captured = verify(
        () => mockProcessRunner(
          'npm',
          ['install'],
          workingDirectory: repoADir.path,
          environment: captureAny(named: 'environment'),
        ),
      ).captured;
      expect(captured.length, 1);
      final env = captured.single as Map<String, String>;
      expect(env['PNPM_CONFIG_BLOCK_EXOTIC_SUBDEPS'], 'false');

      verify(
        () => mockProcessRunner(
          'dart',
          ['pub', 'upgrade'],
          workingDirectory: repoADir.path,
          environment: any(named: 'environment'),
        ),
      ).called(1);
    });
  });

  group('DoPublishCommand rollback on failure', () {
    late MockGgDoPublish mockGgDoPublish;
    late MockGgDoCommit mockGgDoCommit;
    late MockGgDoPush mockGgDoPush;
    late MockUnlocalizeRefs mockUnlocalizeRefs;
    late MockRestorePublishTo mockRestorePublishTo;
    late MockSortedProcessingList mockSortedProcessingList;
    late MockCanPublishCommand mockCanPublishCommand;
    late MockDoReviewCommand mockDoReviewCommand;
    late MockGetVersion mockGetVersion;
    late MockSetRefVersion mockSetRefVersion;
    late MockGetRefVersion mockGetRefVersion;
    late MockProcessRunner m;
    late String dirA;

    /// Creates a runner wired with all mocks of this group.
    CommandRunner<void> buildRunner() => CommandRunner<void>(
          'test',
          'do publish ticket',
        )..addCommand(
            DoPublishCommand(
              ggLog: ggLog,
              ggDoCommit: mockGgDoCommit,
              unlocalizeRefs: mockUnlocalizeRefs,
              restorePublishTo: mockRestorePublishTo,
              ggDoPush: mockGgDoPush,
              ggDoPublish: mockGgDoPublish,
              sortedProcessingList: mockSortedProcessingList,
              processRunner: m.call,
              canPublishCommand: mockCanPublishCommand,
              doReviewCommand: mockDoReviewCommand,
              getVersionCommand: mockGetVersion,
              setRefVersionCommand: mockSetRefVersion,
              getRefVersionCommand: mockGetRefVersion,
              confirmDeleteTicket: (_) => false,
            ),
          );

    /// Makes `gg do publish` fail for the single repo A.
    void stubPublishFails() {
      when(
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
          verbose: any(named: 'verbose'),
          versionIncrement: any(named: 'versionIncrement'),
          channel: any(named: 'channel'),
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
        ),
      ).thenThrow(Exception('publish failed'));
    }

    /// Stubs `git rev-parse HEAD` so the snapshot sees [before] and every
    /// later call sees [after] — the failed publish moved HEAD.
    void stubHeadMoves(String before, String after) {
      var headCalls = 0;
      when(
        () => m(
          'git',
          ['rev-parse', 'HEAD'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(0, 0, headCalls++ == 0 ? before : after, ''),
      );
    }

    setUp(() {
      mockGgDoPublish = MockGgDoPublish();
      mockGgDoCommit = MockGgDoCommit();
      mockGgDoPush = MockGgDoPush();
      mockUnlocalizeRefs = MockUnlocalizeRefs();
      mockRestorePublishTo = MockRestorePublishTo();
      mockSortedProcessingList = MockSortedProcessingList();
      mockCanPublishCommand = MockCanPublishCommand();
      mockDoReviewCommand = MockDoReviewCommand();
      mockGetVersion = MockGetVersion();
      mockSetRefVersion = MockSetRefVersion();
      mockGetRefVersion = MockGetRefVersion();
      m = MockProcessRunner();
      dirA = path.join(ticketDir.path, 'A');

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
        () => mockRestorePublishTo.exec(
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
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockGetVersion.get(directory: any(named: 'directory')),
      ).thenAnswer((_) async => '1.0.0');
      _stubPubUpgrade(m);

      // Baseline git behaviour: clean repo on the feature branch with an
      // unchanged main. Individual tests override what their scenario needs.
      when(
        () => m(
          'git',
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'TICKPB', ''));
      when(
        () => m(
          'git',
          ['rev-parse', 'HEAD'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'h0', ''));
      when(
        () => m(
          'git',
          ['status', '--porcelain'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => m(
          'git',
          ['rev-parse', '--verify', '--quiet', 'refs/heads/main'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'm0', ''));
      when(
        () => m(
          'git',
          ['ls-remote', 'origin', 'refs/heads/main'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(0, 0, 'r0\trefs/heads/main', ''),
      );
      when(
        () => m(
          'git',
          ['ls-remote', 'origin', 'refs/heads/TICKPB'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(0, 0, 'rf0\trefs/heads/TICKPB', ''),
      );
      when(
        () => m(
          'git',
          ['tag', '--list'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      // A rollback tolerates failing aborts (nothing to abort).
      when(
        () => m(
          'git',
          ['merge', '--abort'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 1, '', 'no merge'));
      when(
        () => m(
          'git',
          ['rebase', '--abort'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 1, '', 'no rebase'));
    });

    test(
        'restores HEAD, main position and new tags when nothing '
        'irreversible happened', () async {
      stubPublishFails();
      stubHeadMoves('h0', 'h1');

      // main moved locally during the failed run (m0 → m1) ...
      var mainCalls = 0;
      when(
        () => m(
          'git',
          ['rev-parse', '--verify', '--quiet', 'refs/heads/main'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(0, 0, mainCalls++ == 0 ? 'm0' : 'm1', ''),
      );
      // ... and the failed run created a tag.
      var tagCalls = 0;
      when(
        () => m(
          'git',
          ['tag', '--list'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(0, 0, tagCalls++ == 0 ? '' : 'v1.1.0', ''),
      );
      when(
        () => m(
          'git',
          ['reset', '--hard', 'h0'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => m(
          'git',
          ['branch', '-f', 'main', 'm0'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => m(
          'git',
          ['tag', '-d', 'v1.1.0'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      await expectLater(
        () async => buildRunner().run(
          ['publish', '--verbose', '--input', ticketDir.path],
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('publish failed'),
          ),
        ),
      );

      verify(
        () => m('git', ['reset', '--hard', 'h0'], workingDirectory: dirA),
      ).called(1);
      verify(
        () => m('git', ['branch', '-f', 'main', 'm0'], workingDirectory: dirA),
      ).called(1);
      verify(
        () => m('git', ['tag', '-d', 'v1.1.0'], workingDirectory: dirA),
      ).called(1);
      expect(
        messages.any(
          (msg) => msg.contains('Restored the state before the publish in A'),
        ),
        isTrue,
      );
      expect(
        messages.any(
          (msg) => msg.contains('pushes to origin are not rolled back'),
        ),
        isTrue,
      );
    });

    test('a full restore drops the repo-level .gg/.gg-publish.json', () async {
      // The gitignored runtime file survives `reset --hard`, but its step
      // markers describe commits the rollback just removed.
      final repoRuntime = File(path.join(dirA, '.gg', '.gg-publish.json'))
        ..createSync(recursive: true);
      repoRuntime.writeAsStringSync('''
{
  "version_increment": "patch",
  "merge_message": "m",
  "done_steps": ["prepare_version"]
}
''');
      stubPublishFails();
      stubHeadMoves('h0', 'h1');
      when(
        () => m(
          'git',
          ['reset', '--hard', 'h0'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      await expectLater(
        () async => buildRunner().run(
          ['publish', '--verbose', '--input', ticketDir.path],
        ),
        throwsA(isA<Exception>()),
      );

      expect(repoRuntime.existsSync(), isFalse);
    });

    test('keeps all commits when the version was already bumped', () async {
      // The runtime file's steps stay real on the keep-commits path — a
      // later --continue resumes exactly there, so the file must survive.
      final repoRuntime = File(path.join(dirA, '.gg', '.gg-publish.json'))
        ..createSync(recursive: true);
      repoRuntime.writeAsStringSync('''
{
  "version_increment": "patch",
  "merge_message": "m",
  "done_steps": ["prepare_version"]
}
''');
      stubPublishFails();
      stubHeadMoves('h0', 'h1');

      // The snapshot sees 1.0.0, the restore sees the bumped 1.1.0 — the
      // registry may already carry the release, so nothing is reset.
      var versionCalls = 0;
      when(
        () => mockGetVersion.get(directory: any(named: 'directory')),
      ).thenAnswer(
        (_) async => versionCalls++ == 0 ? '1.0.0' : '1.1.0',
      );

      await expectLater(
        () async => buildRunner().run(
          ['publish', '--verbose', '--input', ticketDir.path],
        ),
        throwsA(isA<Exception>()),
      );

      expect(repoRuntime.existsSync(), isTrue);

      verifyNever(
        () => m(
          'git',
          any(that: contains('reset')),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
      expect(
        messages.any(
          (msg) =>
              msg.contains('all commits were kept') &&
              msg.contains('resumes the publish'),
        ),
        isTrue,
      );
    });

    test(
        'checks out the feature branch and keeps commits when origin/main '
        'already moved', () async {
      stubPublishFails();

      // The failed run left the repo on main ...
      var branchCalls = 0;
      when(
        () => m(
          'git',
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer(
        (_) async =>
            ProcessResult(0, 0, branchCalls++ == 0 ? 'TICKPB' : 'main', ''),
      );
      // ... and origin/main already received the release push (r0 → r9).
      var remoteCalls = 0;
      when(
        () => m(
          'git',
          ['ls-remote', 'origin', 'refs/heads/main'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(
          0,
          0,
          remoteCalls++ == 0 ? 'r0\trefs/heads/main' : 'r9\trefs/heads/main',
          '',
        ),
      );
      when(
        () => m('git', ['checkout', 'TICKPB'], workingDirectory: dirA),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      await expectLater(
        () async => buildRunner().run(
          ['publish', '--verbose', '--input', ticketDir.path],
        ),
        throwsA(isA<Exception>()),
      );

      verify(
        () => m('git', ['checkout', 'TICKPB'], workingDirectory: dirA),
      ).called(1);
      verifyNever(
        () => m(
          'git',
          any(that: contains('reset')),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
      expect(
        messages.any(
          (msg) => msg.contains('origin/main already received the release'),
        ),
        isTrue,
      );
    });

    test('aborts before changing anything when saving the state fails',
        () async {
      when(
        () => m(
          'git',
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 1, '', 'not a repo'));

      await expectLater(
        () async => buildRunner().run(
          ['publish', '--verbose', '--input', ticketDir.path],
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Failed to save the state of A before publishing'),
          ),
        ),
      );

      verifyNever(
        () => mockUnlocalizeRefs.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      );
    });

    test('logs a manual-recovery hint when the restore itself fails', () async {
      stubPublishFails();
      stubHeadMoves('h0', 'h1');
      // A dirty repo → the manual-recovery hint must also surface the stash
      // hash, otherwise following it would wipe the uncommitted changes.
      when(
        () => m(
          'git',
          ['status', '--porcelain'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
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
        () => m(
          'git',
          ['reset', '--hard', 'h0'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 1, '', 'reset boom'));

      await expectLater(
        () async => buildRunner().run(
          ['publish', '--verbose', '--input', ticketDir.path],
        ),
        // The publish failure stays the primary error.
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('publish failed'),
          ),
        ),
      );

      expect(
        messages.any(
          (msg) =>
              msg.contains('restore it manually') &&
              msg.contains('git reset --hard h0') &&
              msg.contains('git stash apply --index stashsha'),
        ),
        isTrue,
      );
    });

    test('falls back to master and tolerates unreachable remotes', () async {
      stubPublishFails();
      stubHeadMoves('h0', 'h1');

      // No main branch → the snapshot falls back to master.
      when(
        () => m(
          'git',
          ['rev-parse', '--verify', '--quiet', 'refs/heads/main'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 1, '', ''));
      when(
        () => m(
          'git',
          ['rev-parse', '--verify', '--quiet', 'refs/heads/master'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'm0', ''));
      // The remote is unreachable at snapshot time and has no master branch
      // at restore time → both resolve to "unknown" and compare equal.
      var remoteCalls = 0;
      when(
        () => m(
          'git',
          ['ls-remote', 'origin', 'refs/heads/master'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer(
        (_) async => remoteCalls++ == 0
            ? ProcessResult(0, 128, '', 'no connection')
            : ProcessResult(0, 0, '', ''),
      );
      when(
        () => m(
          'git',
          ['reset', '--hard', 'h0'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      await expectLater(
        () async => buildRunner().run(
          ['publish', '--verbose', '--input', ticketDir.path],
        ),
        throwsA(isA<Exception>()),
      );

      // Full restore ran; master did not move (m0 both times) → no branch -f.
      verify(
        () => m('git', ['reset', '--hard', 'h0'], workingDirectory: dirA),
      ).called(1);
      verifyNever(
        () => m(
          'git',
          any(that: contains('branch')),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
    });

    test('works without any default branch and an unreadable version',
        () async {
      stubPublishFails();
      stubHeadMoves('h0', 'h1');

      // Neither main nor master exist; the version is unreadable — both are
      // tolerated and the full restore still runs.
      when(
        () => m(
          'git',
          ['rev-parse', '--verify', '--quiet', 'refs/heads/main'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 1, '', ''));
      when(
        () => m(
          'git',
          ['rev-parse', '--verify', '--quiet', 'refs/heads/master'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 1, '', ''));
      when(
        () => mockGetVersion.get(directory: any(named: 'directory')),
      ).thenThrow(Exception('no version'));
      when(
        () => m(
          'git',
          ['reset', '--hard', 'h0'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      await expectLater(
        () async => buildRunner().run(
          ['publish', '--verbose', '--input', ticketDir.path],
        ),
        throwsA(isA<Exception>()),
      );

      verify(
        () => m('git', ['reset', '--hard', 'h0'], workingDirectory: dirA),
      ).called(1);
      // No default branch → neither main nor master is queried on the remote.
      // (The feature branch is still queried, so this is scoped to main/master.)
      verifyNever(
        () => m(
          'git',
          ['ls-remote', 'origin', 'refs/heads/main'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
      verifyNever(
        () => m(
          'git',
          ['ls-remote', 'origin', 'refs/heads/master'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
    });

    test('restores stashed uncommitted changes of a dirty repo', () async {
      stubPublishFails();
      stubHeadMoves('h0', 'h1');

      // The repo carries uncommitted changes → the snapshot stashes them
      // (push-with-untracked, record the hash, re-apply, drop).
      when(
        () => m(
          'git',
          ['status', '--porcelain'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
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
        () => m(
          'git',
          ['reset', '--hard', 'h0'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
      when(
        () => m(
          'git',
          ['stash', 'apply', '--index', 'stashsha'],
          workingDirectory: dirA,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      await expectLater(
        () async => buildRunner().run(
          ['publish', '--verbose', '--input', ticketDir.path],
        ),
        throwsA(isA<Exception>()),
      );

      verify(
        () => m(
          'git',
          ['stash', 'apply', '--index', 'stashsha'],
          workingDirectory: dirA,
        ),
      ).called(1);
    });

    test('fully restores an uncommitted half-written version bump', () async {
      stubPublishFails();
      stubHeadMoves('h0', 'h1');

      // gg_one wrote the new version into pubspec.yaml but its commit failed,
      // so the bump is uncommitted (shows in `git status`). That is
      // recoverable — nothing reached the registry — so restore fully.
      var versionCalls = 0;
      when(
        () => mockGetVersion.get(directory: any(named: 'directory')),
      ).thenAnswer(
        (_) async => versionCalls++ == 0 ? '1.0.0' : '1.1.0',
      );
      // Clean at snapshot time, dirty (the half-bump) at restore time.
      var statusCalls = 0;
      when(
        () => m(
          'git',
          ['status', '--porcelain'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async {
        final out = statusCalls++ == 0 ? '' : ' M pubspec.yaml';
        return ProcessResult(0, 0, out, '');
      });
      when(
        () => m(
          'git',
          ['reset', '--hard', 'h0'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      await expectLater(
        () async => buildRunner().run(
          ['publish', '--verbose', '--input', ticketDir.path],
        ),
        throwsA(isA<Exception>()),
      );

      // The half-bump did not count as irreversible → full restore.
      verify(
        () => m('git', ['reset', '--hard', 'h0'], workingDirectory: dirA),
      ).called(1);
      expect(
        messages.any((msg) => msg.contains('all commits were kept')),
        isFalse,
      );
    });

    test('keeps all commits when the feature branch was already pushed',
        () async {
      stubPublishFails();
      stubHeadMoves('h0', 'h1');

      // origin/<feature> advanced (rf0 → rf9): the failed run pushed the
      // feature commit, so resetting local below it would desync the two.
      var featureCalls = 0;
      when(
        () => m(
          'git',
          ['ls-remote', 'origin', 'refs/heads/TICKPB'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer(
        (_) async => ProcessResult(
          0,
          0,
          featureCalls++ == 0
              ? 'rf0\trefs/heads/TICKPB'
              : 'rf9\trefs/heads/TICKPB',
          '',
        ),
      );

      await expectLater(
        () async => buildRunner().run(
          ['publish', '--verbose', '--input', ticketDir.path],
        ),
        throwsA(isA<Exception>()),
      );

      verifyNever(
        () => m(
          'git',
          any(that: contains('reset')),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      );
      expect(
        messages.any(
          (msg) =>
              msg.contains('the feature branch was already pushed to origin') &&
              msg.contains('resumes the publish'),
        ),
        isTrue,
      );
    });

    test('does not treat an unreachable remote as a moved main', () async {
      stubPublishFails();
      stubHeadMoves('h0', 'h1');

      // The snapshot read a concrete origin/main hash, but at restore time
      // `git ls-remote` fails (e.g. the network outage that broke the
      // publish). A null result must NOT masquerade as "already released".
      var remoteCalls = 0;
      when(
        () => m(
          'git',
          ['ls-remote', 'origin', 'refs/heads/main'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer(
        (_) async => remoteCalls++ == 0
            ? ProcessResult(0, 0, 'r0\trefs/heads/main', '')
            : ProcessResult(0, 1, '', 'no connection'),
      );
      when(
        () => m(
          'git',
          ['reset', '--hard', 'h0'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));

      await expectLater(
        () async => buildRunner().run(
          ['publish', '--verbose', '--input', ticketDir.path],
        ),
        throwsA(isA<Exception>()),
      );

      // Full restore ran; the failed ls-remote did not force cleanup mode.
      verify(
        () => m('git', ['reset', '--hard', 'h0'], workingDirectory: dirA),
      ).called(1);
      expect(
        messages.any((msg) => msg.contains('already received the release')),
        isFalse,
      );
    });
  });

  group('DoPublishCommand configure + resume', () {
    late MockGgDoPublish mockGgDoPublish;
    late MockGgDoCommit mockGgDoCommit;
    late MockGgDoPush mockGgDoPush;
    late MockUnlocalizeRefs mockUnlocalizeRefs;
    late MockSortedProcessingList mockSortedProcessingList;
    late MockProcessRunner mockProcessRunner;
    late MockCanPublishCommand mockCanPublishCommand;
    late MockDoReviewCommand mockDoReviewCommand;
    late MockGetVersion mockGetVersion;
    late MockSetRefVersion mockSetRefVersion;
    late MockGetRefVersion mockGetRefVersion;
    late MockPubDevChecker mockPubDevChecker;
    late MockConfigurePublishCommand mockConfigure;
    late File runtimeFile;

    Node repoNode(String name) => Node(
          name: name,
          directory: Directory(path.join(ticketDir.path, name)),
          manifest: DartPackageManifest(pubspec: Pubspec(name)),
        );

    setUp(() {
      mockGgDoPublish = MockGgDoPublish();
      mockGgDoCommit = MockGgDoCommit();
      mockGgDoPush = MockGgDoPush();
      mockUnlocalizeRefs = MockUnlocalizeRefs();
      mockSortedProcessingList = MockSortedProcessingList();
      mockProcessRunner = MockProcessRunner();
      _stubPubUpgrade(mockProcessRunner);
      _stubRepoSnapshot(mockProcessRunner);
      mockCanPublishCommand = MockCanPublishCommand();
      mockDoReviewCommand = MockDoReviewCommand();
      mockGetVersion = MockGetVersion();
      mockSetRefVersion = MockSetRefVersion();
      mockGetRefVersion = MockGetRefVersion();
      mockPubDevChecker = MockPubDevChecker();
      mockConfigure = MockConfigurePublishCommand();
      runtimeFile = File(path.join(ticketDir.path, '.gg', '.gg-publish.json'));

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
      ).thenAnswer((_) async => [repoNode('A')]);
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
          verbose: any(named: 'verbose'),
          versionIncrement: any(named: 'versionIncrement'),
          channel: any(named: 'channel'),
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => mockGetVersion.get(directory: any(named: 'directory')),
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
    });

    CommandRunner<void> buildRunner() =>
        CommandRunner<void>('test', 'do publish ticket')
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
              doConfigurePublishCommand: mockConfigure,
              confirmDeleteTicket: (_) => false,
            ),
          );

    test('a registry-visibility lookup failure does not abort the publish',
        () async {
      // getPackagePublishInfo is a network read; a transient failure there
      // must not abort a run whose repo already published irreversibly.
      when(
        () => mockPubDevChecker.getPackagePublishInfo(
          packageName: any(named: 'packageName'),
        ),
      ).thenThrow(Exception('pub.dev unreachable'));

      await buildRunner().run(['publish', '--input', ticketDir.path]);

      expect(
        messages.any(
          (m) => m.contains('Could not check registry visibility'),
        ),
        isTrue,
      );
      // The repo still published, and the run completed.
      verify(
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
          verbose: any(named: 'verbose'),
          versionIncrement: any(named: 'versionIncrement'),
          channel: any(named: 'channel'),
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
        ),
      ).called(1);
    });

    test('--continue without a saved run throws a clear error', () async {
      runtimeFile.deleteSync();
      await expectLater(
        () => buildRunner().run(
          ['publish', '--input', ticketDir.path, '--continue'],
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Nothing to continue'),
          ),
        ),
      );
    });

    test('--continue skips already-published repos and resumes the rest',
        () async {
      when(
        () => mockSortedProcessingList.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => [repoNode('A'), repoNode('B')]);
      runtimeFile.writeAsStringSync('''
{
  "repos": {
    "A": {
      "version_increment": "patch", "merge_message": "m",
      "status": "published"
    },
    "B": {
      "version_increment": "patch", "merge_message": "m",
      "status": "pending"
    }
  }
}
''');

      await buildRunner().run(
        ['publish', '--input', ticketDir.path, '--continue'],
      );

      // A was already published — it is skipped, only B is published.
      expect(messages, contains('A: already published — skipping.'));
      verify(
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
          verbose: any(named: 'verbose'),
          versionIncrement: any(named: 'versionIncrement'),
          channel: any(named: 'channel'),
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
        ),
      ).called(1);
      // Review + can-publish are skipped when resuming.
      verifyNever(
        () => mockDoReviewCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          verbose: any(named: 'verbose'),
        ),
      );
    });

    test('--reconfigure ignores the saved config and reconfigures', () async {
      when(
        () => mockConfigure.configure(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer(
        (_) async => gg.PublishConfig(
          versionIncrement: 'patch',
          mergeMessage: 'reconfigured',
        ),
      );

      await buildRunner().run(
        ['publish', '--input', ticketDir.path, '--reconfigure'],
      );

      verify(
        () => mockConfigure.configure(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).called(1);
    });

    test('-m is forwarded to configure as the default merge message', () async {
      // No config present → the interactive configure path runs, and -m is
      // handed to it as the default merge message.
      runtimeFile.deleteSync();
      when(
        () => mockConfigure.configure(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          defaultMergeMessage: any(named: 'defaultMergeMessage'),
        ),
      ).thenAnswer(
        (_) async => gg.PublishConfig(
          versionIncrement: 'patch',
          mergeMessage: 'Release msg',
        ),
      );

      await buildRunner().run(
        ['publish', '--input', ticketDir.path, '-m', 'Release msg'],
      );

      verify(
        () => mockConfigure.configure(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          defaultMergeMessage: 'Release msg',
        ),
      ).called(1);
    });

    test('reads the legacy <ticket>/.gg-publish.json when present', () async {
      runtimeFile.deleteSync();
      File(path.join(ticketDir.path, '.gg-publish.json')).writeAsStringSync('''
{
  "version_increment": "minor",
  "merge_message": "legacy msg"
}
''');

      await buildRunner().run(['publish', '--input', ticketDir.path]);

      verify(
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: 'legacy msg',
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
          verbose: any(named: 'verbose'),
          versionIncrement: 'minor',
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
        ),
      ).called(1);
      verifyNever(
        () => mockConfigure.configure(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      );
    });

    test('--continue rejects a co-passed --config', () async {
      await expectLater(
        () => buildRunner().run([
          'publish',
          '--input',
          ticketDir.path,
          '--continue',
          '--config',
          'x.json',
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('cannot be combined'),
          ),
        ),
      );
    });

    test('--continue rejects --reconfigure', () async {
      await expectLater(
        () => buildRunner().run([
          'publish',
          '--input',
          ticketDir.path,
          '--continue',
          '--reconfigure',
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('cannot be combined'),
          ),
        ),
      );
    });

    test('a plain re-run refuses a runtime file that still holds progress',
        () async {
      runtimeFile.writeAsStringSync('''
{
  "repos": {
    "A": {
      "version_increment": "patch", "merge_message": "m",
      "status": "failed"
    }
  }
}
''');
      await expectLater(
        () => buildRunner().run(['publish', '--input', ticketDir.path]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('unfinished publish left progress'),
          ),
        ),
      );
    });

    test('--continue after a review failure (nothing published) re-reviews',
        () async {
      runtimeFile.writeAsStringSync('''
{
  "repos": {
    "A": {
      "version_increment": "patch", "merge_message": "m",
      "status": "failed"
    }
  }
}
''');

      await buildRunner().run(
        ['publish', '--input', ticketDir.path, '--continue'],
      );

      // No repo was published yet, so review must still run.
      verify(
        () => mockDoReviewCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          verbose: any(named: 'verbose'),
        ),
      ).called(1);
    });

    test('a fresh run passes resume: false and gitignores the runtime file',
        () async {
      await buildRunner().run(['publish', '--input', ticketDir.path]);

      // gg_one must not silently resume on a fresh gg_multi run.
      verify(
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
          verbose: any(named: 'verbose'),
          versionIncrement: any(named: 'versionIncrement'),
          channel: any(named: 'channel'),
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: false,
        ),
      ).called(1);
      // The repo-level runtime file was gitignored before the pre-publish
      // commit, so gg_one's progress never shows up as an untracked file.
      final gitignore = File(path.join(ticketDir.path, 'A', '.gitignore'));
      expect(gitignore.existsSync(), isTrue);
      expect(
        gitignore.readAsStringSync(),
        contains('.gg/.gg-publish.json'),
      );
    });

    test('--continue forwards resume: true to gg_one', () async {
      when(
        () => mockSortedProcessingList.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => [repoNode('A'), repoNode('B')]);
      runtimeFile.writeAsStringSync('''
{
  "repos": {
    "A": {
      "version_increment": "patch", "merge_message": "m",
      "status": "published"
    },
    "B": {
      "version_increment": "patch", "merge_message": "m",
      "status": "failed"
    }
  }
}
''');

      await buildRunner().run(
        ['publish', '--input', ticketDir.path, '--continue'],
      );

      // Repo B is re-published in resume mode, so gg_one picks up at the
      // first step its own .gg/.gg-publish.json marks as open.
      verify(
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
          verbose: any(named: 'verbose'),
          versionIncrement: any(named: 'versionIncrement'),
          channel: any(named: 'channel'),
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: true,
        ),
      ).called(1);
    });

    test('--continue skips review when a failed repo has step progress',
        () async {
      // First-repo failure AFTER irreversible steps: ticket file holds only
      // 'failed', but the repo-level file proves the partial publish —
      // re-reviewing the partially merged ticket would block the resume.
      runtimeFile.writeAsStringSync('''
{
  "repos": {
    "A": {
      "version_increment": "patch", "merge_message": "m",
      "status": "failed"
    }
  }
}
''');
      final repoRuntime = File(
        path.join(ticketDir.path, 'A', '.gg', '.gg-publish.json'),
      )..createSync(recursive: true);
      repoRuntime.writeAsStringSync('''
{
  "version_increment": "patch",
  "merge_message": "m",
  "done_steps": ["prepare_version", "publish_registry", "merge"]
}
''');

      await buildRunner().run(
        ['publish', '--input', ticketDir.path, '--continue'],
      );

      verifyNever(
        () => mockDoReviewCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          verbose: any(named: 'verbose'),
        ),
      );
    });

    test('an unreadable repo progress file does not skip the review', () async {
      runtimeFile.writeAsStringSync('''
{
  "repos": {
    "A": {
      "version_increment": "patch", "merge_message": "m",
      "status": "failed"
    }
  }
}
''');
      final repoRuntime = File(
        path.join(ticketDir.path, 'A', '.gg', '.gg-publish.json'),
      )..createSync(recursive: true);
      repoRuntime.writeAsStringSync('{not valid json');

      await buildRunner().run(
        ['publish', '--input', ticketDir.path, '--continue'],
      );

      // An unreadable file cannot prove progress — review still runs.
      verify(
        () => mockDoReviewCommand.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          verbose: any(named: 'verbose'),
        ),
      ).called(1);
    });

    test('--config refuses a runtime file that still holds progress', () async {
      runtimeFile.writeAsStringSync('''
{
  "repos": {
    "A": {
      "version_increment": "patch", "merge_message": "m",
      "status": "published"
    }
  }
}
''');

      await expectLater(
        () => buildRunner().run([
          'publish',
          '--input',
          ticketDir.path,
          '--config',
          'x.json',
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('unfinished publish left progress'),
          ),
        ),
      );
      // The progress markers survive untouched.
      expect(runtimeFile.readAsStringSync(), contains('"published"'));
    });

    test('--config passes the guard when the runtime file has no progress',
        () async {
      // The setUp runtime file is config-only — --config may replace it.
      final configFile = File(path.join(ticketDir.path, 'plain.json'));
      configFile.writeAsStringSync(
        '{"version_increment":"major","merge_message":"plain msg"}',
      );

      await buildRunner().run([
        'publish',
        '--input',
        ticketDir.path,
        '--config',
        'plain.json',
      ]);

      verify(
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: 'plain msg',
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
          verbose: any(named: 'verbose'),
          versionIncrement: 'major',
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
        ),
      ).called(1);
    });

    test('--config with --reconfigure discards progress and proceeds',
        () async {
      runtimeFile.writeAsStringSync('''
{
  "repos": {
    "A": {
      "version_increment": "patch", "merge_message": "m",
      "status": "failed"
    }
  }
}
''');
      final configFile = File(path.join(ticketDir.path, 'fresh.json'));
      configFile.writeAsStringSync(
        '{"version_increment":"minor","merge_message":"fresh msg"}',
      );

      await buildRunner().run([
        'publish',
        '--input',
        ticketDir.path,
        '--config',
        'fresh.json',
        '--reconfigure',
      ]);

      verify(
        () => mockGgDoPublish.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: 'fresh msg',
          deleteFeatureBranch: any(named: 'deleteFeatureBranch'),
          verbose: any(named: 'verbose'),
          versionIncrement: 'minor',
          askBeforePublishing: any(named: 'askBeforePublishing'),
          resume: any(named: 'resume'),
        ),
      ).called(1);
    });

    test('--reconfigure removes the repo-level runtime files', () async {
      final repoRuntime = File(
        path.join(ticketDir.path, 'A', '.gg', '.gg-publish.json'),
      )..createSync(recursive: true);
      repoRuntime.writeAsStringSync('''
{
  "version_increment": "patch",
  "merge_message": "m",
  "done_steps": ["prepare_version"]
}
''');
      when(
        () => mockConfigure.configure(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          defaultMergeMessage: any(named: 'defaultMergeMessage'),
        ),
      ).thenAnswer(
        (_) async => gg.PublishConfig(
          versionIncrement: 'patch',
          mergeMessage: 'reconfigured',
        ),
      );

      await buildRunner().run(
        ['publish', '--input', ticketDir.path, '--reconfigure'],
      );

      // Stale gg_one step progress must not seed the reconfigured run.
      expect(repoRuntime.existsSync(), isFalse);
    });
  });
}

// Mock for ProcessRunner
class MockProcessRunner extends Mock {
  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });
}

/// Stubs `dart pub upgrade` on [runner] so it succeeds for any working
/// directory.
void _stubPubUpgrade(MockProcessRunner runner) {
  when(
    () => runner(
      'dart',
      ['pub', 'upgrade'],
      workingDirectory: any(named: 'workingDirectory'),
      environment: any(named: 'environment'),
    ),
  ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
}

/// Stubs the git calls of the pre-publish snapshot on [runner]: constant
/// branch/HEAD, a clean working tree, an existing `main` with an unchanged
/// remote and no tags. With these values a rollback after a failure sees an
/// unchanged repo and skips it.
void _stubRepoSnapshot(MockProcessRunner runner) {
  when(
    () => runner(
      'git',
      ['rev-parse', '--abbrev-ref', 'HEAD'],
      workingDirectory: any(named: 'workingDirectory'),
    ),
  ).thenAnswer((_) async => ProcessResult(0, 0, 'TICKPB', ''));
  when(
    () => runner(
      'git',
      ['rev-parse', 'HEAD'],
      workingDirectory: any(named: 'workingDirectory'),
    ),
  ).thenAnswer((_) async => ProcessResult(0, 0, 'samehead', ''));
  when(
    () => runner(
      'git',
      ['status', '--porcelain'],
      workingDirectory: any(named: 'workingDirectory'),
    ),
  ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
  when(
    () => runner(
      'git',
      ['rev-parse', '--verify', '--quiet', 'refs/heads/main'],
      workingDirectory: any(named: 'workingDirectory'),
    ),
  ).thenAnswer((_) async => ProcessResult(0, 0, 'mainhead', ''));
  when(
    () => runner(
      'git',
      ['ls-remote', 'origin', 'refs/heads/main'],
      workingDirectory: any(named: 'workingDirectory'),
    ),
  ).thenAnswer(
    (_) async => ProcessResult(0, 0, 'remotemain\trefs/heads/main', ''),
  );
  when(
    () => runner(
      'git',
      ['ls-remote', 'origin', 'refs/heads/TICKPB'],
      workingDirectory: any(named: 'workingDirectory'),
    ),
  ).thenAnswer(
    (_) async => ProcessResult(0, 0, 'remotefeature\trefs/heads/TICKPB', ''),
  );
  when(
    () => runner(
      'git',
      ['tag', '--list'],
      workingDirectory: any(named: 'workingDirectory'),
    ),
  ).thenAnswer((_) async => ProcessResult(0, 0, '', ''));
}
