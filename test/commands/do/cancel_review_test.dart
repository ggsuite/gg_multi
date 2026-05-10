// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart' as gg;
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_localize_refs/gg_localize_refs.dart';
import 'package:gg_multi/src/backend/status_utils.dart';
import 'package:gg_multi/src/commands/do/cancel_review.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:test/test.dart';

import '../../rm_console_colors_helper.dart';

class MockSortedProcessingList extends Mock implements SortedProcessingList {}

class MockLocalizeRefs extends Mock implements ChangeRefsToLocal {}

class MockGgDoCommit extends Mock implements gg.DoCommit {}

class MockProcessRunner extends Mock {
  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  });
}

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
      'do_cancel_review_ticket_test_',
    );
    ticketsDir = Directory(path.join(tempDir.path, 'tickets'))..createSync();
    ticketDir = Directory(path.join(ticketsDir.path, 'TICKCR'))..createSync();
    Directory(path.join(ticketDir.path, 'A')).createSync();
    Directory(path.join(ticketDir.path, 'B')).createSync();
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('DoCancelReviewCommand (ticket-wide)', () {
    test('fails outside any ticket folder', () async {
      final runner = CommandRunner<void>('test', 'do cancel-review ticket')
        ..addCommand(
          DoCancelReviewCommand(
            ggLog: ggLog,
          ),
        );
      await expectLater(
        () async => await runner.run([
          'cancel-review',
          '--input',
          tempDir.path,
        ]),
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
      final runner = CommandRunner<void>('test', 'do cancel-review ticket')
        ..addCommand(
          DoCancelReviewCommand(
            ggLog: ggLog,
          ),
        );
      await runner.run([
        'cancel-review',
        '--input',
        emptyTicket.path,
      ]);
      expect(
        messages,
        contains('⚠️ No repositories found in ticket EMPTY.'),
      );
    });

    test('relocalizes and commits all repos successfully', () async {
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockLocalizeRefs = MockLocalizeRefs();
      final mockGgDoCommit = MockGgDoCommit();

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
        () => mockLocalizeRefs.get(
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

      final runner = CommandRunner<void>('test', 'do cancel-review ticket')
        ..addCommand(
          DoCancelReviewCommand(
            ggLog: ggLog,
            localizeRefs: mockLocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            ggDoCommit: mockGgDoCommit,
          ),
        );

      await runner.run([
        'cancel-review',
        '--verbose',
        '--input',
        ticketDir.path,
      ]);

      verify(
        () => mockLocalizeRefs.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).called(2);

      verify(
        () => mockGgDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: 'gg_multi: changed references to local',
          force: true,
        ),
      ).called(2);

      for (final repoName in ['A', 'B']) {
        final statusFile = File(
          path.join(ticketDir.path, repoName, '.gg_multi_status'),
        );
        expect(statusFile.existsSync(), isTrue);
        final content = jsonDecode(
          statusFile.readAsStringSync(),
        ) as Map<String, dynamic>;
        expect(content['status'], StatusUtils.statusLocalized);
      }

      expect(
        messages,
        contains(
          '✅ All repositories in ticket TICKCR were localized '
          'back to local paths and committed.',
        ),
      );
    });

    test('fails and logs when localize fails', () async {
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockLocalizeRefs = MockLocalizeRefs();
      final mockGgDoCommit = MockGgDoCommit();

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
        () => mockLocalizeRefs.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenThrow(Exception('localize failed'));

      final runner = CommandRunner<void>('test', 'do cancel-review ticket')
        ..addCommand(
          DoCancelReviewCommand(
            ggLog: ggLog,
            localizeRefs: mockLocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            ggDoCommit: mockGgDoCommit,
          ),
        );

      await expectLater(
        () async => await runner.run([
          'cancel-review',
          '--verbose',
          '--input',
          ticketDir.path,
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains(
              'Failed to cancel review for some repositories in ticket TICKCR',
            ),
          ),
        ),
      );

      expect(
        messages.any(
          (m) => m.contains(
            'Failed to localize refs to local paths for A: '
            'Exception: localize failed',
          ),
        ),
        isTrue,
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

    test('fails and logs when commit fails', () async {
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockLocalizeRefs = MockLocalizeRefs();
      final mockGgDoCommit = MockGgDoCommit();

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
        () => mockLocalizeRefs.get(
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
      ).thenThrow(Exception('commit failed'));

      final runner = CommandRunner<void>('test', 'do cancel-review ticket')
        ..addCommand(
          DoCancelReviewCommand(
            ggLog: ggLog,
            localizeRefs: mockLocalizeRefs,
            sortedProcessingList: mockSortedProcessingList,
            ggDoCommit: mockGgDoCommit,
          ),
        );

      await expectLater(
        () async => await runner.run([
          'cancel-review',
          '--verbose',
          '--input',
          ticketDir.path,
        ]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains(
              'Failed to cancel review for some repositories in ticket TICKCR',
            ),
          ),
        ),
      );

      expect(
        messages.any(
          (m) => m.contains('Failed to commit A: Exception: commit failed'),
        ),
        isTrue,
      );
    });

    test(
      'runs npm install for typescript repos after relocalize, logs success',
      () async {
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockLocalizeRefs = MockLocalizeRefs();
        final mockGgDoCommit = MockGgDoCommit();
        final mockProcessRunner = MockProcessRunner();

        final repoADir = Directory(path.join(ticketDir.path, 'A'));
        File(path.join(repoADir.path, 'package.json'))
            .writeAsStringSync(jsonEncode(<String, dynamic>{'name': 'A'}));
        File(path.join(repoADir.path, 'tsconfig.json')).writeAsStringSync('{}');

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
          () => mockLocalizeRefs.get(
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
          () => mockProcessRunner(
            'npm',
            ['install'],
            workingDirectory: repoADir.path,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        final runner = CommandRunner<void>('test', 'do cancel-review ticket')
          ..addCommand(
            DoCancelReviewCommand(
              ggLog: ggLog,
              localizeRefs: mockLocalizeRefs,
              sortedProcessingList: mockSortedProcessingList,
              ggDoCommit: mockGgDoCommit,
              processRunner: mockProcessRunner.call,
            ),
          );

        await runner.run([
          'cancel-review',
          '--verbose',
          '--input',
          ticketDir.path,
        ]);

        expect(
          messages.any((m) => m.contains('Executed npm install in A.')),
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
      'fails and logs when npm install fails for typescript repos',
      () async {
        final mockSortedProcessingList = MockSortedProcessingList();
        final mockLocalizeRefs = MockLocalizeRefs();
        final mockGgDoCommit = MockGgDoCommit();
        final mockProcessRunner = MockProcessRunner();

        final repoADir = Directory(path.join(ticketDir.path, 'A'));
        File(path.join(repoADir.path, 'package.json'))
            .writeAsStringSync(jsonEncode(<String, dynamic>{'name': 'A'}));
        File(path.join(repoADir.path, 'tsconfig.json')).writeAsStringSync('{}');

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
          () => mockLocalizeRefs.get(
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
          () => mockProcessRunner(
            'npm',
            ['install'],
            workingDirectory: repoADir.path,
          ),
        ).thenAnswer(
          (_) async => ProcessResult(1, 1, '', 'install error'),
        );

        final runner = CommandRunner<void>('test', 'do cancel-review ticket')
          ..addCommand(
            DoCancelReviewCommand(
              ggLog: ggLog,
              localizeRefs: mockLocalizeRefs,
              sortedProcessingList: mockSortedProcessingList,
              ggDoCommit: mockGgDoCommit,
              processRunner: mockProcessRunner.call,
            ),
          );

        await expectLater(
          () async => await runner.run([
            'cancel-review',
            '--verbose',
            '--input',
            ticketDir.path,
          ]),
          throwsA(isA<Exception>()),
        );

        expect(
          messages.any(
            (m) => m.contains('Failed to execute npm install in A: '
                'install error'),
          ),
          isTrue,
        );
      },
    );

    test('uses quiet taskLog when verbose is false', () async {
      final mockSortedProcessingList = MockSortedProcessingList();
      final mockLocalizeRefs = MockLocalizeRefs();
      final mockGgDoCommit = MockGgDoCommit();

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
        () => mockLocalizeRefs.get(
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

      final localMessages = <String>[];

      void localLog(String msg) {
        localMessages.add(rmConsoleColors(msg));
      }

      final command = DoCancelReviewCommand(
        ggLog: localLog,
        localizeRefs: mockLocalizeRefs,
        sortedProcessingList: mockSortedProcessingList,
        ggDoCommit: mockGgDoCommit,
      );

      await command.get(
        directory: ticketDir,
        ggLog: localLog,
        verbose: false,
      );

      expect(
        localMessages.any(
          (m) => m.contains(
            'Setting dependencies back to local paths and committing',
          ),
        ),
        isTrue,
      );
      expect(
        localMessages.any(
          (m) => m.contains(
            '✅ Setting dependencies back to local paths and committing',
          ),
        ),
        isTrue,
      );
    });
  });
}
