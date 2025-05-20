// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_capture_print/gg_capture_print.dart';
import 'package:kidney_core/src/backend/constants.dart';
import 'package:kidney_core/src/backend/git_handler.dart';
import 'package:kidney_core/src/commands/add_deps.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../rm_console_colors_helper.dart';

class MockGitCloner extends Mock implements GitHandler {}

void main() {
  group('AddDepsCommand', () {
    late Directory tempDir;
    late Directory dirNoPubspec;
    late Directory dirProject;
    late List<String> logMessages;
    late MockGitCloner mockGitCloner;
    late CommandRunner<void> runner;
    late String workspacePath;

    void ggLog(String message) {
      logMessages.add(rmConsoleColors(message));
    }

    setUp(() {
      logMessages = [];
      mockGitCloner = MockGitCloner();
      when(() => mockGitCloner.cloneRepo(any(), any()))
          .thenAnswer((_) async {});
      tempDir = Directory.systemTemp.createTempSync('add_deps_test');
      workspacePath = path.join(tempDir.path, kidneyMasterFolder);
      Directory(workspacePath).createSync(recursive: true);
      dirNoPubspec = Directory(path.join(workspacePath, 'no_pubspec'))
        ..createSync(recursive: true);
      dirProject = Directory(path.join(workspacePath, 'project'))
        ..createSync(recursive: true);
      runner = CommandRunner<void>('test', 'Test AddDepsCommand');
      runner.addCommand(
        AddDepsCommand(
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
          packageFetcher: (uri) async {
            final segments = uri.pathSegments;
            final packageName = segments.isNotEmpty ? segments.last : '';
            final data = {
              'latest': {
                'pubspec': {
                  'repository':
                      'https://github.com/$packageName/$packageName.git',
                },
              },
            };
            return http.Response(jsonEncode(data), 200);
          },
        ),
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('iterates over dependencies and dev_dependencies', () async {
      const pubspecContent = '''
name: test_project
version: 1.0.0
dependencies:
  json_dart: ^3.5.2
  http: ^0.13.0
dev_dependencies:
  json_serializer: ^1.4.2
''';
      File(path.join(dirProject.path, 'pubspec.yaml'))
          .writeAsStringSync(pubspecContent);

      await runner.run(['add-deps', 'project']);

      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/json_dart/json_dart.git',
          any(),
        ),
      ).called(1);
      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/http/http.git',
          any(),
        ),
      ).called(1);
      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/json_serializer/json_serializer.git',
          any(),
        ),
      ).called(1);

      expect(
        logMessages,
        containsAll([
          'Added repository json_dart from '
              'https://github.com/json_dart/json_dart.git',
          'Added repository http from '
              'https://github.com/http/http.git',
          'Added repository json_serializer from '
              'https://github.com/json_serializer/json_serializer.git',
        ]),
      );
    });

    test('logs message when pubspec.yaml not found', () async {
      await runner.run(['add-deps', 'no_pubspec']);
      expect(
        logMessages,
        contains('pubspec.yaml not found in project '
            'no_pubspec in workspace $workspacePath.'),
      );
    });

    test('logs message when no dependencies found', () async {
      const pubspecContent = '''
name: test_project
version: 1.0.0
dependencies:

dev_dependencies:
''';
      File(path.join(dirNoPubspec.path, 'pubspec.yaml'))
          .writeAsStringSync(pubspecContent);
      await runner.run(['add-deps', 'no_pubspec']);
      expect(
        logMessages,
        contains(
          'No dependencies found in pubspec.yaml for project test_project.',
        ),
      );
    });

    test('does nothing if pubspec.yaml parsing fails', () async {
      final invalidDir = Directory(path.join(workspacePath, 'invalid_pubspec'))
        ..createSync(recursive: true);
      File(path.join(invalidDir.path, 'pubspec.yaml'))
          .writeAsStringSync('bad content');
      logMessages.clear();
      await runner.run(['add-deps', 'invalid_pubspec']);
      expect(
        logMessages.any((m) => m.contains('Error parsing pubspec.yaml:')),
        isTrue,
      );
    });

    test('throws exception when target repository parameter is missing',
        () async {
      final newRunner = CommandRunner<void>('test', 'Test Missing Target');
      newRunner.addCommand(
        AddDepsCommand(
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
        ),
      );
      await expectLater(
        newRunner.run(['add-deps']),
        throwsA(isA<UsageException>()),
      );
    });

    test('logs error and continues when dependency addition fails', () async {
      const pubspecContent = '''
name: test_project
version: 1.0.0
dependencies:
  fail_dep: ^1.0.0
''';
      File(path.join(dirProject.path, 'pubspec.yaml'))
          .writeAsStringSync(pubspecContent);

      when(() => mockGitCloner.cloneRepo(any(), any()))
          .thenThrow(Exception('clone failed'));

      await runner.run(['add-deps', 'project']);

      expect(
        logMessages.any(
          (msg) => msg.contains('Failed to clone dependency fail_dep from '
              'https://github.com/fail_dep/fail_dep.git: '
              'Exception: clone failed'),
        ),
        isTrue,
      );
    });

    test('logs skipping message when no repository URL found for dependency',
        () async {
      const pubspecContent = '''
name: test_project
version: 1.0.0
dependencies:
  no_repo_dep: ^1.0.0
''';
      File(path.join(dirProject.path, 'pubspec.yaml'))
          .writeAsStringSync(pubspecContent);

      // Override the packageFetcher to return JSON without a repository key
      runner = CommandRunner<void>('test', 'Test AddDepsCommand');
      runner.addCommand(
        AddDepsCommand(
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
          packageFetcher: (uri) async {
            final data = {
              'latest': {
                'pubspec': <String, String>{},
              },
            };
            return http.Response(jsonEncode(data), 200);
          },
        ),
      );

      await runner.run(['add-deps', 'project']);
      expect(
        logMessages,
        contains('No repository URL found for '
            'dependency no_repo_dep on pub.dev, skipping.'),
      );
    });

    test('logs error when packageFetcher throws exception for dependency',
        () async {
      const pubspecContent = '''
name: test_project
version: 1.0.0
dependencies:
  fail_fetch_dep: ^1.0.0
''';
      File(path.join(dirProject.path, 'pubspec.yaml'))
          .writeAsStringSync(pubspecContent);

      runner = CommandRunner<void>('test', 'Test AddDepsCommand');
      runner.addCommand(
        AddDepsCommand(
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
          packageFetcher: (uri) async {
            throw Exception('fetch error');
          },
        ),
      );

      await runner.run(['add-deps', 'project']);
      expect(
        logMessages.any(
          (msg) =>
              msg.contains('Failed to fetch repository info for dependency '
                  'fail_fetch_dep: Exception: fetch error'),
        ),
        isTrue,
      );
    });

    test('prints help message when --help is passed', () async {
      final output = await capturePrint(
        code: () async {
          await runner.run(['add-deps', '--help']);
        },
      );
      expect(
        output.first,
        contains('Iterates over all dependencies specified in pubspec.yaml'),
      );
    });

    test('ignores dependencies with dart-lang repository URL', () async {
      final runner2 = CommandRunner<void>('test', 'Test AddDepsCommand');
      runner2.addCommand(
        AddDepsCommand(
          ggLog: ggLog,
          gitCloner: mockGitCloner,
          workspacePath: workspacePath,
          packageFetcher: (uri) async {
            final segments = uri.pathSegments;
            final pkgName = segments.isNotEmpty ? segments.last : '';
            if (pkgName == 'dart_dep') {
              return http.Response(
                '{"latest": {"pubspec": {"repository": "https://github.com/dart-lang/dart_dep.git"}}}',
                200,
              );
            } else if (pkgName == 'other_dep') {
              return http.Response(
                '{"latest": {"pubspec": {"repository": "https://github.com/other_dep/other_dep.git"}}}',
                200,
              );
            }
            return http.Response('{}', 200);
          },
        ),
      );
      const pubspecContent = '''
name: test_project
version: 1.0.0
dependencies:
  dart_dep: ^1.0.0
  other_dep: ^1.0.0
''';
      File(path.join(dirProject.path, 'pubspec.yaml'))
          .writeAsStringSync(pubspecContent);
      await runner2.run(['add-deps', 'project']);
      verifyNever(
        () => mockGitCloner.cloneRepo(
          'https://github.com/dart-lang/dart_dep.git',
          any(),
        ),
      );
      verify(
        () => mockGitCloner.cloneRepo(
          'https://github.com/other_dep/other_dep.git',
          any(),
        ),
      ).called(1);
      expect(
        logMessages.first,
        contains('Ignoring dependency dart_dep from dart-lang repository'),
      );
    });
  });

  group('fetchDependencyRepoUrl', () {
    const packageName = 'test_pkg';

    test('throws exception when response status is not 200', () async {
      Future<http.Response> fakeFetcher(Uri uri) async {
        return http.Response('Not Found', 404);
      }

      expect(
        () async => await fetchDependencyRepoUrl(
          packageName,
          packageFetcher: fakeFetcher,
        ),
        throwsA(
          predicate(
            (e) =>
                e is Exception &&
                e.toString().contains(
                      'Failed to fetch package info '
                      'from pub.dev for $packageName',
                    ),
          ),
        ),
      );
    });

    test('returns null when JSON does not contain latest key', () async {
      Future<http.Response> fakeFetcher(Uri uri) async {
        return http.Response('{}', 200);
      }

      final result = await fetchDependencyRepoUrl(
        packageName,
        packageFetcher: fakeFetcher,
      );
      expect(result, isNull);
    });

    test('returns null when latest exists but no pubspec key', () async {
      Future<http.Response> fakeFetcher(Uri uri) async {
        return http.Response('{"latest": {}}', 200);
      }

      final result = await fetchDependencyRepoUrl(
        packageName,
        packageFetcher: fakeFetcher,
      );
      expect(result, isNull);
    });

    test('returns null when pubspec exists but no repository key', () async {
      Future<http.Response> fakeFetcher(Uri uri) async {
        return http.Response(
          '{"latest": {"pubspec": {}}}',
          200,
        );
      }

      final result = await fetchDependencyRepoUrl(
        packageName,
        packageFetcher: fakeFetcher,
      );
      expect(result, isNull);
    });

    test('returns repository URL when valid JSON provided', () async {
      const repoUrl = 'https://github.com/test_pkg/test_pkg.git';
      Future<http.Response> fakeFetcher(Uri uri) async {
        return http.Response(
          '{"latest": {"pubspec": {"repository": "$repoUrl"}}}',
          200,
        );
      }

      final result = await fetchDependencyRepoUrl(
        packageName,
        packageFetcher: fakeFetcher,
      );
      expect(result, equals(repoUrl));
    });

    test('propagates exception from packageFetcher', () async {
      Future<http.Response> fakeFetcher(Uri uri) async {
        throw Exception('Fetcher error');
      }

      expect(
        () async => await fetchDependencyRepoUrl(
          packageName,
          packageFetcher: fakeFetcher,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('throws error when response body is invalid JSON', () async {
      Future<http.Response> fakeFetcher(Uri uri) async {
        return http.Response('invalid json', 200);
      }

      expect(
        () async => await fetchDependencyRepoUrl(
          packageName,
          packageFetcher: fakeFetcher,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws error when latest is not a map', () async {
      Future<http.Response> fakeFetcher(Uri uri) async {
        return http.Response(
          '{"latest": "not a map"}',
          200,
        );
      }

      expect(
        () async => await fetchDependencyRepoUrl(
          packageName,
          packageFetcher: fakeFetcher,
        ),
        throwsA(isA<TypeError>()),
      );
    });

    test('throws error when pubspec is not a map', () async {
      Future<http.Response> fakeFetcher(Uri uri) async {
        return http.Response(
          '{"latest": {"pubspec": "not a map"}}',
          200,
        );
      }

      expect(
        () async => await fetchDependencyRepoUrl(
          packageName,
          packageFetcher: fakeFetcher,
        ),
        throwsA(isA<TypeError>()),
      );
    });
  });
}
