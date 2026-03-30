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
import 'package:kidney_core/src/backend/constants.dart';
import 'package:kidney_core/src/backend/git_platform.dart' hide ProcessRunner;
import 'package:kidney_core/src/backend/organization.dart';
import 'package:kidney_core/src/backend/status_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:kidney_core/src/commands/do/add.dart';
import 'package:kidney_core/src/backend/git_handler.dart' hide ProcessRunner;
import 'package:gg_localize_refs/gg_localize_refs.dart';
import 'package:gg_local_package_dependencies/gg_local_package_dependencies.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:kidney_core/src/backend/repository.dart';

import '../../rm_console_colors_helper.dart';

class MockGitCloner extends Mock implements GitHandler {}

class MockGitHubPlatform extends Mock implements GitHubPlatform {}

class MockLocalizeRefs extends Mock implements ChangeRefsToLocal {}

class MockProcessRunner extends Mock {
  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    bool runInShell,
  });
}

class MockGgDoCommit extends Mock implements gg.DoCommit {}

class MockSortedProcessingList extends Mock implements SortedProcessingList {}

class MockUnlocalizeRefs extends Mock implements ChangeRefsToPubDev {}

class MockGraph extends Mock implements Graph {}

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
      SortedProcessingList? sortedProcessingList,
      ChangeRefsToPubDev? unlocalizeRefs,
      ChangeRefsToLocal? localizeRefs,
      Graph? graph,
    }) {
      final execPath = Directory.systemTemp.createTempSync('exec_path_').path;
      runner = CommandRunner<void>('test', 'Test for AddCommand');
      runner.addCommand(
        AddCommand(
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          processRunner: processRunner,
          masterWorkspacePath: masterWorkspacePath,
          executionPath: executionPath ?? execPath,
          ggDoCommit: ggDoCommit,
          sortedProcessingList: sortedProcessingList,
          unlocalizeRefs: unlocalizeRefs,
          localizeRefs: localizeRefs,
          graph: graph,
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
      final mockDoCommit = MockGgDoCommit();
      when(
        () => mockDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          logType: any(named: 'logType'),
          updateChangeLog: any(named: 'updateChangeLog'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async {});
      createRunner(ggDoCommit: mockDoCommit);
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
          'Added repository myrepo from '
              'https://github.com/myrepo/myrepo.git',
        ]),
      );

      final orgFile = File(path.join(masterWorkspacePath, '.organizations'));
      expect(orgFile.existsSync(), isTrue);
      final orgMap = (jsonDecode(orgFile.readAsStringSync()) as List<dynamic>)
          .map((e) => Organization.fromMap(e as Map<String, dynamic>))
          .toList();
      expect(orgMap.first.url, 'https://github.com/myrepo/');
    });

    test(
      'should clone single repository when target is in username/repo '
      'format',
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
      'should clone single repository when '
      'target is a full repository URL with .git',
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
      'should clone repositories when '
      'target is an organization URL',
      () async {
        final repoList = [
          const Repository(
            name: 'repo1',
            httpsUrl: 'https://github.com/myorganization/repo1.git',
          ),
          const Repository(
            name: 'repo2',
            httpsUrl: 'https://github.com/myorganization/repo2.git',
          ),
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
        final mockDoCommit = MockGgDoCommit();
        when(
          () => mockDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            logType: any(named: 'logType'),
            updateChangeLog: any(named: 'updateChangeLog'),
            force: any(named: 'force'),
          ),
        ).thenAnswer((_) async {});
        orgRunner.addCommand(
          AddCommand(
            ggLog: ggLog,
            gitCloner: mockGitCloner,
            gitHubPlatform: mockGitHubPlatform,
            masterWorkspacePath: masterWorkspacePath,
            ggDoCommit: mockDoCommit,
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
      final mockDoCommit = MockGgDoCommit();
      when(
        () => mockDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          logType: any(named: 'logType'),
          updateChangeLog: any(named: 'updateChangeLog'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async {});
      invalidRunner.addCommand(
        AddCommand(
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          masterWorkspacePath: masterWorkspacePath,
          ggDoCommit: mockDoCommit,
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

        await runner.run([
          'add',
          'git@github.com:ggsuite/kidney_core.git',
        ]);

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

        await runner.run([
          'add',
          'git@github.com:ggsuite/kidney_core.git',
          '--force',
        ]);

        verify(() => mockGitCloner.cloneRepo(any(), any())).called(1);
      },
    );

    test(
      'copies repo into ticket workspace and relocalizes ticket '
      '(two passes)',
      () async {
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
            force: any(named: 'force'),
          ),
        ).thenAnswer((_) async {});

        final mockProc = MockProcessRunner();
        when(
          () => mockProc(
            'git',
            ['fetch'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'git',
            ['reset', '--hard', 'origin/main'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'git',
            ['tag', '-l', '|', 'xargs', 'git', 'tag', '-d'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'git',
            ['fetch', '--tags'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'git',
            ['fetch', '--prune', '--tags'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'dart',
            ['pub', 'get'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockProc(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

        createRunner(
          executionPath: ticketDir.path,
          ggDoCommit: mockDoCommit,
          processRunner: mockProc.call,
        );

        await runner.run(['add', '--verbose', repoName]);

        final copiedFileInTicket = File(
          path.join(ticketDir.path, repoName, 'target.txt'),
        );
        expect(copiedFileInTicket.existsSync(), isTrue);

        verify(
          () => mockDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: 'kidney: changed references to path',
            logType: any(named: 'logType'),
            updateChangeLog: any(named: 'updateChangeLog'),
            force: true,
          ),
        ).called(greaterThanOrEqualTo(1));

        final statusFile = File(
          path.join(ticketDir.path, repoName, '.kidney_status'),
        );
        expect(statusFile.existsSync(), isTrue);
        final content =
            jsonDecode(statusFile.readAsStringSync()) as Map<String, dynamic>;
        expect(content['status'], StatusUtils.statusLocalized);

        expect(
          logMessages.any(
            (m) => m.contains('Re-localized all repositories in ticket'),
          ),
          isTrue,
        );
      },
    );

    test('creates .code-workspace for ticket with one repo', () async {
      const repoName = 'workspaceRepo';
      final repoDir = Directory(path.join(masterWorkspacePath, repoName))
        ..createSync(recursive: true);
      File(path.join(repoDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: $repoName
version: 1.0.0
''');

      final ticketDir = Directory(
        path.join(tempDir.path, kidneyTicketFolder, 'TICKET_WS'),
      )..createSync(recursive: true);

      final mockProc = MockProcessRunner();
      when(
        () => mockProc(
          'git',
          ['fetch'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['reset', '--hard', 'origin/main'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['tag', '-l', '|', 'xargs', 'git', 'tag', '-d'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['fetch', '--tags'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['fetch', '--prune', '--tags'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'dart',
          ['pub', 'get'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer(
        (_) async => ProcessResult(1, 0, 'ok', ''),
      );
      when(
        () => mockProc(
          'dart',
          ['pub', 'upgrade'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer(
        (_) async => ProcessResult(1, 0, 'ok', ''),
      );

      final mockDoCommit = MockGgDoCommit();
      when(
        () => mockDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          logType: any(named: 'logType'),
          updateChangeLog: any(named: 'updateChangeLog'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async {});

      createRunner(
        executionPath: ticketDir.path,
        processRunner: mockProc.call,
        ggDoCommit: mockDoCommit,
      );

      await runner.run(['add', repoName]);

      final wsFile =
          File(path.join(ticketDir.path, 'TICKET_WS.code-workspace'));
      expect(wsFile.existsSync(), isTrue);
      final json =
          jsonDecode(wsFile.readAsStringSync()) as Map<String, dynamic>;
      final folders =
          (json['folders'] as List<dynamic>).cast<Map<String, dynamic>>();
      final paths = folders.map((f) => f['path'] as String).toSet();
      expect(paths, equals(<String>{repoName}));
    });

    test('logs error when git reset fails but still copies repo', () async {
      const repoName = 'pullFailRepo';
      final masterRepoDir = Directory(
        path.join(masterWorkspacePath, repoName),
      )..createSync(recursive: true);
      File(path.join(masterRepoDir.path, 'file.txt')).writeAsStringSync('x');

      final ticketDir = Directory(
        path.join(tempDir.path, kidneyTicketFolder, 'TICKET_PULL_FAIL'),
      )..createSync(recursive: true);

      final mockProc = MockProcessRunner();
      final mockSorted = MockSortedProcessingList();
      final mockDoCommit = MockGgDoCommit();
      final mockGraph = MockGraph();

      when(
        () => mockDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          logType: any(named: 'logType'),
          updateChangeLog: any(named: 'updateChangeLog'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => mockGraph.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => <String, Node>{});

      when(
        () => mockSorted.get(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
        ),
      ).thenAnswer((_) async => <Node>[]);

      when(
        () => mockProc(
          'git',
          ['fetch'],
          workingDirectory: masterRepoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['reset', '--hard', 'origin/main'],
          workingDirectory: masterRepoDir.path,
          runInShell: true,
        ),
      ).thenAnswer(
        (_) async => ProcessResult(1, 1, '', 'reset error'),
      );
      when(
        () => mockProc(
          'git',
          ['tag', '-l', '|', 'xargs', 'git', 'tag', '-d'],
          workingDirectory: masterRepoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['fetch', '--tags'],
          workingDirectory: masterRepoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['fetch', '--prune', '--tags'],
          workingDirectory: masterRepoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'dart',
          ['pub', 'get'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
      when(
        () => mockProc(
          'dart',
          ['pub', 'upgrade'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

      final localRunner = CommandRunner<void>('test', 'Add pull fail')
        ..addCommand(
          AddCommand(
            ggLog: ggLog,
            gitCloner: mockGitCloner,
            processRunner: mockProc.call,
            masterWorkspacePath: masterWorkspacePath,
            executionPath: ticketDir.path,
            ggDoCommit: mockDoCommit,
            sortedProcessingList: mockSorted,
            graph: mockGraph,
          ),
        );

      await localRunner.run(['add', '--verbose', repoName]);

      final copied = Directory(path.join(ticketDir.path, repoName));
      expect(copied.existsSync(), isTrue);
      expect(
        logMessages.any(
          (m) => m.contains(
            'Failed to execute git reset --hard origin/main in '
            'pullFailRepo in master workspace: reset error',
          ),
        ),
        isTrue,
      );
      verify(
        () => mockProc(
          'git',
          ['fetch'],
          workingDirectory: masterRepoDir.path,
          runInShell: true,
        ),
      ).called(1);
      verify(
        () => mockProc(
          'git',
          ['reset', '--hard', 'origin/main'],
          workingDirectory: masterRepoDir.path,
          runInShell: true,
        ),
      ).called(1);
      verify(
        () => mockProc(
          'git',
          ['tag', '-l', '|', 'xargs', 'git', 'tag', '-d'],
          workingDirectory: masterRepoDir.path,
          runInShell: true,
        ),
      ).called(1);
      verify(
        () => mockProc(
          'git',
          ['fetch', '--tags'],
          workingDirectory: masterRepoDir.path,
          runInShell: true,
        ),
      ).called(1);
      verify(
        () => mockProc(
          'git',
          ['fetch', '--prune', '--tags'],
          workingDirectory: masterRepoDir.path,
          runInShell: true,
        ),
      ).called(1);
    });

    test('logs error when repo not found in master workspace', () async {
      final ticketDir = Directory(
        path.join(tempDir.path, kidneyTicketFolder, 'TICKET-MISSING'),
      )..createSync(recursive: true);
      createRunner(executionPath: ticketDir.path);
      await runner.run(['add', '--verbose', 'nonexistent']);
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

        await runner.run(['add', '--verbose', repoName]);

        expect(
          logMessages,
          contains('$repoName already exists in ticket workspace.'),
        );
      },
    );

    test(
        'does not set status if localization fails in ticket '
        'relocalization', () async {
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
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async {});

      createRunner(executionPath: ticketDir.path, ggDoCommit: mockDoCommit);

      await runner.run(['add', repoName]);

      final statusFile = File(
        path.join(ticketDir.path, repoName, '.kidney_status'),
      );
      expect(statusFile.existsSync(), isFalse);
      verifyNever(
        () => mockDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          logType: any(named: 'logType'),
          updateChangeLog: any(named: 'updateChangeLog'),
          force: any(named: 'force'),
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
        final mockDoCommit = MockGgDoCommit();
        when(
          () => mockDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            logType: any(named: 'logType'),
            updateChangeLog: any(named: 'updateChangeLog'),
            force: any(named: 'force'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => mockProcessRunner(
            'git',
            ['fetch'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProcessRunner(
            'git',
            ['reset', '--hard', 'origin/main'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProcessRunner(
            'git',
            ['tag', '-l', '|', 'xargs', 'git', 'tag', '-d'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProcessRunner(
            'git',
            ['fetch', '--tags'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProcessRunner(
            'git',
            ['fetch', '--prune', '--tags'],
            workingDirectory: repoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockProcessRunner.call,
          ggDoCommit: mockDoCommit,
        );
      });

      tearDown(() async {
        if (ticketDir.existsSync()) {
          ticketDir.deleteSync(recursive: true);
        }
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
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'Pub get success', ''));
        when(
          () => mockProcessRunner(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

        await runner.run(['add', '--verbose', repoName]);

        verify(
          () => mockProcessRunner(
            'dart',
            ['pub', 'get'],
            workingDirectory: path.join(ticketDir.path, repoName),
            runInShell: true,
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
            runInShell: true,
          ),
        ).thenAnswer(
          (_) async => ProcessResult(2, 1, '', 'Pub get error'),
        );
        when(
          () => mockProcessRunner(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

        await runner.run(['add', '--verbose', repoName]);

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
          force: any(named: 'force'),
        ),
      ).thenThrow(Exception('commit error'));

      final mockProc = MockProcessRunner();
      when(
        () => mockProc(
          'git',
          ['fetch'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['reset', '--hard', 'origin/main'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['tag', '-l', '|', 'xargs', 'git', 'tag', '-d'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['fetch', '--tags'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'git',
          ['fetch', '--prune', '--tags'],
          workingDirectory: repoDir.path,
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
      when(
        () => mockProc(
          'dart',
          ['pub', 'get'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
      when(
        () => mockProc(
          'dart',
          ['pub', 'upgrade'],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: true,
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

      createRunner(
        executionPath: ticketDir.path,
        ggDoCommit: mockDoCommit,
        processRunner: mockProc.call,
      );

      await runner.run(['add', '--verbose', repoName]);

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

      final mockDoCommit = MockGgDoCommit();
      when(
        () => mockDoCommit.exec(
          directory: any(named: 'directory'),
          ggLog: any(named: 'ggLog'),
          message: any(named: 'message'),
          logType: any(named: 'logType'),
          updateChangeLog: any(named: 'updateChangeLog'),
          force: any(named: 'force'),
        ),
      ).thenAnswer((_) async {});

      createRunner(ggDoCommit: mockDoCommit);

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

    test(
      'relocalization aborts and logs when localize fails',
      () async {
        const repoName = 'localizeFailRepo';
        final repoDir = Directory(path.join(masterWorkspacePath, repoName))
          ..createSync(recursive: true);
        File(path.join(repoDir.path, 'pubspec.yaml'))
            .writeAsStringSync('name: $repoName');

        final ticketDir = Directory(
          path.join(tempDir.path, kidneyTicketFolder, 'TICKET-LOCFAIL'),
        )..createSync(recursive: true);

        final mockSorted = MockSortedProcessingList();
        final mockUnloc = MockUnlocalizeRefs();
        final mockLoc = MockLocalizeRefs();
        final mockDoCommit = MockGgDoCommit();

        when(
          () => mockDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            logType: any(named: 'logType'),
            updateChangeLog: any(named: 'updateChangeLog'),
            force: any(named: 'force'),
          ),
        ).thenAnswer((_) async {});

        Future<List<Node>> futureNode() async => [
              Node(
                name: repoName,
                directory: Directory(
                  path.join(ticketDir.path, repoName),
                ),
                manifest: DartPackageManifest(pubspec: Pubspec(repoName)),
              ),
            ];

        when(
          () => mockSorted.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async => await futureNode());

        when(
          () => mockUnloc.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => mockLoc.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenThrow(Exception('localize failed'));

        final mockRunner = MockProcessRunner();
        when(
          () => mockRunner(
            'git',
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockRunner(
            'dart',
            ['pub', 'get'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockRunner(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockRunner.call,
          ggDoCommit: mockDoCommit,
          sortedProcessingList: mockSorted,
          unlocalizeRefs: mockUnloc,
          localizeRefs: mockLoc,
        );

        await expectLater(
          () async => await runner.run(['add', '--verbose', repoName]),
          throwsA(isA<Exception>()),
        );

        expect(
          logMessages.any(
            (m) => m.contains(
              'Failed to localize refs for $repoName: '
              'Exception: localize failed',
            ),
          ),
          isTrue,
        );
      },
    );

    test(
      'adds between nodes into ticket when executed inside a ticket',
      () async {
        final aDir = Directory(path.join(masterWorkspacePath, 'a'))
          ..createSync(recursive: true);
        final bDir = Directory(path.join(masterWorkspacePath, 'b'))
          ..createSync(recursive: true);
        final cDir = Directory(path.join(masterWorkspacePath, 'c'))
          ..createSync(recursive: true);

        File(path.join(aDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: a
version: 1.0.0
dependencies:
  b: ^1.0.0
''');
        File(path.join(bDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: b
version: 1.0.0
dependencies:
  c: ^1.0.0
''');
        File(path.join(cDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: c
version: 1.0.0
''');

        final ticketDir = Directory(
          path.join(tempDir.path, kidneyTicketFolder, 'TXYZ'),
        )..createSync(recursive: true);

        final mockRunner = MockProcessRunner();
        when(
          () => mockRunner(
            'git',
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockRunner(
            'dart',
            ['pub', 'get'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockRunner(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

        final mockDoCommit = MockGgDoCommit();
        when(
          () => mockDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            logType: any(named: 'logType'),
            updateChangeLog: any(named: 'updateChangeLog'),
            force: any(named: 'force'),
          ),
        ).thenAnswer((_) async {});

        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockRunner.call,
          ggDoCommit: mockDoCommit,
        );

        await runner.run(['add', '--verbose', 'a', 'c']);

        expect(Directory(path.join(ticketDir.path, 'a')).existsSync(), isTrue);
        expect(Directory(path.join(ticketDir.path, 'b')).existsSync(), isTrue);
        expect(Directory(path.join(ticketDir.path, 'c')).existsSync(), isTrue);

        expect(
          logMessages.any(
            (m) => m == 'Added repository b to ticket workspace.',
          ),
          isTrue,
        );

        expect(
          logMessages.any(
            (m) => m.contains('Re-localized all repositories in ticket TXYZ'),
          ),
          isTrue,
        );

        final workspaceFile = File(
          path.join(ticketDir.path, 'TXYZ.code-workspace'),
        );
        expect(workspaceFile.existsSync(), isTrue);
        final workspaceJson = jsonDecode(
          workspaceFile.readAsStringSync(),
        ) as Map<String, dynamic>;
        final folders = (workspaceJson['folders'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        final folderPaths = folders.map((f) => f['path'] as String).toSet();
        expect(
          folderPaths,
          equals(<String>{'a', 'b', 'c'}),
        );
      },
    );

    test(
      'adds between nodes using existing ticket repos as endpoints',
      () async {
        final aDir = Directory(path.join(masterWorkspacePath, 'a'))
          ..createSync(recursive: true);
        final bDir = Directory(path.join(masterWorkspacePath, 'b'))
          ..createSync(recursive: true);
        final cDir = Directory(path.join(masterWorkspacePath, 'c'))
          ..createSync(recursive: true);

        File(path.join(aDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: a
version: 1.0.0
dependencies:
  b: ^1.0.0
''');
        File(path.join(bDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: b
version: 1.0.0
dependencies:
  c: ^1.0.0
''');
        File(path.join(cDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: c
version: 1.0.0
''');

        final ticketDir = Directory(
          path.join(tempDir.path, kidneyTicketFolder, 'TXYZ_EXISTING'),
        )..createSync(recursive: true);

        final existingC = Directory(path.join(ticketDir.path, 'c'))
          ..createSync(recursive: true);
        File(path.join(existingC.path, 'dummy.txt')).writeAsStringSync('x');

        final mockRunner = MockProcessRunner();
        when(
          () => mockRunner(
            'git',
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockRunner(
            'dart',
            ['pub', 'get'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockRunner(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

        final mockDoCommit = MockGgDoCommit();
        when(
          () => mockDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            logType: any(named: 'logType'),
            updateChangeLog: any(named: 'updateChangeLog'),
            force: any(named: 'force'),
          ),
        ).thenAnswer((_) async {});

        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockRunner.call,
          ggDoCommit: mockDoCommit,
        );

        await runner.run(['add', '--verbose', 'a']);

        expect(Directory(path.join(ticketDir.path, 'a')).existsSync(), isTrue);
        expect(Directory(path.join(ticketDir.path, 'b')).existsSync(), isTrue);
        expect(Directory(path.join(ticketDir.path, 'c')).existsSync(), isTrue);

        expect(
          logMessages.any(
            (m) => m == 'Added repository b to ticket workspace.',
          ),
          isTrue,
        );
        expect(
          logMessages.any(
            (m) => m == 'c already exists in ticket workspace.',
          ),
          isFalse,
        );
        expect(
          logMessages.any(
            (m) => m.contains(
              'Re-localized all repositories in ticket TXYZ_EXISTING',
            ),
          ),
          isTrue,
        );
      },
    );

    test(
      'logs when dependency graph building fails and continues',
      () async {
        const repoName = 'graphFailRepo';
        final repoDir = Directory(path.join(masterWorkspacePath, repoName))
          ..createSync(recursive: true);
        File(path.join(repoDir.path, 'file.txt')).writeAsStringSync('x');

        final ticketDir = Directory(
          path.join(tempDir.path, kidneyTicketFolder, 'T-DFG'),
        )..createSync(recursive: true);

        final mockGraph = MockGraph();
        when(
          () => mockGraph.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenThrow(Exception('graph error'));

        final mockProc = MockProcessRunner();
        when(
          () => mockProc(
            any(),
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

        final cmdRunner = CommandRunner<void>('test', 'Add with graph mock')
          ..addCommand(
            AddCommand(
              ggLog: ggLog,
              gitCloner: mockGitCloner,
              masterWorkspacePath: masterWorkspacePath,
              executionPath: ticketDir.path,
              processRunner: mockProc.call,
              graph: mockGraph,
            ),
          );

        await cmdRunner.run(['add', repoName]);

        expect(
          logMessages.any(
            (m) => m.contains(
              'Failed to build dependency graph: Exception: graph error',
            ),
          ),
          isTrue,
        );
      },
    );

    group('dart pub upgrade in relocalization', () {
      test('executes dart pub upgrade after localize and logs success',
          () async {
        const repoName = 'upgradeRepo';
        final repoDir = Directory(path.join(masterWorkspacePath, repoName))
          ..createSync(recursive: true);
        File(path.join(repoDir.path, 'pubspec.yaml')).writeAsStringSync(
          'name: $repoName',
        );

        final ticketDir = Directory(
          path.join(tempDir.path, kidneyTicketFolder, 'T-UPG'),
        )..createSync(recursive: true);

        final mockSorted = MockSortedProcessingList();
        when(
          () => mockSorted.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(
              name: repoName,
              directory: Directory(path.join(ticketDir.path, repoName)),
              manifest: DartPackageManifest(pubspec: Pubspec(repoName)),
            ),
          ],
        );

        final mockUnloc = MockUnlocalizeRefs();
        final mockLoc = MockLocalizeRefs();
        when(
          () => mockUnloc.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => mockLoc.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        final mockProc = MockProcessRunner();
        when(
          () => mockProc(
            'git',
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockProc(
            'dart',
            ['pub', 'get'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockProc(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

        final mockDoCommit = MockGgDoCommit();
        when(
          () => mockDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            logType: any(named: 'logType'),
            updateChangeLog: any(named: 'updateChangeLog'),
            force: any(named: 'force'),
          ),
        ).thenAnswer((_) async {});

        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockProc.call,
          ggDoCommit: mockDoCommit,
          sortedProcessingList: mockSorted,
          unlocalizeRefs: mockUnloc,
          localizeRefs: mockLoc,
        );

        await runner.run(['add', '--verbose', repoName]);

        expect(
          logMessages.any(
            (m) => m.contains('Executed dart pub upgrade in $repoName.'),
          ),
          isTrue,
        );
      });

      test(
          'logs error and aborts when dart pub upgrade '
          'fails in relocalization', () async {
        const repoName = 'upgradeFailRepo';
        final repoDir = Directory(path.join(masterWorkspacePath, repoName))
          ..createSync(recursive: true);
        File(path.join(repoDir.path, 'pubspec.yaml')).writeAsStringSync(
          'name: $repoName',
        );

        final ticketDir = Directory(
          path.join(tempDir.path, kidneyTicketFolder, 'T-UPG-FAIL'),
        )..createSync(recursive: true);

        final mockSorted = MockSortedProcessingList();
        when(
          () => mockSorted.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer(
          (_) async => [
            Node(
              name: repoName,
              directory: Directory(path.join(ticketDir.path, repoName)),
              manifest: DartPackageManifest(pubspec: Pubspec(repoName)),
            ),
          ],
        );

        final mockUnloc = MockUnlocalizeRefs();
        final mockLoc = MockLocalizeRefs();
        when(
          () => mockUnloc.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});
        when(
          () => mockLoc.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        final mockProc = MockProcessRunner();
        when(
          () => mockProc(
            'git',
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockProc(
            'dart',
            ['pub', 'get'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockProc(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer(
          (_) async => ProcessResult(1, 1, '', 'Upgrade error'),
        );

        final mockDoCommit = MockGgDoCommit();
        when(
          () => mockDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            logType: any(named: 'logType'),
            updateChangeLog: any(named: 'updateChangeLog'),
            force: any(named: 'force'),
          ),
        ).thenAnswer((_) async {});

        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockProc.call,
          ggDoCommit: mockDoCommit,
          sortedProcessingList: mockSorted,
          unlocalizeRefs: mockUnloc,
          localizeRefs: mockLoc,
        );

        await runner.run(['add', '--verbose', repoName]);

        expect(
          logMessages.any(
            (m) => m.contains(
              'Failed to execute dart pub upgrade '
              'in $repoName: Upgrade error',
            ),
          ),
          isTrue,
        );
      });
    });

    test(
      'unlocalizes when backup file exists in ticket repository',
      () async {
        const repoName = 'backupRepo';
        final masterRepoDir = Directory(
          path.join(masterWorkspacePath, repoName),
        )..createSync(recursive: true);

        File(path.join(masterRepoDir.path, 'pubspec.yaml'))
            .writeAsStringSync('name: $repoName');

        File(
          path.join(
            masterRepoDir.path,
            '.gg_localize_refs_backup.json',
          ),
        ).writeAsStringSync('{}');

        final ticketDir = Directory(
          path.join(tempDir.path, kidneyTicketFolder, 'TICKET-BACKUP'),
        )..createSync(recursive: true);

        final mockSorted = MockSortedProcessingList();
        final mockUnloc = MockUnlocalizeRefs();
        final mockLoc = MockLocalizeRefs();
        final mockDoCommit = MockGgDoCommit();
        final mockProc = MockProcessRunner();

        when(
          () => mockDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            logType: any(named: 'logType'),
            updateChangeLog: any(named: 'updateChangeLog'),
            force: any(named: 'force'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockProc(
            'git',
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockProc(
            'dart',
            ['pub', 'get'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockProc(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

        when(
          () => mockSorted.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((invocation) async {
          final dir = invocation.namedArguments[#directory] as Directory;
          final ticketRepoDir = Directory(path.join(dir.path, repoName));
          return [
            Node(
              name: repoName,
              directory: ticketRepoDir,
              manifest: DartPackageManifest(pubspec: Pubspec(repoName)),
            ),
          ];
        });

        when(
          () => mockUnloc.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockLoc.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockProc.call,
          ggDoCommit: mockDoCommit,
          sortedProcessingList: mockSorted,
          unlocalizeRefs: mockUnloc,
          localizeRefs: mockLoc,
        );

        await runner.run(['add', repoName]);

        final ticketRepoBackup = File(
          path.join(
            ticketDir.path,
            repoName,
            '.gg_localize_refs_backup.json',
          ),
        );
        expect(ticketRepoBackup.existsSync(), isTrue);

        verify(
          () => mockUnloc.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).called(1);
      },
    );

    test(
      'logs error and aborts when unlocalize fails '
      'in relocalization pass',
      () async {
        const repoName = 'unlocFailRepo';
        final masterRepoDir = Directory(
          path.join(masterWorkspacePath, repoName),
        )..createSync(recursive: true);

        File(path.join(masterRepoDir.path, 'pubspec.yaml'))
            .writeAsStringSync('name: $repoName');

        File(
          path.join(
            masterRepoDir.path,
            '.gg_localize_refs_backup.json',
          ),
        ).writeAsStringSync('{}');

        final ticketDir = Directory(
          path.join(
            tempDir.path,
            kidneyTicketFolder,
            'TICKET-UNLOC-FAIL',
          ),
        )..createSync(recursive: true);

        final mockSorted = MockSortedProcessingList();
        final mockUnloc = MockUnlocalizeRefs();
        final mockLoc = MockLocalizeRefs();
        final mockDoCommit = MockGgDoCommit();
        final mockProc = MockProcessRunner();

        when(
          () => mockDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            logType: any(named: 'logType'),
            updateChangeLog: any(named: 'updateChangeLog'),
            force: any(named: 'force'),
          ),
        ).thenAnswer((_) async {});

        when(
          () => mockProc(
            'git',
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockProc(
            'dart',
            ['pub', 'get'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));
        when(
          () => mockProc(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(1, 0, 'ok', ''));

        when(
          () => mockSorted.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((invocation) async {
          final dir = invocation.namedArguments[#directory] as Directory;
          final ticketRepoDir = Directory(path.join(dir.path, repoName));
          return [
            Node(
              name: repoName,
              directory: ticketRepoDir,
              manifest: DartPackageManifest(pubspec: Pubspec(repoName)),
            ),
          ];
        });

        when(
          () => mockUnloc.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenThrow(Exception('unloc failed'));

        when(
          () => mockLoc.get(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
          ),
        ).thenAnswer((_) async {});

        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockProc.call,
          ggDoCommit: mockDoCommit,
          sortedProcessingList: mockSorted,
          unlocalizeRefs: mockUnloc,
          localizeRefs: mockLoc,
        );

        await expectLater(
          () async => await runner.run(['add', '--verbose', repoName]),
          throwsA(isA<Exception>()),
        );

        expect(
          logMessages.any(
            (m) => m.contains(
              'Failed to unlocalize refs for $repoName: '
              'Exception: unloc failed',
            ),
          ),
          isTrue,
        );
      },
    );

    test(
      'installs git hooks for repositories in ticket workspace after add',
      () async {
        const repoName = 'hooksRepo';

        final masterRepoDir = Directory(
          path.join(masterWorkspacePath, repoName),
        )..createSync(recursive: true);
        File(path.join(masterRepoDir.path, 'pubspec.yaml'))
            .writeAsStringSync('name: $repoName');
        Directory(path.join(masterRepoDir.path, '.git')).createSync();

        final ticketDir = Directory(
          path.join(tempDir.path, kidneyTicketFolder, 'TICKET-HOOKS'),
        )..createSync(recursive: true);

        final mockProc = MockProcessRunner();
        when(
          () => mockProc(
            'git',
            ['fetch'],
            workingDirectory: masterRepoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'git',
            ['reset', '--hard', 'origin/main'],
            workingDirectory: masterRepoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'git',
            ['tag', '-l', '|', 'xargs', 'git', 'tag', '-d'],
            workingDirectory: masterRepoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'git',
            ['fetch', '--tags'],
            workingDirectory: masterRepoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'git',
            ['fetch', '--prune', '--tags'],
            workingDirectory: masterRepoDir.path,
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'dart',
            ['pub', 'get'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));
        when(
          () => mockProc(
            'dart',
            ['pub', 'upgrade'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: true,
          ),
        ).thenAnswer((_) async => ProcessResult(0, 0, 'ok', ''));

        final mockDoCommit = MockGgDoCommit();
        when(
          () => mockDoCommit.exec(
            directory: any(named: 'directory'),
            ggLog: any(named: 'ggLog'),
            message: any(named: 'message'),
            logType: any(named: 'logType'),
            updateChangeLog: any(named: 'updateChangeLog'),
            force: any(named: 'force'),
          ),
        ).thenAnswer((_) async {});

        createRunner(
          executionPath: ticketDir.path,
          processRunner: mockProc.call,
          ggDoCommit: mockDoCommit,
        );

        await runner.run(['add', repoName]);

        final ticketRepoDir = Directory(path.join(ticketDir.path, repoName));
        final prePushHook = File(
          path.join(ticketRepoDir.path, '.git', 'hooks', 'pre-push'),
        );
        final verifyPushScript = File(
          path.join(ticketRepoDir.path, '.gg', 'verify_push.dart'),
        );

        expect(prePushHook.existsSync(), isTrue);
        expect(verifyPushScript.existsSync(), isTrue);
      },
    );
  });
}
