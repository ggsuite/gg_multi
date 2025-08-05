// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg/gg.dart' as gg;
import 'package:kidney_core/src/backend/constants.dart';
import 'package:kidney_core/src/backend/git_platform.dart' hide ProcessRunner;
import 'package:kidney_core/src/backend/organization.dart';
import 'package:kidney_core/src/backend/status_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:kidney_core/src/commands/kidney_add.dart';
import 'package:kidney_core/src/backend/git_handler.dart' hide ProcessRunner;
import 'package:gg_localize_refs/gg_localize_refs.dart';

import '../rm_console_colors_helper.dart';

// Create a mock for GitCloner
class MockGitCloner extends Mock implements GitHandler {}

class MockGitHubPlatform extends Mock implements GitHubPlatform {}

class MockLocalizeRefs extends Mock implements LocalizeRefs {}

class MockProcessRunner extends Mock {
  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  });
}

class MockGgDoCommit extends Mock implements gg.DoCommit {}

void main() {
  group('AddCommand', () {
    late MockGitCloner mockGitCloner;
    late List<String> logMessages;
    late CommandRunner<void> runner;
    late Directory tempDir;
    late String masterWorkspacePath;

    void ggLog(String message) {
      logMessages.add(rmConsoleColors(message));
    }

    void createRunner({
      String? executionPath,
      Future<void> Function(String repoPath)? localizeRefsFn,
      ProcessRunner? processRunner,
      gg.DoCommit? ggDoCommit,
    }) {
      runner = CommandRunner<void>('test', 'Test for AddCommand');
      runner.addCommand(
        AddCommand(
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          processRunner: processRunner,
          masterWorkspacePath: masterWorkspacePath,
          executionPath: executionPath ?? Directory.current.path,
          ggDoCommit: ggDoCommit,
        ),
      );
    }

    setUp(() {
      mockGitCloner = MockGitCloner();
      logMessages = [];
      registerFallbackValue(Directory(''));
      when(() => mockGitCloner.cloneRepo(any(), any()))
          .thenAnswer((_) async {});
      tempDir = Directory.systemTemp.createTempSync('add_test');
      masterWorkspacePath = path.join(tempDir.path, kidneyMasterFolder);
      Directory(masterWorkspacePath).createSync(recursive: true);
      createRunner();
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should clone single repository when target is a repo name', () async {
      await runner.run(['add', 'myrepo']);
      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/myrepo/myrepo.git',
          any(),
        ),
      ).called(1);
      expect(
        logMessages,
        equals([
          'Added repository myrepo from https://github.com/myrepo/myrepo.git',
        ]),
      );

      // Integration check: .organizations file correctly updated
      final orgFile = File(path.join(masterWorkspacePath, '.organizations'));
      expect(orgFile.existsSync(), isTrue);
      final orgMap = (jsonDecode(orgFile.readAsStringSync()) as List<dynamic>)
          .map((e) => Organization.fromMap(e as Map<String, dynamic>))
          .toList();
      expect(orgMap.first.url, 'https://github.com/myrepo/');
    });

    test(
      'should clone single repository when target is in username/repo format',
      () async {
        await runner.run(['add', 'testuser/testrepo']);
        verify(
          () => mockGitCloner.cloneRepo(
            'https://github.com/testuser/testrepo.git',
            any(),
          ),
        ).called(1);
        expect(
          logMessages,
          equals([
            'Added repository testrepo from '
                'https://github.com/testuser/testrepo.git',
          ]),
        );
      },
    );

    test(
      'should clone single repository when target '
      'is a full repository URL with .git',
      () async {
        const repoUrl = 'https://gitlab.com/someuser/somerepo.git';
        await runner.run(['add', repoUrl]);
        verify(() => mockGitCloner.cloneRepo(repoUrl, any())).called(1);
        expect(
          logMessages,
          equals([
            'Added repository somerepo from $repoUrl',
          ]),
        );
      },
    );

    test(
      'should clone single repository when '
      'target is a git SSH URL',
      () async {
        const repoUrl = 'git@github.com:ggsuite/kidney_core.git';
        await runner.run(['add', repoUrl]);
        verify(
          () => mockGitCloner.cloneRepo(
            repoUrl,
            any(),
          ),
        ).called(1);
        expect(
          logMessages,
          equals([
            'Added repository kidney_core from $repoUrl',
          ]),
        );
      },
    );

    test(
      'should clone single repository when '
      'target is a URL without .git',
      () async {
        const urlWithoutGit = 'https://github.com/ggsuite/kidney_core';
        await runner.run(['add', urlWithoutGit]);
        verify(
          () => mockGitCloner.cloneRepo(
            'https://github.com/ggsuite/kidney_core.git',
            any(),
          ),
        ).called(1);
        expect(
          logMessages,
          equals([
            'Added repository kidney_core from '
                'https://github.com/ggsuite/kidney_core.git',
          ]),
        );
      },
    );

    test(
      'should clone single repository when '
      'target is a URL with trailing #',
      () async {
        const urlWithHash = 'https://github.com/ggsuite/kidney_core#';
        await runner.run(['add', urlWithHash]);
        verify(
          () => mockGitCloner.cloneRepo(
            'https://github.com/ggsuite/kidney_core.git',
            any(),
          ),
        ).called(1);
        expect(
          logMessages,
          equals([
            'Added repository kidney_core from '
                'https://github.com/ggsuite/kidney_core.git',
          ]),
        );
      },
    );

    test(
      'should clone repositories when '
      'target is an organization URL',
      () async {
        final repoList = [
          {
            'name': 'repo1',
            'clone_url': 'https://github.com/myorganization/repo1.git',
          },
          {
            'name': 'repo2',
            'clone_url': 'https://github.com/myorganization/repo2.git',
          },
        ];

        final mockGitHubPlatform = MockGitHubPlatform();
        when(
          () => mockGitHubPlatform.fetchOrgRepos(
            any(),
            client: any(named: 'client'),
          ),
        ).thenAnswer((_) async => repoList);

        final orgRunner = CommandRunner<void>(
          'test',
          'Test for AddCommand Org',
        );
        orgRunner.addCommand(
          AddCommand(
            ggLog: ggLog,
            gitCloner: mockGitCloner,
            gitHubPlatform: mockGitHubPlatform,
            masterWorkspacePath: masterWorkspacePath,
          ),
        );
        const orgUrl = 'https://github.com/myorganization';
        await orgRunner.run(['add', orgUrl]);
        verify(
          () => mockGitCloner.cloneRepo(
            'https://github.com/myorganization/repo1.git',
            any(),
          ),
        ).called(1);
        verify(
          () => mockGitCloner.cloneRepo(
            'https://github.com/myorganization/repo2.git',
            any(),
          ),
        ).called(1);
        expect(
          logMessages,
          containsAllInOrder([
            'Added repository repo1 from '
                'https://github.com/myorganization/repo1.git',
            'Added repository repo2 from '
                'https://github.com/myorganization/repo2.git',
          ]),
        );
      },
    );

    test('should throw UsageException when target parameter is missing',
        () async {
      expect(
        () => runner.run(['add']),
        throwsA(isA<UsageException>()),
      );
    });

    test('should throw exception when invalid organization URL is provided',
        () async {
      final invalidRunner = CommandRunner<void>(
        'test',
        'Test for AddCommand Invalid Org',
      );
      invalidRunner.addCommand(
        AddCommand(
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          masterWorkspacePath: masterWorkspacePath,
        ),
      );
      const invalidOrgUrl = 'https://github.com/';
      expect(
        () => invalidRunner.run(['add', invalidOrgUrl]),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'should log already added when destination '
      'exists and --force not provided',
      () async {
        const repoName = 'kidney_core';
        final destination = path.join(masterWorkspacePath, repoName);
        Directory(destination).createSync(recursive: true);
        File(path.join(destination, 'dummy.txt')).writeAsStringSync('data');

        await runner.run(['add', 'git@github.com:ggsuite/kidney_core.git']);

        verifyNever(() => mockGitCloner.cloneRepo(any(), any()));
        expect(logMessages, contains('$repoName already added.'));
      },
    );

    test(
      'should force clone repository when --force '
      'is provided even if destination exists',
      () async {
        const repoName = 'kidney_core';
        final destination = path.join(masterWorkspacePath, repoName);
        Directory(destination).createSync(recursive: true);
        File(path.join(destination, 'dummy.txt')).writeAsStringSync('data');

        await runner
            .run(['add', 'git@github.com:ggsuite/kidney_core.git', '--force']);

        verify(() => mockGitCloner.cloneRepo(any(), any())).called(1);
      },
    );

    test(
      'copies repo into ticket workspace and relocalizes ticket (two passes)',
      () async {
        // Arrange: create a repo with a file and pubspec in master
        const repoName = 'testRepoCommit';
        final repoDir = Directory(
          path.join(masterWorkspacePath, repoName),
        )..createSync(recursive: true);
        File(path.join(repoDir.path, 'target.txt'))
            .writeAsStringSync('content');
        const pubspecContent = '''
name: project123
version: 1.0.0
dependencies:
  json_dart: ^3.5.2
dev_dependencies:
  json_serializer: ^1.4.2
''';
        final pubspecFile = File(path.join(repoDir.path, 'pubspec.yaml'));
        pubspecFile.writeAsStringSync(pubspecContent);

        // Setup ticket workspace
        final ticketDir = Directory(
          path.join(tempDir.path, kidneyTicketFolder, 'TICKET'),
        )..createSync(recursive: true);

        final mockDoCommit = MockGgDoCommit();
        when(
          () => mockDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            logType: any(named: 'logType'),
            updateChangeLog: any(named: 'updateChangeLog'),
          ),
        ).thenAnswer((_) async {});

        createRunner(
          executionPath: ticketDir.path,
          ggDoCommit: mockDoCommit,
        );

        // Act
        await runner.run(['add', repoName]);

        // Assert: ensure the target file has been copied
        final copiedFileInTicket = File(
          path.join(ticketDir.path, repoName, 'target.txt'),
        );
        expect(copiedFileInTicket.existsSync(), isTrue);

        // Verify commit was called with the expected git message
        verify(
          () => mockDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: 'kidney: changed references to git',
            logType: any(named: 'logType'),
            updateChangeLog: any(named: 'updateChangeLog'),
          ),
        ).called(greaterThanOrEqualTo(1));

        final statusFile = File(
          path.join(ticketDir.path, repoName, '.kidney_status'),
        );
        expect(statusFile.existsSync(), isTrue);
        final content =
            jsonDecode(statusFile.readAsStringSync()) as Map<String, dynamic>;
        expect(content['status'], StatusUtils.statusLocalized);

        // Logs should indicate un/localize and commit somewhere
        expect(
          logMessages.any((m) => m.contains('Unlocalized refs for')),
          isTrue,
        );
        expect(
          logMessages.any((m) => m.contains('Localized refs for')),
          isTrue,
        );
        expect(
          logMessages.any((m) => m.contains('Committed')),
          isTrue,
        );
      },
    );

    // New test to cover error when master workspace missing repository
    test('logs error when repo not found in master workspace', () async {
      final ticketDir = Directory(
        path.join(tempDir.path, kidneyTicketFolder, 'TICKET-MISSING'),
      )..createSync(recursive: true);
      createRunner(executionPath: ticketDir.path);
      await runner.run(['add', 'nonexistent']);
      expect(
        logMessages,
        contains('Repository nonexistent not found in master workspace.'),
      );
    });

    test(
      'logs already exists in ticket workspace if copied before',
      () async {
        const repoName = 'someGreyRepo';
        final repoDir = Directory(path.join(masterWorkspacePath, repoName))
          ..createSync(recursive: true);
        File(path.join(repoDir.path, 'foo.txt')).writeAsStringSync('hi');

        final ticketDir = Directory(
          path.join(tempDir.path, kidneyTicketFolder, 'ALREADY'),
        )..createSync(recursive: true);
        createRunner(executionPath: ticketDir.path);
        final destination = Directory(path.join(ticketDir.path, repoName));
        destination.createSync(recursive: true);
        File(path.join(destination.path, 'foo.txt')).writeAsStringSync('hi');

        await runner.run(['add', repoName]);

        expect(
          logMessages,
          contains('$repoName already exists in ticket workspace.'),
        );
      },
    );

    test('does not set status if localization fails in ticket relocalization',
        () async {
      const repoName = 'failStatusRepo';
      final repoDir = Directory(path.join(masterWorkspacePath, repoName))
        ..createSync(recursive: true);
      File(path.join(repoDir.path, 'dummy.txt')).writeAsStringSync('data');

      final ticketDir = Directory(
        path.join(tempDir.path, kidneyTicketFolder, 'TICKET-FAIL'),
      )..createSync(recursive: true);
      final mockDoCommit = MockGgDoCommit();
      when(
        () => mockDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          logType: any(named: 'logType'),
          updateChangeLog: any(named: 'updateChangeLog'),
        ),
      ).thenAnswer((_) async {});

      createRunner(executionPath: ticketDir.path, ggDoCommit: mockDoCommit);

      await runner.run(['add', repoName]);

      final statusFile = File(
        path.join(ticketDir.path, repoName, '.kidney_status'),
      );
      expect(statusFile.existsSync(), isFalse);
      // Commit must not be called when localization fails early
      // (our environment without proper project roots will cause localization
      // to fail inside the command). So ensure there is no commit recorded.
      verifyNever(
        () => mockDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          logType: any(named: 'logType'),
          updateChangeLog: any(named: 'updateChangeLog'),
        ),
      );
    });

    group('dart pub get in _addRepoToTicket', () {
      late MockProcessRunner mockProcessRunner;
      late Directory ticketDir;
      late Directory repoDir;
      const repoName = 'pubgetRepo';

      setUp(() async {
        mockProcessRunner = MockProcessRunner();
        repoDir = Directory(path.join(masterWorkspacePath, repoName))
          ..createSync(recursive: true);
        File(path.join(repoDir.path, 'dummy.txt')).writeAsStringSync('data');
        ticketDir = Directory(
          path.join(tempDir.path, kidneyTicketFolder, 'TICKET-PUBGET'),
        )..createSync(recursive: true);
        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockProcessRunner.call,
        );
      });

      test('executes dart pub get if pubspec.yaml exists and logs success',
          () async {
        File(path.join(repoDir.path, 'pubspec.yaml'))
            .writeAsStringSync('name: pubgetRepo');
        when(
          () => mockProcessRunner(
            'dart',
            ['pub', 'get'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'Pub get success', ''));

        await runner.run(['add', repoName]);

        verify(
          () => mockProcessRunner(
            'dart',
            ['pub', 'get'],
            workingDirectory: path.join(ticketDir.path, repoName),
          ),
        ).called(1);
        expect(
          logMessages,
          contains('Executed dart pub get in $repoName.'),
        );
      });

      test('logs error if dart pub get fails', () async {
        File(path.join(repoDir.path, 'pubspec.yaml'))
            .writeAsStringSync('name: pubgetRepo');
        when(
          () => mockProcessRunner(
            'dart',
            ['pub', 'get'],
            workingDirectory: any(named: 'workingDirectory'),
          ),
        ).thenAnswer((_) async => ProcessResult(2, 1, '', 'Pub get error'));

        await runner.run(['add', repoName]);

        expect(
          logMessages.any(
            (m) => m.contains('Failed to execute dart pub get '
                'in $repoName: Pub get error'),
          ),
          isTrue,
        );
      });
    });

    test('commit failures are logged and aborts immediately', () async {
      // Arrange: create a repo with a file and pubspec
      const repoName = 'commitFailRepo';
      final repoDir = Directory(path.join(masterWorkspacePath, repoName))
        ..createSync(recursive: true);
      File(path.join(repoDir.path, 'dummy.txt')).writeAsStringSync('data');
      File(path.join(repoDir.path, 'pubspec.yaml'))
          .writeAsStringSync('name: x');

      final ticketDir = Directory(
        path.join(tempDir.path, kidneyTicketFolder, 'TICKET-COMMIT-FAIL'),
      )..createSync(recursive: true);

      final mockDoCommit = MockGgDoCommit();
      when(
        () => mockDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          logType: any(named: 'logType'),
          updateChangeLog: any(named: 'updateChangeLog'),
        ),
      ).thenThrow(Exception('commit error'));

      createRunner(executionPath: ticketDir.path, ggDoCommit: mockDoCommit);

      await expectLater(
        () async => await runner.run(['add', repoName]),
        throwsA(isA<Exception>()),
      );

      expect(
        logMessages.any(
          (m) => m.contains(
            'Failed to commit $repoName: Exception: commit error',
          ),
        ),
        isTrue,
      );
    });

    test('clones multiple repositories when multiple targets provided',
        () async {
      when(() => mockGitCloner.cloneRepo(any(), any()))
          .thenAnswer((_) async {});
      await runner.run(['add', 'repoA', 'repoB']);
      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/repoA/repoA.git',
          any(),
        ),
      ).called(1);
      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/repoB/repoB.git',
          any(),
        ),
      ).called(1);
      expect(
        logMessages,
        contains('Added repository repoA from '
            'https://github.com/repoA/repoA.git'),
      );
      expect(
        logMessages,
        contains('Added repository repoB from '
            'https://github.com/repoB/repoB.git'),
      );
    });
  });
}
