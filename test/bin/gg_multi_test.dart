// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('bin/gg_multi.dart', () {
    // #########################################################################

    test('should be executable', () async {
      // Execute bin/gg_multi.dart and check if it prints help
      final result = await Process.run(
        'dart',
        ['./bin/gg_multi.dart', 'do', 'add'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
        runInShell: true,
      );

      // Match independent of the platform's line ending.
      final expectedMessages = [
        'Missing target parameter.',
      ];

      // Concatenate stdout and stderr
      final output = (result.stdout as String) + (result.stderr as String);

      for (final msg in expectedMessages) {
        expect(output, contains(msg));
      }
    });
  });
}
