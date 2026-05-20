// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_log/gg_log.dart';

/// Processes [items] with [task], running up to [maxParallel] tasks at a time.
///
/// Workers pull from a shared queue in submission order. Each task is
/// awaited individually, so an exception in one task does not cancel the
/// others — but it does propagate out of this function after all
/// already-started workers have settled (via [Future.wait]).
///
/// Callers that want to keep running on failures must catch inside [task]
/// and accumulate errors themselves (see e.g. `can/commit.dart`).
Future<void> runWithLimit<T>(
  Iterable<T> items,
  int maxParallel,
  Future<void> Function(T item) task,
) async {
  final queue = items.toList();
  var nextIndex = 0;

  Future<void> worker() async {
    while (true) {
      if (nextIndex >= queue.length) {
        return;
      }
      final item = queue[nextIndex++];
      await task(item);
    }
  }

  final workers = <Future<void>>[
    for (var i = 0; i < maxParallel && i < queue.length; i++) worker(),
  ];

  await Future.wait(workers);
}

/// Returns a [GgLog] that prepends [prefix] to every line before delegating
/// to [ggLog].
///
/// Useful when several parallel tasks share one log sink and you want to
/// keep their output attributable (e.g. `[gg_kidney_core] ✅ Analyze`).
GgLog prefixedLog(String prefix, GgLog ggLog) {
  return (String line) => ggLog('$prefix$line');
}
