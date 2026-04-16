// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Loads pub.dev metadata and waits until published versions become visible.
class PubDevChecker {
  /// Creates a new checker with injectable network and delay dependencies.
  PubDevChecker({
    http.Client? httpClient,
    Future<void> Function(Duration duration)? delay,
    Duration? pollInterval,
    Duration? timeout,
  })  : _httpClient = httpClient ?? http.Client(),
        _delay = delay ?? Future<void>.delayed,
        pollInterval = pollInterval ?? const Duration(seconds: 15),
        timeout = timeout ?? const Duration(minutes: 2);

  final http.Client _httpClient;
  final Future<void> Function(Duration duration) _delay;

  /// Delay between poll attempts.
  final Duration pollInterval;

  /// Maximum waiting time for a version to appear on pub.dev.
  final Duration timeout;

  /// Returns the publish target configured for the package
  Future<PackagePublishInfo> getPackagePublishInfo({
    required String packageName,
  }) async {
    final isAvailableOnPubDev = await packageExistsOnPubDev(
      packageName: packageName,
    );

    return PackagePublishInfo(
      packageName: packageName,
      waitsForPubDev: isAvailableOnPubDev,
    );
  }

  /// Returns whether [packageName] exists on pub.dev.
  Future<bool> packageExistsOnPubDev({
    required String packageName,
  }) async {
    final response = await _getPackageResponse(packageName: packageName);

    if (response == null) {
      return false;
    }

    if (response.statusCode == 404) {
      return false;
    }

    if (response.statusCode >= 500) {
      return false;
    }

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to query pub.dev for $packageName '
        '(HTTP ${response.statusCode}).',
      );
    }

    return true;
  }

  /// Returns whether [version] of [packageName] is already visible on pub.dev.
  Future<bool> isVersionAvailable({
    required String packageName,
    required String version,
  }) async {
    final response = await _getPackageResponse(packageName: packageName);

    if (response == null) {
      return false;
    }

    if (response.statusCode == 404) {
      return false;
    }

    if (response.statusCode >= 500) {
      return false;
    }

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to query pub.dev for $packageName '
        '(HTTP ${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid pub.dev response for $packageName.');
    }

    final versions = decoded['versions'];
    if (versions is! List) {
      throw Exception('Invalid pub.dev versions payload for $packageName.');
    }

    for (final entry in versions) {
      if (entry is Map<String, dynamic>) {
        final pubspec = entry['pubspec'];
        if (pubspec is Map<String, dynamic>) {
          final candidate = pubspec['version']?.toString();
          if (candidate == version) {
            return true;
          }
        }
      }
    }

    return false;
  }

  /// Waits until [version] of [packageName] is visible on pub.dev.
  Future<void> waitUntilVersionAvailable({
    required String packageName,
    required String version,
    required void Function(String message) ggLog,
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (true) {
      final available = await isVersionAvailable(
        packageName: packageName,
        version: version,
      );

      if (available) {
        return;
      }

      if (DateTime.now().isAfter(deadline)) {
        throw Exception(
          'Timed out waiting for $packageName $version to become '
          'available on pub.dev after ${timeout.inSeconds} seconds.',
        );
      }

      await _delay(pollInterval);
    }
  }

  /// Loads the package API response from pub.dev.
  Future<http.Response?> _getPackageResponse({
    required String packageName,
  }) async {
    final uri = Uri.parse('https://pub.dev/api/packages/$packageName');

    try {
      return await _httpClient.get(uri);
    } on SocketException {
      return null;
    } on http.ClientException {
      return null;
    }
  }
}

/// Describes how a package is published.
class PackagePublishInfo {
  /// Creates a publish info model.
  const PackagePublishInfo({
    required this.packageName,
    required this.waitsForPubDev,
  });

  /// The package name from pubspec.yaml.
  final String packageName;

  /// Whether dependent publishes must wait for pub.dev availability.
  final bool waitsForPubDev;
}
