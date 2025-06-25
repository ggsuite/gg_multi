// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:test/test.dart';
import 'package:kidney_core/src/commands/create/ticket.dart';
import 'package:path/path.dart' as path;

import '../../rm_console_colors_helper.dart';

void main() {
  group('TicketCommand', () {
    late Directory tempDir;
    late CommandRunner<void> runner;
    final messages = <String>[];

    void ggLog(String msg) {
      messages.add(rmConsoleColors(msg));
    }

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('ticket_test_');
      runner = CommandRunner<void>('test', 'TicketCommand Test')
        ..addCommand(
          TicketCommand(
            ggLog: ggLog,
            rootPath: tempDir.path,
            directoryFactory: (p) => Directory(p),
          ),
        );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('creates folder and writes .ticket file', () async {
      const issueId = 'CDM-128';
      const description = 'Fix some ugly bug';
      final ticketRelPath = path.join('tickets', issueId);

      await runner.run([
        'ticket',
        issueId,
        '-m',
        description,
      ]);

      final ticketDir = Directory(
        path.join(
          tempDir.path,
          'tickets',
          issueId,
        ),
      );
      expect(ticketDir.existsSync(), isTrue);

      final ticketFile = File(
        path.join(
          ticketDir.path,
          '.ticket',
        ),
      );
      expect(ticketFile.existsSync(), isTrue);

      final content = ticketFile.readAsStringSync();
      final data = jsonDecode(content) as Map<String, dynamic>;
      expect(data['issue_id'], equals(issueId));
      expect(data['description'], equals(description));

      expect(
        messages,
        contains(
          'Created ticket $issueId at $ticketRelPath',
        ),
      );
      expect(
        messages,
        contains('Execute "cd $ticketRelPath" '
            'to enter the ticket workspace.'),
      );
    });

    test('does not create ticket if it already exists', () async {
      const issueId = 'DUP-1';
      const description = 'duplicate ticket';
      final ticketRelPath = path.join('tickets', issueId);

      // First creation
      await runner.run([
        'ticket',
        issueId,
        '-m',
        description,
      ]);
      final ticketDir = Directory(
        path.join(
          tempDir.path,
          'tickets',
          issueId,
        ),
      );
      final ticketFile = File(
        path.join(
          ticketDir.path,
          '.ticket',
        ),
      );
      expect(ticketFile.existsSync(), isTrue);

      // Try to create same ticket again
      messages.clear();
      await runner.run([
        'ticket',
        issueId,
        '-m',
        description,
      ]);
      // Existing file still exists and was not modified again
      expect(ticketFile.existsSync(), isTrue);

      expect(
        messages,
        contains(
          'Error: Ticket $issueId already exists at $ticketRelPath',
        ),
      );
    });

    test('throws UsageException when missing issue id', () async {
      await expectLater(
        runner.run(['ticket', '-m', 'desc']),
        throwsA(isA<UsageException>()),
      );
    });

    test('creates ticket with empty description when message is omitted',
        () async {
      const issueId = 'NO-DESC-1';

      await runner.run(['ticket', issueId]);

      final ticketDir = Directory(
        path.join(
          tempDir.path,
          'tickets',
          issueId,
        ),
      );
      expect(ticketDir.existsSync(), isTrue);

      final ticketFile = File(
        path.join(
          ticketDir.path,
          '.ticket',
        ),
      );
      expect(ticketFile.existsSync(), isTrue);

      final content = ticketFile.readAsStringSync();
      final data = jsonDecode(content) as Map<String, dynamic>;
      expect(data['issue_id'], equals(issueId));
      expect(data['description'], equals(''));
    });

    test('prints help when --help is passed', () async {
      final output = await capturePrint(
        code: () async {
          await runner.run(['ticket', '--help']);
        },
      );
      expect(
        output.first,
        contains('Create a ticket folder and save ticket data as JSON.'),
      );
    });
  });
}
