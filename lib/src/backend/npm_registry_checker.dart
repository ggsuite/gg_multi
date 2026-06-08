// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_lang/gg_lang.dart';

import 'pub_dev_checker.dart' show PackagePublishInfo;

/// The npm counterpart of [PubDevChecker]: checks whether published versions
/// are visible on npm, backed by gg_lang's [RegistryWaiter] over an
/// [NpmRegistry] (`npm view <name> version`).
///
/// A thin gg_multi-side adapter — registry interaction and the poll/wait logic
/// live in gg_lang.
class NpmRegistryChecker {
  /// Creates a new checker. Inject [waiter] in tests; production resolves a
  /// [RegistryWaiter] over the npm registry from the language catalog.
  NpmRegistryChecker({
    RegistryWaiter? waiter,
    LanguageCatalog? catalog,
    Future<void> Function(Duration duration)? delay,
    this.pollInterval = const Duration(seconds: 5),
    this.timeout = const Duration(minutes: 2),
  })  : _waiter = waiter,
        _catalog = catalog,
        _delay = delay;

  final RegistryWaiter? _waiter;
  final LanguageCatalog? _catalog;
  final Future<void> Function(Duration duration)? _delay;

  /// Delay between poll attempts.
  final Duration pollInterval;

  /// Maximum waiting time for a version to appear on npm.
  final Duration timeout;

  /// Returns publish info for [packageName] (whether dependents must wait for
  /// npm availability).
  Future<PackagePublishInfo> getPackagePublishInfo({
    required String packageName,
  }) async {
    final waiter = await _resolveWaiter();
    return PackagePublishInfo(
      packageName: packageName,
      waitsForPubDev: await waiter.isPublished(packageName: packageName),
    );
  }

  /// Returns whether [version] of [packageName] is already visible on npm.
  Future<bool> isVersionAvailable({
    required String packageName,
    required String version,
  }) async {
    final waiter = await _resolveWaiter();
    return waiter.isVersionAvailable(
      packageName: packageName,
      version: version,
    );
  }

  /// Waits until [version] of [packageName] is visible on npm.
  Future<void> waitUntilVersionAvailable({
    required String packageName,
    required String version,
    required void Function(String message) ggLog,
  }) async {
    final waiter = await _resolveWaiter();
    await waiter.waitUntilVersionAvailable(
      packageName: packageName,
      version: version,
    );
  }

  // ...........................................................................
  Future<RegistryWaiter> _resolveWaiter() async {
    if (_waiter != null) {
      return _waiter;
    }
    // coverage:ignore-start
    final catalog = _catalog ?? await LanguageCatalog.load();
    final registry = const RegistryFactory().forProjectType(
      ProjectType.typescript,
      spec: catalog.spec(ProjectType.typescript),
    );
    return RegistryWaiter(
      registry: registry,
      registryName: 'npm',
      delay: _delay,
      pollInterval: pollInterval,
      timeout: timeout,
    );
    // coverage:ignore-end
  }
}
