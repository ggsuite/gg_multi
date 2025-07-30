// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:gg/gg.dart' as gg;
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:kidney_core/src/commands/do/merge.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:kidney_core/src/backend/status_utils.dart';

import '../../rm_console_colors_helper.dart';

class MockGgCanCommit extends Mock implements gg.CanCommit {}

class MockGgDoCommit extends Mock implements gg.DoCommit {}

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
    tempDir = Directory.systemTemp.createTempSync('do_merge_ticket_test_');
    ticketsDir = Directory(path.join(tempDir.path, 'tickets'))..createSync();
    ticketDir = Directory(path.join(ticketsDir.path, 'TICKM'))..createSync();
    Directory(path.join(ticketDir.path, 'A')).createSync();
    Directory(path.join(ticketDir.path, 'B')).createSync();
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('DoMergeCommand (ticket-wide)', () {
    test('fails outside any ticket folder', () async {
      final runner = CommandRunner<void>('test', 'do merge ticket')
        ..addCommand(
          DoMergeCommand(
            ggLog: ggLog,
          ),
        );
      await expectLater(
        () async => await runner.run(['merge', '--input', tempDir.path]),
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
        contains('Merge must be executed inside a ticket folder.'),
      );
    });

    test('logs when there are no repositories', () async {
      final emptyTicket = Directory(path.join(ticketsDir.path, 'EMPTY'))
        ..createSync();
      final runner = CommandRunner<void>('test', 'do merge ticket')
        ..addCommand(
          DoMergeCommand(
            ggLog: ggLog,
          ),
        );
      await runner.run(['merge', '--input', emptyTicket.path]);
      expect(
        messages,
        contains('⚠️ No repositories found in ticket EMPTY.'),
      );
    });

    test('merges all repos successfully', () async {
      final mockGgCanCommit = MockGgCanCommit();
      final mockGgDoCommit = MockGgDoCommit();
      final mockProcessRunner = MockProcessRunner();

      when(
        () => mockGgCanCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGgDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          updateChangeLog: any(named: 'updateChangeLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockProcessRunner(
          'git',
          any(),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      // Set initial status to git-localized for each repo
      for (final repoName in ['A', 'B']) {
        final statusFile = File(
          path.join(ticketDir.path, repoName, '.kidney_status'),
        )..createSync(recursive: true);
        statusFile.writeAsStringSync(
          jsonEncode({'status': StatusUtils.statusGitLocalized}),
        );
        var pubspecContent = 'name: $repoName\nversion: 1.2.3';
        File(path.join(ticketDir.path, repoName, 'pubspec.yaml'))
            .writeAsStringSync(pubspecContent);
      }

      final runner = CommandRunner<void>('test', 'do merge ticket')
        ..addCommand(
          DoMergeCommand(
            ggLog: ggLog,
            ggCanCommit: mockGgCanCommit,
            ggDoCommit: mockGgDoCommit,
            processRunner: mockProcessRunner.call,
          ),
        );
      await runner.run(['merge', '--input', ticketDir.path]);
      expect(
        messages,
        contains('✅ All repositories in ticket '
            'TICKM merged and pushed successfully.'),
      );
      expect(
        messages,
        contains('Merging A in ticket TICKM...'),
      );
      expect(
        messages,
        contains('Merging B in ticket TICKM...'),
      );

      // Verify status files updated
      for (final repoName in ['A', 'B']) {
        final statusFile = File(
          path.join(ticketDir.path, repoName, '.kidney_status'),
        );
        final content = jsonDecode(
          statusFile.readAsStringSync(),
        ) as Map<String, dynamic>;
        expect(content['status'], StatusUtils.statusMerged);
      }
    });

    test('aborts if status not git-localized', () async {
      final mockGgCanCommit = MockGgCanCommit();
      final mockGgDoCommit = MockGgDoCommit();
      final mockProcessRunner = MockProcessRunner();

      // Set incorrect status for A
      final statusFileA = File(path.join(ticketDir.path, 'A', '.kidney_status'))
        ..createSync(recursive: true);
      statusFileA.writeAsStringSync(jsonEncode({'status': 'wrong'}));
      var pubspecContent = 'name: A\nversion: 1.2.3';
      File(path.join(ticketDir.path, 'A', 'pubspec.yaml'))
          .writeAsStringSync(pubspecContent);

      final runner = CommandRunner<void>('test', 'do merge ticket')
        ..addCommand(
          DoMergeCommand(
            ggLog: ggLog,
            ggCanCommit: mockGgCanCommit,
            ggDoCommit: mockGgDoCommit,
            processRunner: mockProcessRunner.call,
          ),
        );
      await expectLater(
        () async => await runner.run(['merge', '--input', ticketDir.path]),
        throwsA(isA<Exception>()),
      );
      expect(
        messages.any(
          (m) => m.contains('Please execute kidney_core '
              'review before merging'),
        ),
        isTrue,
      );
      expect(
        messages.any((m) => m.contains('❌ Failed to merge A:')),
        isTrue,
      );
    });

    test('aborts on gg can commit failure', () async {
      final mockGgCanCommit = MockGgCanCommit();
      final mockGgDoCommit = MockGgDoCommit();
      final mockProcessRunner = MockProcessRunner();

      when(
        () => mockGgCanCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenThrow(Exception('can commit failed'));

      // Set initial status
      for (final repoName in ['A', 'B']) {
        final statusFile = File(
          path.join(ticketDir.path, repoName, '.kidney_status'),
        )..createSync(recursive: true);
        statusFile.writeAsStringSync(
          jsonEncode({'status': StatusUtils.statusGitLocalized}),
        );
        var pubspecContent = 'name: $repoName\nversion: 1.2.3';
        File(path.join(ticketDir.path, repoName, 'pubspec.yaml'))
            .writeAsStringSync(pubspecContent);
      }

      final runner = CommandRunner<void>('test', 'do merge ticket')
        ..addCommand(
          DoMergeCommand(
            ggLog: ggLog,
            ggCanCommit: mockGgCanCommit,
            ggDoCommit: mockGgDoCommit,
            processRunner: mockProcessRunner.call,
          ),
        );
      await expectLater(
        () async => await runner.run(['merge', '--input', ticketDir.path]),
        throwsA(isA<Exception>()),
      );
      expect(
        messages.any((m) => m.contains('❌ Failed to merge A:')),
        isTrue,
      );
      expect(
        messages.any(
          (m) => m.contains(
            '❌ Failed to merge the following repositories',
          ),
        ),
        isTrue,
      );
    });

    test('aborts on git merge failure', () async {
      final mockGgCanCommit = MockGgCanCommit();
      final mockGgDoCommit = MockGgDoCommit();
      final mockProcessRunner = MockProcessRunner();

      when(
        () => mockGgCanCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockProcessRunner(
          'git',
          any(that: contains('merge')),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(1, 1, '', 'merge error'));

      // Set initial status
      for (final repoName in ['A', 'B']) {
        final statusFile = File(
          path.join(ticketDir.path, repoName, '.kidney_status'),
        )..createSync(recursive: true);
        statusFile.writeAsStringSync(
          jsonEncode({'status': StatusUtils.statusGitLocalized}),
        );
        var pubspecContent = 'name: $repoName\nversion: 1.2.3';
        File(path.join(ticketDir.path, repoName, 'pubspec.yaml'))
            .writeAsStringSync(pubspecContent);
      }

      final runner = CommandRunner<void>('test', 'do merge ticket')
        ..addCommand(
          DoMergeCommand(
            ggLog: ggLog,
            ggCanCommit: mockGgCanCommit,
            ggDoCommit: mockGgDoCommit,
            processRunner: mockProcessRunner.call,
          ),
        );
      await expectLater(
        () async => await runner.run(['merge', '--input', ticketDir.path]),
        throwsA(isA<Exception>()),
      );
      expect(
        messages.any(
          (m) => m.contains(
            'git merge --squash failed: merge error',
          ),
        ),
        isTrue,
      );
    });

    test('prints help message', () async {
      final runner = CommandRunner<void>(
        'test',
        'Help',
      )..addCommand(DoMergeCommand(ggLog: (_) {}));

      final output = await capturePrint(
        code: () async {
          await runner.run(['merge', '--help']);
        },
      );

      expect(
        output.last,
        contains('Squash-merges the ticket branch into main'),
        reason: 'Help should mention the merge description.',
      );
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
