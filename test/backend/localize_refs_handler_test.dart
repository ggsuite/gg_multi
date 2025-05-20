// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kidney_core/src/backend/localize_refs_handler.dart';

class MockProcessRunner extends Mock {
  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  });
}

void main() {
  group('localizeRefs', () {
    late MockProcessRunner mockProcessRunner;

    setUp(() {
      mockProcessRunner = MockProcessRunner();
    });

    test('successfully localizes refs', () async {
      when(
        () => mockProcessRunner(
          'gg_localize_refs',
          ['localize-refs'],
          workingDirectory: 'repoA',
        ),
      ).thenAnswer((_) async => ProcessResult(1, 0, '', ''));

      await localizeRefs(
        'repoA',
        processRunner: mockProcessRunner.call,
      );

      verify(
        () => mockProcessRunner(
          'gg_localize_refs',
          ['localize-refs'],
          workingDirectory: 'repoA',
        ),
      ).called(1);
    });

    test('throws when localize-refs process fails', () async {
      when(
        () => mockProcessRunner(
          'gg_localize_refs',
          ['localize-refs'],
          workingDirectory: 'brokenrepo',
        ),
      ).thenAnswer((_) async => ProcessResult(2, 1, '', 'errorref'));

      expect(
        () => localizeRefs('brokenrepo', processRunner: mockProcessRunner.call),
        throwsA(
          predicate(
            (e) =>
                e is Exception &&
                e.toString() ==
                    'Exception: Failed to localize refs in brokenrepo: '
                        'errorref',
          ),
        ),
      );
    });
  });
}
