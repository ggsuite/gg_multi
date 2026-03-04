// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

// ignore_for_file: avoid_print

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg/gg.dart' as gg;
import 'package:gg_publish/gg_publish.dart';
import 'package:kidney_core/src/backend/constants.dart';
import 'package:kidney_core/src/backend/filesystem_utils.dart';
import 'package:kidney_core/src/commands/can/commit.dart';
import 'package:kidney_core/src/commands/can/review.dart';
import 'package:kidney_core/src/commands/create/ticket.dart';
import 'package:kidney_core/src/commands/do/commit.dart';
import 'package:kidney_core/src/commands/do/publish.dart';
import 'package:kidney_core/src/commands/do/push.dart';
import 'package:kidney_core/src/commands/do/review.dart';
import 'package:kidney_core/src/commands/kidney_add.dart';
import 'package:kidney_core/src/commands/kidney_init.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:test/test.dart';

import '../rm_console_colors_helper.dart';

/// Integration test that executes the full "add" → "do review" flow
/// for two local Dart packages `a` and `b`.
///
/// The test assumes that `git` and `dart` are available on the PATH.
void main() {
  void mockVersionSelector(gg.VersionSelector versionSelector) => when(
        () => versionSelector.selectIncrement(
          currentVersion: any(named: 'currentVersion'),
        ),
      ).thenAnswer((_) async {
        return VersionIncrement.patch;
      });

  group('kidney_core review integration', () {
    test(
      'adds a & b and reviews them end-to-end',
      () async {
        final logs = <String>[];

        void ggLog(String message) {
          logs.add(rmConsoleColors(message));
          print(message);
        }

        // Ensure git and dart binaries are available --------------------------
        await _ensureBinaryAvailable('git');
        await _ensureBinaryAvailable('dart');

        // Locate the sample projects a and b under test/sample_folder ---------
        final projectRoot = Directory.current.path;
        final sampleRoot = path.join(projectRoot, 'test', 'sample_folder');
        final sampleDir = Directory(sampleRoot);
        expect(
          sampleDir.existsSync(),
          isTrue,
          reason: 'Sample folder not found at $sampleRoot',
        );

        // Create an isolated workspace root for this integration test ---------
        final tempRoot =
            Directory.systemTemp.createTempSync('kidney_review_integration_');

        try {
          // -------------------------------------------------------------------
          // 1) Initialize master workspace via InitCommand (kidney_core init)

          print('------- Running kidney_core init -------');

          final initRunner = CommandRunner<void>(
            'kidney_core',
            'kidney_core integration init',
          )..addCommand(
              InitCommand(
                ggLog: ggLog,
                rootPath: tempRoot.path,
              ),
            );

          await initRunner.run(<String>['init']);

          final masterDir = Directory(
            path.join(tempRoot.path, kidneyMasterFolder),
          );
          expect(masterDir.existsSync(), isTrue);

          // -------------------------------------------------------------------
          // 2) Copy sample projects a and b into master and set up git remotes
          final remotesRoot = Directory(path.join(tempRoot.path, 'remotes'))
            ..createSync(recursive: true);

          for (final projectName in <String>['a', 'b']) {
            final sourceDir = Directory(path.join(sampleRoot, projectName));
            expect(
              sourceDir.existsSync(),
              isTrue,
              reason: 'Missing sample project $projectName under $sampleRoot',
            );

            final masterRepoDir = Directory(
              path.join(masterDir.path, projectName),
            );
            await copyDirectory(sourceDir, masterRepoDir);

            await _initializeGitRepoWithRemote(
              projectName: projectName,
              repoDir: masterRepoDir,
              remotesRoot: remotesRoot,
            );
          }

          // 2.1 ) Expect both projects in .master Workspace
          for (final projectName in <String>['a', 'b']) {
            final pubspecFile = File(
              path.join(masterDir.path, projectName, 'pubspec.yaml'),
            );
            expect(
              pubspecFile.existsSync(),
              isTrue,
              reason: 'pubspec.yaml of package $projectName in '
                  'master workspace does not exist',
            );
          }

          // -------------------------------------------------------------------
          // 3) Create ticket workspace KIDNEY_TEST (kidney_core create ticket)

          const ticketName = 'KIDNEY_TEST';

          print(
            '------- Running kidney_core create ticket $ticketName -------',
          );

          final ticketRunner = CommandRunner<void>(
            'kidney_core',
            'kidney_core integration create ticket',
          )..addCommand(
              TicketCommand(
                ggLog: ggLog,
                rootPath: tempRoot.path,
                directoryFactory: Directory.new,
              ),
            );

          await ticketRunner.run(<String>[
            'ticket',
            '--input',
            tempRoot.path,
            ticketName,
          ]);

          final ticketDir = Directory(
            path.join(tempRoot.path, kidneyTicketFolder, ticketName),
          );
          expect(ticketDir.existsSync(), isTrue);

          // -------------------------------------------------------------------
          // 4) Add a and b into ticket workspace (kidney_core add a b) --------

          print(
            '------- Running kidney_core add a b -------',
          );

          final addRunner = CommandRunner<void>(
            'kidney_core',
            'kidney_core integration add',
          )..addCommand(
              AddCommand(
                ggLog: ggLog,
                masterWorkspacePath: masterDir.path,
                executionPath: ticketDir.path,
              ),
            );

          await addRunner.run(<String>['add', 'b', 'a', '--verbose']);

          // -------------------------------------------------------------------
          // 4.1) Add a file change --------------------------------------------

          final aLibFile = File(
            path.join(ticketDir.path, 'a', 'lib', 'src', 'a.dart'),
          );
          expect(
            aLibFile.existsSync(),
            isTrue,
            reason: 'Expected file a/lib/src/a.dart does not exist in ticket',
          );

          aLibFile.writeAsStringSync(
            '${aLibFile.readAsStringSync()}\n'
            '// This is a file change added by the integration test.\n',
          );

          // -------------------------------------------------------------------
          // 5) Run kidney_core do commit for the ticket -----------------------

          print(
            '------- Running kidney_core do commit -------',
          );

          final doCommitRunner = CommandRunner<void>(
            'kidney_core',
            'kidney_core integration do commit',
          )..addCommand(
              DoCommitCommand(
                ggLog: ggLog,
              ),
            );

          await doCommitRunner.run(<String>[
            'commit',
            '--input',
            ticketDir.path,
            '--message',
            'test-kidney-integration: initial commit after '
                'adding to ticket and before review',
          ]);

          // -------------------------------------------------------------------
          // 6) Run kidney_core do push for the ticket -------------------------

          print(
            '------- Running kidney_core do push -------',
          );

          final doPushRunner = CommandRunner<void>(
            'kidney_core',
            'kidney_core integration do push',
          )..addCommand(
              DoPushCommand(
                ggLog: ggLog,
              ),
            );

          await doPushRunner.run(<String>[
            'push',
            '--input',
            ticketDir.path,
            '--verbose',
          ]);

          // -------------------------------------------------------------------
          // 7) Run kidney_core can review for the ticket ----------------------

          print(
            '------- Running kidney_core can review -------',
          );

          final canReviewRunner = CommandRunner<void>(
            'kidney_core',
            'kidney_core integration can review',
          )..addCommand(
              CanReviewCommand(
                ggLog: ggLog,
              ),
            );

          await canReviewRunner.run(<String>[
            'review',
            '--input',
            ticketDir.path,
          ]);

          // -------------------------------------------------------------------
          // 8) Run kidney_core do review for the ticket -----------------------

          print(
            '------- Running kidney_core do review -------',
          );

          final reviewRunner = CommandRunner<void>(
            'kidney_core',
            'kidney_core integration do review',
          )..addCommand(
              DoReviewCommand(
                ggLog: ggLog,
              ),
            );

          await reviewRunner.run(<String>[
            'review',
            '--input',
            ticketDir.path,
            '--verbose',
          ]);

          // -------------------------------------------------------------------
          // 9) Assertions -----------------------------------------------------

          // 9.1) Both projects exist in the ticket workspace ------------------
          final ticketA = Directory(path.join(ticketDir.path, 'a'));
          final ticketB = Directory(path.join(ticketDir.path, 'b'));
          expect(ticketA.existsSync(), isTrue);
          expect(ticketB.existsSync(), isTrue);

          // 9.2) a depends on b via a git dependency in pubspec.yaml ----------
          final aPubspecFile = File(path.join(ticketA.path, 'pubspec.yaml'));
          expect(
            aPubspecFile.existsSync(),
            isTrue,
            reason:
                'pubspec.yaml of package a in ticket workspace does not exist',
          );

          final aPubspecContent = aPubspecFile.readAsStringSync();
          final aPubspec = Pubspec.parse(aPubspecContent);

          final bDependency = aPubspec.dependencies['b'];
          expect(bDependency, isNotNull, reason: 'Dependency b missing in a');
          expect(
            bDependency,
            isA<GitDependency>(),
            reason: 'Dependency b is expected to be a git dependency in a.',
          );

          // The YAML should contain a git: block for b as well.
          expect(aPubspecContent, contains('git:'));

          // 9.3) Both ticket repositories are on branch KIDNEY_TEST -----------
          for (final repoName in <String>['a', 'b']) {
            final repoPath = path.join(ticketDir.path, repoName);
            final result = await _runGit(
              <String>['rev-parse', '--abbrev-ref', 'HEAD'],
              workingDirectory: repoPath,
            );
            final branchName = (result.stdout as String).trim();
            expect(
              branchName,
              ticketName,
              reason: 'Repository $repoName is not on branch $ticketName',
            );
          }

          // -------------------------------------------------------------------
          // 10) Run kidney_core do publish for the ticket ---------------------

          print(
            '------- Running kidney_core can commit -------',
          );

          final canCommitRunner = CommandRunner<void>(
            'kidney_core',
            'kidney_core integration can commit',
          )..addCommand(
              CanCommitCommand(
                ggLog: ggLog,
              ),
            );

          await canCommitRunner.run(<String>[
            'commit',
            '--input',
            ticketDir.path,
          ]);

          await doCommitRunner.run(<String>[
            'commit',
            '--input',
            ticketDir.path,
            '--message',
            'test-kidney-integration: initial commit after '
                'review and before publish',
          ]);

          print(
            '------- Running kidney_core do publish -------',
          );

          gg.VersionSelector versionSelector = gg.MockVersionSelector();

          registerFallbackValue(Version(0, 0, 0));
          mockVersionSelector(versionSelector);

          final publishRunner = CommandRunner<void>(
            'kidney_core',
            'kidney_core integration do publish',
          )..addCommand(
              DoPublishCommand(
                ggLog: ggLog,
                ggDoPublish: gg.DoPublish(
                  ggLog: ggLog,
                  versionSelector: versionSelector,
                ),
              ),
            );

          await publishRunner.run(<String>[
            'publish',
            '--input',
            ticketDir.path,
            '--force',
            '--verbose',
          ]);

          // 10.1)

          // create new ticket KIDNEY_TEST_2 and add a and b into it again

          const ticketName2 = 'KIDNEY_TEST_2';

          await ticketRunner.run(<String>[
            'ticket',
            '--input',
            tempRoot.path,
            ticketName2,
          ]);

          final ticketDir2 = Directory(
            path.join(tempRoot.path, kidneyTicketFolder, ticketName2),
          );
          expect(ticketDir2.existsSync(), isTrue);

          print(
            '------- Running kidney_core add a b -------',
          );

          final addRunner2 = CommandRunner<void>(
            'kidney_core',
            'kidney_core integration add',
          )..addCommand(
              AddCommand(
                ggLog: ggLog,
                masterWorkspacePath: masterDir.path,
                executionPath: ticketDir2.path,
              ),
            );

          await addRunner2.run(<String>['add', 'a', 'b']);

          // print changelog.md and pubspec.yaml of both repos for debugging
          for (final repoName in <String>['a', 'b']) {
            final repoPath = path.join(ticketDir2.path, repoName);
            final changelogFile = File(path.join(repoPath, 'CHANGELOG.md'));
            final pubspecFile = File(path.join(repoPath, 'pubspec.yaml'));

            print('------- $repoName CHANGELOG.md -------');
            if (changelogFile.existsSync()) {
              print(changelogFile.readAsStringSync());
            } else {
              print('No CHANGELOG.md found for $repoName');
            }

            print('------- $repoName pubspec.yaml -------');
            if (pubspecFile.existsSync()) {
              print(pubspecFile.readAsStringSync());
            } else {
              print('No pubspec.yaml found for $repoName');
            }
          }
        } finally {
          if (tempRoot.existsSync()) {
            tempRoot.deleteSync(recursive: true);
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}

/// Ensures that the given [binary] exists on the PATH by running
/// `<binary> --version` and expecting a zero exit code.
Future<void> _ensureBinaryAvailable(String binary) async {
  final result = await Process.run(
    binary,
    <String>['--version'],
    runInShell: true,
  );

  expect(
    result.exitCode,
    0,
    reason: '$binary must be available on PATH for this integration test. '
        'STDOUT: ${result.stdout}\nSTDERR: ${result.stderr}',
  );
}

/// Runs a git command with [args] and asserts that it succeeds.
Future<ProcessResult> _runGit(
  List<String> args, {
  String? workingDirectory,
}) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: workingDirectory,
    runInShell: true,
  );

  if (result.exitCode != 0) {
    fail(
      'git ${args.join(' ')} failed with exit code ${result.exitCode}\n'
      'STDOUT: ${result.stdout}\n'
      'STDERR: ${result.stderr}',
    );
  }

  return result;
}

/// Initializes a regular git repository for [projectName] in [repoDir]
/// and connects it to a local bare remote under [remotesRoot].
Future<void> _initializeGitRepoWithRemote({
  required String projectName,
  required Directory repoDir,
  required Directory remotesRoot,
}) async {
  // Create bare remote repository ("a_remote.git" / "b_remote.git").
  final remoteDir = Directory(
    path.join(remotesRoot.path, '${projectName}_remote.git'),
  );
  if (!remoteDir.existsSync()) {
    remoteDir.createSync(recursive: true);
  }

  await _runGit(
    <String>['init', '--bare', remoteDir.path],
    workingDirectory: remotesRoot.path,
  );

  // Initialize git in the master repository directory.
  await _runGit(<String>['init'], workingDirectory: repoDir.path);

  // Configure a local user so that commits succeed even in clean CI images.
  await _runGit(
    <String>['config', 'user.email', 'test@example.com'],
    workingDirectory: repoDir.path,
  );
  await _runGit(
    <String>['config', 'user.name', 'Test User'],
    workingDirectory: repoDir.path,
  );

  await _runGit(
    <String>['remote', 'add', 'origin', remoteDir.path],
    workingDirectory: repoDir.path,
  );

  await _runGit(<String>['add', '.'], workingDirectory: repoDir.path);

  await _runGit(
    <String>['commit', '-m', 'Initial commit for $projectName'],
    workingDirectory: repoDir.path,
  );

  // Normalize branch name to main so that pushing works reliably.
  await _runGit(
    <String>['branch', '-M', 'main'],
    workingDirectory: repoDir.path,
  );

  await _runGit(
    <String>['push', '-u', 'origin', 'main'],
    workingDirectory: repoDir.path,
  );
}
