// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_multi/src/backend/parallel.dart';
import 'package:test/test.dart';

void main() {
  group('runWithLimit', () {
    test('processes every item exactly once', () async {
      final seen = <int>[];
      await runWithLimit<int>(
        [1, 2, 3, 4, 5],
        2,
        (i) async {
          seen.add(i);
        },
      );
      expect(seen, unorderedEquals([1, 2, 3, 4, 5]));
    });

    test('limits concurrency to maxParallel', () async {
      var inFlight = 0;
      var maxObserved = 0;
      await runWithLimit<int>(
        List.generate(8, (i) => i),
        3,
        (i) async {
          inFlight++;
          if (inFlight > maxObserved) {
            maxObserved = inFlight;
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
          inFlight--;
        },
      );
      expect(maxObserved, lessThanOrEqualTo(3));
      expect(maxObserved, greaterThan(1));
    });

    test('handles fewer items than workers', () async {
      final seen = <int>[];
      await runWithLimit<int>(
        [42],
        4,
        (i) async => seen.add(i),
      );
      expect(seen, equals([42]));
    });

    test('handles empty iterable', () async {
      await runWithLimit<int>(
        const <int>[],
        4,
        (i) async => fail('must not be called'),
      );
    });

    test('rethrows first error after all started tasks settle', () async {
      final completed = <int>[];
      Object? thrown;
      try {
        await runWithLimit<int>(
          [1, 2, 3],
          2,
          (i) async {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            if (i == 2) {
              throw StateError('boom on $i');
            }
            completed.add(i);
          },
        );
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isA<StateError>());
      // The other tasks must still have completed.
      expect(completed, containsAll(<int>[1, 3]));
    });
  });

  group('prefixedLog', () {
    test('prepends the prefix to every line', () {
      final captured = <String>[];
      final log = prefixedLog('[repo] ', captured.add);
      log('hello');
      log('world');
      expect(captured, equals(['[repo] hello', '[repo] world']));
    });

    test('passes an empty prefix through unchanged', () {
      final captured = <String>[];
      final log = prefixedLog('', captured.add);
      log('plain');
      expect(captured, equals(['plain']));
    });
  });
}
