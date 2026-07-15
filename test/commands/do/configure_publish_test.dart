// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_one/gg_one.dart' as gg;
// ignore: lines_longer_than_80_chars
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:gg_localize_refs/gg_localize_refs.dart';
import 'package:gg_multi/src/commands/do/configure_publish.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:test/test.dart';

import '../../rm_console_colors_helper.dart';

class MockSortedProcessingList extends Mock implements SortedProcessingList {}

class MockGetVersion extends Mock implements GetVersion {}

class FakeDirectory extends Fake implements Directory {}

/// Deterministic [gg.InteractAdapter] returning queued indices and capturing
/// the option lists it is shown (to assert the version previews).
class _StubAdapter implements gg.InteractAdapter {
  _StubAdapter(this._indices);
  final List<int> _indices;
  int _call = 0;
  final List<List<String>> capturedOptions = [];

  @override
  Future<int> choose({
    required String message,
    required List<String> options,
  }) async {
    capturedOptions.add(options);
    final index = _indices[_call % _indices.length];
    _call++;
    return index;
  }
}

void main() {
  late Directory tempDir;
  late Directory ticketsDir;
  late Directory ticketDir;
  final messages = <String>[];
  final capturedInitials = <String>[];

  setUpAll(() {
    registerFallbackValue(FakeDirectory());
  });

  void ggLog(String msg) => messages.add(rmConsoleColors(msg));

  setUp(() {
    messages.clear();
    capturedInitials.clear();
    tempDir = Directory.systemTemp.createTempSync('configure_publish_test_');
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

  Node node(String name) => Node(
        name: name,
        directory: Directory(path.join(ticketDir.path, name)),
        manifest: DartPackageManifest(pubspec: Pubspec(name)),
      );

  DoConfigurePublishCommand makeCommand({
    required List<Node> repos,
    List<int> increments = const [0],
    String? version = '1.0.0',
    bool versionThrows = false,
    _StubAdapter? adapter,
    EditMessage? editMessage,
  }) {
    final sortedList = MockSortedProcessingList();
    when(
      () => sortedList.get(
        directory: any(named: 'directory'),
        ggLog: any(named: 'ggLog'),
      ),
    ).thenAnswer((_) async => repos);

    final getVersion = MockGetVersion();
    if (versionThrows) {
      when(
        () => getVersion.get(directory: any(named: 'directory')),
      ).thenThrow(Exception('no version'));
    } else {
      when(
        () => getVersion.get(directory: any(named: 'directory')),
      ).thenAnswer((_) async => version);
    }

    return DoConfigurePublishCommand(
      ggLog: ggLog,
      sortedProcessingList: sortedList,
      getVersionCommand: getVersion,
      versionSelector: gg.VersionSelector(
        adapter: adapter ?? _StubAdapter(increments),
      ),
      editMessage: editMessage ??
          (initial) async {
            capturedInitials.add(initial);
            return initial;
          },
      confirmDeleteTicket: (_) => true,
    );
  }

  group('DoConfigurePublishCommand', () {
    test('throws when not inside a ticket folder', () async {
      // The bare constructor also exercises the real default dependencies
      // (SortedProcessingList / GetVersion / VersionSelector).
      final command = DoConfigurePublishCommand(ggLog: ggLog);
      await expectLater(
        () => command.configure(directory: tempDir, ggLog: ggLog),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Not inside a ticket folder'),
          ),
        ),
      );
    });

    test('logs and writes an empty config when the ticket has no repos',
        () async {
      final emptyTicket = Directory(path.join(ticketsDir.path, 'EMPTY'))
        ..createSync();
      final command = makeCommand(repos: const []);

      final config = await command.configure(
        directory: emptyTicket,
        ggLog: ggLog,
        deleteTicket: false,
      );

      expect(messages, contains('⚠️ No repos in this ticket'));
      expect(config.repos, isEmpty);

      final file = DoConfigurePublishCommand.configFileFor(emptyTicket);
      expect(file.existsSync(), isTrue);
      final reloaded = gg.PublishConfig.load(
        configArg: file.path,
        fallbackDir: emptyTicket.path,
      );
      expect(reloaded.deleteTicket, isFalse);
      expect(reloaded.repos, isEmpty);
    });

    test('writes per-repo increment + message using the ticket description',
        () async {
      File(path.join(ticketDir.path, '.ticket'))
          .writeAsStringSync('{"description": "Ticket desc"}');
      final command = makeCommand(
        repos: [node('A'), node('B')],
        increments: [1, 0], // A -> minor, B -> patch
      );

      await command.configure(
        directory: ticketDir,
        ggLog: ggLog,
        deleteTicket: true,
      );

      final file = DoConfigurePublishCommand.configFileFor(ticketDir);
      final cfg = gg.PublishConfig.load(
        configArg: file.path,
        fallbackDir: ticketDir.path,
      );
      expect(cfg.repos['A']!.versionIncrement, 'minor');
      expect(cfg.repos['A']!.mergeMessage, 'Ticket desc');
      expect(cfg.repos['B']!.versionIncrement, 'patch');
      expect(cfg.repos['B']!.mergeMessage, 'Ticket desc');
      expect(cfg.deleteTicket, isTrue);
      // Both repos were shown the merge-message editor with the description.
      expect(capturedInitials, ['Ticket desc', 'Ticket desc']);
    });

    test('CLI run resolves the directory and prompts for delete_ticket',
        () async {
      final command = makeCommand(
        repos: [node('A')],
        increments: [2], // major
      );
      final runner = CommandRunner<void>('test', 'configure publish')
        ..addCommand(command);
      await runner.run(['configure-publish', '--input', ticketDir.path]);

      final file = DoConfigurePublishCommand.configFileFor(ticketDir);
      final cfg = gg.PublishConfig.load(
        configArg: file.path,
        fallbackDir: ticketDir.path,
      );
      expect(cfg.repos['A']!.versionIncrement, 'major');
      // No .ticket and an empty edit → generic non-empty fallback message.
      expect(cfg.repos['A']!.mergeMessage, 'Publish A');
      // confirmDeleteTicket stub returns true.
      expect(cfg.deleteTicket, isTrue);
    });

    test('falls back to the ticket description when the edit is empty',
        () async {
      File(path.join(ticketDir.path, '.ticket'))
          .writeAsStringSync('{"description": "Ticket desc"}');
      final command = makeCommand(
        repos: [node('A')],
        editMessage: (_) async => '   ', // user cleared the message
      );

      await command.configure(
        directory: ticketDir,
        ggLog: ggLog,
        deleteTicket: true,
      );

      final file = DoConfigurePublishCommand.configFileFor(ticketDir);
      final cfg = gg.PublishConfig.load(
        configArg: file.path,
        fallbackDir: ticketDir.path,
      );
      expect(cfg.repos['A']!.mergeMessage, 'Ticket desc');
    });

    group('version preview baseline', () {
      test('uses the current version when it is readable', () async {
        final adapter = _StubAdapter([0]);
        final command = makeCommand(
          repos: [node('A')],
          version: '2.5.0',
          adapter: adapter,
        );
        await command.configure(
          directory: ticketDir,
          ggLog: ggLog,
          deleteTicket: true,
        );
        expect(adapter.capturedOptions.first.first, contains('2.5.0'));
      });

      test('falls back to 0.0.0 when the version is null', () async {
        final adapter = _StubAdapter([0]);
        final command = makeCommand(
          repos: [node('A')],
          version: null,
          adapter: adapter,
        );
        await command.configure(
          directory: ticketDir,
          ggLog: ggLog,
          deleteTicket: true,
        );
        expect(adapter.capturedOptions.first.first, contains('0.0.0'));
      });

      test('falls back to 0.0.0 when reading the version throws', () async {
        final adapter = _StubAdapter([0]);
        final command = makeCommand(
          repos: [node('A')],
          versionThrows: true,
          adapter: adapter,
        );
        await command.configure(
          directory: ticketDir,
          ggLog: ggLog,
          deleteTicket: true,
        );
        expect(adapter.capturedOptions.first.first, contains('0.0.0'));
      });
    });

    group('merge-message default from .ticket', () {
      test('empty default when no .ticket file exists', () async {
        final command = makeCommand(repos: [node('A')]);
        await command.configure(
          directory: ticketDir,
          ggLog: ggLog,
          deleteTicket: true,
        );
        expect(capturedInitials, ['']);
      });

      test('empty default when .ticket is not a JSON object', () async {
        File(path.join(ticketDir.path, '.ticket')).writeAsStringSync('[]');
        final command = makeCommand(repos: [node('A')]);
        await command.configure(
          directory: ticketDir,
          ggLog: ggLog,
          deleteTicket: true,
        );
        expect(capturedInitials, ['']);
      });

      test('empty default when .ticket is malformed JSON (no crash)', () async {
        // A hand-edited / truncated .ticket must not crash configure-publish.
        File(path.join(ticketDir.path, '.ticket'))
            .writeAsStringSync('{"description":');
        final command = makeCommand(repos: [node('A')]);
        await command.configure(
          directory: ticketDir,
          ggLog: ggLog,
          deleteTicket: true,
        );
        expect(capturedInitials, ['']);
      });

      test('empty default when the description is blank', () async {
        File(path.join(ticketDir.path, '.ticket'))
            .writeAsStringSync('{"description": "   "}');
        final command = makeCommand(repos: [node('A')]);
        await command.configure(
          directory: ticketDir,
          ggLog: ggLog,
          deleteTicket: true,
        );
        expect(capturedInitials, ['']);
      });
    });

    test('refuses to clobber the progress of an unfinished publish', () async {
      final file = DoConfigurePublishCommand.configFileFor(ticketDir)
        ..createSync(recursive: true);
      file.writeAsStringSync('''
{
  "repos": {
    "A": {
      "version_increment": "patch", "merge_message": "m",
      "status": "published"
    }
  }
}
''');

      final command = makeCommand(repos: [node('A')]);
      await expectLater(
        () => command.configure(
          directory: ticketDir,
          ggLog: ggLog,
          deleteTicket: true,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('unfinished publish left progress'),
          ),
        ),
      );
      // The progress markers survive untouched.
      expect(file.readAsStringSync(), contains('"published"'));
    });

    test('overwrites a progress-free config file without complaint', () async {
      final file = DoConfigurePublishCommand.configFileFor(ticketDir)
        ..createSync(recursive: true);
      file.writeAsStringSync(
        '{"version_increment":"patch","merge_message":"old"}',
      );

      final command = makeCommand(repos: [node('A')]);
      final config = await command.configure(
        directory: ticketDir,
        ggLog: ggLog,
        deleteTicket: true,
        defaultMergeMessage: 'new',
      );

      expect(config.repos['A']!.mergeMessage, 'new');
    });

    group('merge-message default from -m', () {
      test('-m seeds the prompt and is the merge message', () async {
        final command = makeCommand(repos: [node('A')]);
        await command.configure(
          directory: ticketDir,
          ggLog: ggLog,
          deleteTicket: true,
          defaultMergeMessage: 'CLI msg',
        );
        // No .ticket; -m pre-fills the prompt and becomes the message.
        expect(capturedInitials, ['CLI msg']);

        final file = DoConfigurePublishCommand.configFileFor(ticketDir);
        final cfg = gg.PublishConfig.load(
          configArg: file.path,
          fallbackDir: ticketDir.path,
        );
        expect(cfg.repos['A']!.mergeMessage, 'CLI msg');
      });

      test('-m takes precedence over the ticket description', () async {
        File(path.join(ticketDir.path, '.ticket'))
            .writeAsStringSync('{"description": "Ticket desc"}');
        final command = makeCommand(repos: [node('A')]);
        await command.configure(
          directory: ticketDir,
          ggLog: ggLog,
          deleteTicket: true,
          defaultMergeMessage: '  CLI msg  ',
        );
        // -m wins and is trimmed.
        expect(capturedInitials, ['CLI msg']);
      });

      test('a blank -m falls back to the ticket description', () async {
        File(path.join(ticketDir.path, '.ticket'))
            .writeAsStringSync('{"description": "Ticket desc"}');
        final command = makeCommand(repos: [node('A')]);
        await command.configure(
          directory: ticketDir,
          ggLog: ggLog,
          deleteTicket: true,
          defaultMergeMessage: '   ',
        );
        expect(capturedInitials, ['Ticket desc']);
      });

      test('CLI --message flows through to the merge message', () async {
        final command = makeCommand(
          repos: [node('A')],
          increments: [0],
        );
        final runner = CommandRunner<void>('test', 'configure publish')
          ..addCommand(command);
        await runner.run(
          ['configure-publish', '--input', ticketDir.path, '-m', 'CLI seed'],
        );

        final file = DoConfigurePublishCommand.configFileFor(ticketDir);
        final cfg = gg.PublishConfig.load(
          configArg: file.path,
          fallbackDir: ticketDir.path,
        );
        expect(cfg.repos['A']!.mergeMessage, 'CLI seed');
      });
    });
  });
}
