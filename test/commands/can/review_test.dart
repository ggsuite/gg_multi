// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_publish/gg_publish.dart' as gg_publish;
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:test/test.dart';
import 'package:kidney_core/src/commands/can/review.dart';
import 'package:kidney_core/src/backend/status_utils.dart';

import '../../rm_console_colors_helper.dart';

class MockSortedProcessingList extends Mock implements SortedProcessingList {}

class MockProcessRunner extends Mock {
  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  });
}

class MockIsFeatureBranch extends Mock implements gg_publish.IsFeatureBranch {}

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
    tempDir = Directory.systemTemp.createTempSync('can_review_ticket_test_');
    ticketsDir = Directory(path.join(tempDir.path, 'tickets'))..createSync();
    ticketDir = Directory(path.join(ticketsDir.path, 'TICKR'))..createSync();
    Directory(path.join(ticketDir.path, 'A')).createSync();
    Directory(path.join(ticketDir.path, 'B')).createSync();
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('CanReviewCommand (ticket-wide)', () {
    test('fails outside any ticket folder', () async {
      final runner = CommandRunner<void>('test', 'can review ticket')
        ..addCommand(
          CanReviewCommand(
            ggLog: ggLog,
          ),
        );
      await expectLater(
        () async => await runner.run(['review', '--input', tempDir.path]),
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
      final runner = CommandRunner<void>('test', 'can review ticket')
        ..addCommand(
          CanReviewCommand(
            ggLog: ggLog,
          ),
        );
      await runner.run(['review', '--input', emptyTicket.path]);
      expect(
        messages,
        contains('⚠️ No repositories found in ticket EMPTY.'),
      );
    });

    test('checks all repos successfully', () async {
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockIsFeatureBranch = MockIsFeatureBranch();

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
        () => mockIsFeatureBranch.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => true);

      // Set status for all repos to localized
      for (final repoName in ['A', 'B']) {
        final statusFile =
            File(path.join(ticketDir.path, repoName, '.kidney_status'))
              ..createSync(recursive: true);
        statusFile.writeAsStringSync(
          jsonEncode({'status': StatusUtils.statusLocalized}),
        );
      }

      final runner = CommandRunner<void>('test', 'can review ticket')
        ..addCommand(
          CanReviewCommand(
            ggLog: ggLog,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            ggIsFeatureBranch: mockIsFeatureBranch,
          ),
        );
      await runner.run(['review', '--input', ticketDir.path]);
      expect(
        messages,
        contains('✅ All repositories in ticket TICKR can be reviewed.'),
      );
      verify(
        () => mockIsFeatureBranch.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).called(2);
    });

    test('fails if a repo is not on a feature branch', () async {
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockIsFeatureBranch = MockIsFeatureBranch();

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

      // A is on a feature branch, B is not
      when(
        () => mockIsFeatureBranch.get(
          directory: any(
            named: 'directory',
            that: predicate<Directory>(
              (d) => path.basename(d.path) == 'A',
            ),
          ),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => mockIsFeatureBranch.get(
          directory: any(
            named: 'directory',
            that: predicate<Directory>(
              (d) => path.basename(d.path) == 'B',
            ),
          ),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => false);

      final runner = CommandRunner<void>('test', 'can review ticket')
        ..addCommand(
          CanReviewCommand(
            ggLog: ggLog,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            ggIsFeatureBranch: mockIsFeatureBranch,
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
            'The following repos are not on a feature branch:',
          ),
        ),
        isTrue,
      );
      expect(messages.any((m) => m.contains(' - B')), isTrue);
    });

    test('fails if uncommitted changes', () async {
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockIsFeatureBranch = MockIsFeatureBranch();

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
        () => mockIsFeatureBranch.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => true);

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

      // Set status for all repos to localized
      for (final repoName in ['A', 'B']) {
        final statusFile =
            File(path.join(ticketDir.path, repoName, '.kidney_status'))
              ..createSync(recursive: true);
        statusFile.writeAsStringSync(
          jsonEncode({'status': StatusUtils.statusLocalized}),
        );
      }

      final runner = CommandRunner<void>('test', 'can review ticket')
        ..addCommand(
          CanReviewCommand(
            ggLog: ggLog,
            sortedProcessingList: mockSortedProcessingList,
            processRunner: mockProcessRunner.call,
            ggIsFeatureBranch: mockIsFeatureBranch,
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
          (m) => m.contains('Uncommitted changes '
              'found in the following repos:'),
        ),
        isTrue,
      );
      expect(messages.any((m) => m.contains(' - A')), isTrue);
    });

    test('uses quiet taskLog when verbose is false', () async {
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockProcessRunner = MockProcessRunner();
      final mockIsFeatureBranch = MockIsFeatureBranch();

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
          ['status', '--porcelain'],
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      when(
        () => mockIsFeatureBranch.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => true);

      final localMessages = <String>[];
      void localLog(String msg) => localMessages.add(rmConsoleColors(msg));

      final command = CanReviewCommand(
        ggLog: localLog,
        sortedProcessingList: mockSortedProcessingList,
        processRunner: mockProcessRunner.call,
        ggIsFeatureBranch: mockIsFeatureBranch,
      );

      await command.get(
        directory: ticketDir,
        ggLog: localLog,
        verbose: false,
      );

      expect(
        localMessages.last,
        contains('✅ All repositories in ticket TICKR can be reviewed.'),
      );
    });
  });
}
