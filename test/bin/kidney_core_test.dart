// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('bin/kidney_core.dart', () {
    // #########################################################################

    test('should be executable', () async {
      // Execute bin/kidney_core.dart and check if it prints help
      final result = await Process.run(
        'dart',
        ['./bin/kidney_core.dart', 'add'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
        runInShell: true,
      );

      final expectedMessages = [
        'Missing target parameter.\r\n',
      ];

      // Concatenate stdout and stderr
      final output = (result.stdout as String) + (result.stderr as String);

      for (final msg in expectedMessages) {
        expect(output, contains(msg));
      }
    });
  });
}
