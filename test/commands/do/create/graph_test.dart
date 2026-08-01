// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_multi/src/commands/do/create/graph.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../rm_console_colors_helper.dart';

void main() {
  group('GraphCommand', () {
    late Directory tempDir;
    late CommandRunner<void> runner;
    final messages = <String>[];

    void ggLog(String msg) {
      messages.add(rmConsoleColors(msg));
    }

    /// Writes a Dart package into `<root>/<org>/<name>`.
    void writePackage({
      required String root,
      required String org,
      required String name,
      List<String> dependencies = const <String>[],
      List<String> devDependencies = const <String>[],
    }) {
      final dir = Directory(p.join(tempDir.path, root, org, name))
        ..createSync(recursive: true);

      final buffer = StringBuffer('name: $name\nversion: 1.0.0\n');
      if (dependencies.isNotEmpty) {
        buffer.writeln('dependencies:');
        for (final dep in dependencies) {
          buffer.writeln('  $dep: ^1.0.0');
        }
      }
      if (devDependencies.isNotEmpty) {
        buffer.writeln('dev_dependencies:');
        for (final dep in devDependencies) {
          buffer.writeln('  $dep: ^1.0.0');
        }
      }

      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
        buffer.toString(),
      );
    }

    /// The single message the command wrote to stdout.
    String output() {
      expect(messages, hasLength(1));
      return messages.single;
    }

    /// All edges of the mermaid output as `from arrow to`.
    List<String> mermaidEdges() => output()
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.contains('-->') || l.contains('-.->'))
        .toList();

    setUp(() {
      messages.clear();
      tempDir = Directory.systemTemp.createTempSync('graph_test_');
      runner = CommandRunner<void>('test', 'GraphCommand Test')
        ..addCommand(GraphCommand(ggLog: ggLog));

      // The master workspace: `a` depends on `b` and - redundantly - on `c`,
      // `b` depends on `c`. `a` also has a dev dependency on `d` and a third
      // party dependency that is no local repository.
      writePackage(
        root: '.master',
        org: 'org_a',
        name: 'a',
        dependencies: <String>['b', 'c', 'external_pkg'],
        devDependencies: <String>['d'],
      );
      writePackage(
        root: '.master',
        org: 'org_a',
        name: 'b',
        dependencies: <String>['c'],
      );
      writePackage(root: '.master', org: 'org_a', name: 'c');
      writePackage(root: '.master', org: 'org_a', name: 'd');

      // A second organization, only reachable via `--org`.
      writePackage(root: '.master', org: 'org_b', name: 'e');

      // A TypeScript repo depending on two npm packages whose names collapse
      // to the same mermaid node id.
      final ts = Directory(p.join(tempDir.path, '.master', 'org_a', 'ts_pkg'))
        ..createSync(recursive: true);
      File(p.join(ts.path, 'package.json')).writeAsStringSync(
        jsonEncode(<String, dynamic>{
          'name': 'ts_pkg',
          'version': '1.0.0',
          'dependencies': <String, String>{
            '@scope/pkg': '^1.0.0',
            '_scope_pkg': '^1.0.0',
          },
        }),
      );

      // A ticket that has `b` checked out.
      writePackage(
        root: p.join('tickets', '1'),
        org: 'org_a',
        name: 'b',
        dependencies: <String>['c'],
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Future<void> run(String workingDir, [List<String> args = const []]) =>
        runner.run(<String>['graph', '--input', workingDir, ...args]);

    String masterDir() => tempDir.path;
    String ticketDir() => p.join(tempDir.path, 'tickets', '1');

    group('outside a ticket', () {
      test('graphs the whole master workspace', () async {
        await run(masterDir(), <String>['--no-transitive-reduction']);

        expect(output(), startsWith('flowchart LR'));
        expect(output(), contains('a["a"]'));
        expect(output(), contains('e["e"]'));
        expect(mermaidEdges(), contains('a --> b'));
        expect(mermaidEdges(), contains('a --> c'));
        expect(mermaidEdges(), contains('b --> c'));
      });

      test('--org narrows the graph down to one organization', () async {
        await run(masterDir(), <String>['--org', 'org_b']);

        expect(output(), contains('e["e"]'));
        expect(output(), isNot(contains('a["a"]')));
      });

      test('--org throws for an unknown organization', () async {
        await expectLater(
          run(masterDir(), <String>['--org', 'nope']),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('nope'),
            ),
          ),
        );
      });
    });

    group('inside a ticket', () {
      test('graphs the ticket repos and what they reach', () async {
        await run(ticketDir());

        // `b` is checked out and reaches `c`. `a` depends on `b`, but is not
        // reachable from it, so it stays out.
        expect(output(), contains('b["b"]'));
        expect(output(), contains('c["c"]'));
        expect(output(), isNot(contains('a["a"]')));
        expect(output(), contains('class b ticket;'));
      });

      test('takes the checked out repo instead of the master one', () async {
        await run(ticketDir(), <String>['--format=json']);

        final json = jsonDecode(output()) as Map<String, dynamic>;
        final nodes = (json['nodes'] as List).cast<Map<String, dynamic>>();
        final b = nodes.firstWhere((n) => n['name'] == 'b');
        expect(b['inTicket'], isTrue);
        expect(b['path'], p.join('org_a', 'b'));

        final c = nodes.firstWhere((n) => n['name'] == 'c');
        expect(c['inTicket'], isFalse);
      });
    });

    group('--transitive-reduction', () {
      test('hides the edge that a longer path already implies', () async {
        await run(masterDir());

        expect(mermaidEdges(), contains('a --> b'));
        expect(mermaidEdges(), contains('b --> c'));
        expect(mermaidEdges(), isNot(contains('a --> c')));
      });

      test('--no-transitive-reduction keeps it', () async {
        await run(masterDir(), <String>['--no-transitive-reduction']);

        expect(mermaidEdges(), contains('a --> c'));
      });
    });

    group('--dev-dependencies', () {
      test('shows dev dependencies as dashed edges by default', () async {
        await run(masterDir());

        expect(mermaidEdges(), contains('a -.-> d'));
      });

      test('--no-dev-dependencies drops them', () async {
        await run(masterDir(), <String>['--no-dev-dependencies']);

        // `d` stays a node of the workspace, but the edge to it is gone.
        expect(output(), contains('d["d"]'));
        expect(output(), isNot(contains('-.->')));
      });
    });

    group('--3rdparty-deps', () {
      test('are hidden by default', () async {
        await run(masterDir());

        expect(output(), isNot(contains('external_pkg')));
      });

      test('are shown when requested', () async {
        await run(masterDir(), <String>['--3rdparty-deps']);

        expect(mermaidEdges(), contains('a --> external_pkg'));
        expect(
          output(),
          contains('class _scope_pkg,_scope_pkg_2,external_pkg external;'),
        );
      });

      test('get a unique id even when their names collapse', () async {
        await run(masterDir(), <String>['--3rdparty-deps']);

        // `@scope/pkg` and `_scope_pkg` both sanitize to `_scope_pkg`.
        expect(output(), contains('_scope_pkg["@scope/pkg"]'));
        expect(output(), contains('_scope_pkg_2["_scope_pkg"]'));
        expect(mermaidEdges(), contains('ts_pkg --> _scope_pkg'));
        expect(mermaidEdges(), contains('ts_pkg --> _scope_pkg_2'));
      });

      test('are marked as external in json', () async {
        await run(masterDir(), <String>['--3rdparty-deps', '--format=json']);

        final json = jsonDecode(output()) as Map<String, dynamic>;
        final nodes = (json['nodes'] as List).cast<Map<String, dynamic>>();
        final external = nodes.firstWhere((n) => n['name'] == 'external_pkg');
        expect(external['external'], isTrue);
        expect(external.containsKey('path'), isFalse);
      });
    });

    group('--orientation', () {
      test('is horizontal by default', () async {
        await run(masterDir());
        expect(output(), startsWith('flowchart LR'));
      });

      test('vertical renders top down', () async {
        await run(masterDir(), <String>['--orientation=vertical']);
        expect(output(), startsWith('flowchart TD'));
      });
    });

    group('--format=json', () {
      test('writes a deterministically sorted document', () async {
        await run(masterDir(), <String>['--format=json']);

        final json = jsonDecode(output()) as Map<String, dynamic>;
        expect(json['orientation'], 'horizontal');
        expect(json['transitiveReduction'], isTrue);

        final nodes = (json['nodes'] as List).cast<Map<String, dynamic>>();
        final names = nodes.map((n) => n['name'] as String).toList();
        expect(names, <String>['a', 'b', 'c', 'd', 'e', 'ts_pkg']);
        expect(nodes.first['language'], 'dart');
        expect(nodes.first['organization'], 'org_a');

        final edges = (json['edges'] as List)
            .cast<Map<String, dynamic>>()
            .map((e) => '${e['from']}->${e['to']} dev:${e['dev']}')
            .toList();
        expect(edges, <String>[
          'a->b dev:false',
          'a->d dev:true',
          'b->c dev:false',
        ]);
      });
    });

    test('throws when the workspace holds no repositories', () async {
      final empty = Directory.systemTemp.createTempSync('graph_empty_');
      Directory(p.join(empty.path, '.master')).createSync();
      try {
        await expectLater(
          run(empty.path),
          throwsA(isA<UsageException>()),
        );
      } finally {
        empty.deleteSync(recursive: true);
      }
    });
  });
}
