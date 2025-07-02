// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

import 'organization.dart';

/// A utility class to manage organizations
/// associated with the master workspace. Caches entries in a buffer.
class OrganizationUtils {
  static List<Organization>? _cache;
  static String? _cachePath;

  /// Returns all organizations (from cache or file).
  static List<Organization> readOrganizations(String workspacePath) {
    if (_cache != null && _cachePath == workspacePath) {
      return _cache!;
    }
    final organizationsFile = File(path.join(workspacePath, '.organizations'));
    if (!organizationsFile.existsSync()) {
      _cachePath = workspacePath;
      _cache = <Organization>[];
      return _cache!;
    }
    try {
      final content = organizationsFile.readAsStringSync();
      final decoded = jsonDecode(content);
      if (decoded is List) {
        _cachePath = workspacePath;
        _cache = decoded
            .map((e) => Organization.fromMap(e as Map<String, dynamic>))
            .toList();
        return _cache!;
      } else if (decoded is Map) {
        // Legacy: Map<String, String> → List<Organization>
        final List<Organization> legacyOrgs = [];
        decoded.forEach((name, url) {
          legacyOrgs.add(
            Organization(
              name: name as String,
              url: url.toString(),
            ),
          );
        });
        _cachePath = workspacePath;
        _cache = legacyOrgs;
        return _cache!;
      }
      // Malformed
    } catch (_) {
      // Failure reading/parsing
    }
    _cachePath = workspacePath;
    _cache = <Organization>[];
    return _cache!;
  }

  /// Writes the given organizations to file and updates the buffer.
  static void writeOrganizations(
    String workspacePath,
    List<Organization> orgs,
  ) {
    final organizationsFile = File(path.join(workspacePath, '.organizations'));
    final list = orgs.map((o) => o.toMap()).toList();
    organizationsFile.writeAsStringSync(jsonEncode(list), flush: true);
    _cachePath = workspacePath;
    _cache = orgs;
  }

  /// Adds an organization if not present by name. Updates disk and cache.
  static void addOrganization(String workspacePath, Organization org) {
    final orgs = List<Organization>.from(readOrganizations(workspacePath));
    if (orgs.any((o) => o.name == org.name)) {
      return;
    }
    orgs.add(org);
    writeOrganizations(workspacePath, orgs);
  }

  /// Finds organization by name.
  static Organization? getOrganizationByName(
    String workspacePath,
    String name,
  ) {
    return readOrganizations(workspacePath)
        .where((org) => org.name == name)
        .cast<Organization?>()
        .firstWhere((o) => o != null, orElse: () => null);
  }

  /// Finds organization by a repo URL (extracts org name, then matches).
  static Organization? getOrganizationByRepoUrl(
    String workspacePath,
    String repoUrl,
  ) {
    final orgName = extractOrganizationFromUrl(repoUrl);
    if (orgName == null) return null;
    return getOrganizationByName(workspacePath, orgName);
  }

  /// Appends a new organization (if not present) for a given repo URL.
  /// Calls addOrganization and thus writeOrganizations.
  static void appendOrganization(String workspacePath, String repoUrl) {
    final orgName = extractOrganizationFromUrl(repoUrl);
    if (orgName == null || orgName.isEmpty) {
      return;
    }
    final orgUrl = buildBaseUrl(repoUrl, orgName);
    addOrganization(
      workspacePath,
      Organization(name: orgName, url: orgUrl),
    );
  }

  /// Extracts the organization name from a git repo URL (SSH or HTTP).
  /// Only accepts names with [a-z0-9_-]. Returns null for other patterns.
  static String? extractOrganizationFromUrl(String url) {
    // Azure SSH: git@ssh.dev.azure.com:v3/<org>/<project>/<repo>
    final azSsh = RegExp(r'^git@ssh\.dev\.azure\.com:v3/([a-z0-9_-]+)/');
    final azHttp =
        RegExp(r'^https?://ssh\.dev\.azure\.com[:/]+v3/([a-z0-9_-]+)/');
    // SSH: git@github.com:<org>/<repo>.git
    final sshRegex = RegExp(r'^git@[^:]+:([^/]+)/[^/]+(?:\.git)?');

    // 1. Azure SSH first
    final azSshMatch = azSsh.firstMatch(url);
    if (azSshMatch != null) {
      String? orgName = azSshMatch.group(1);
      if (_isValidOrgName(orgName)) {
        return orgName;
      }
    }
    // 2. Azure HTTP next
    final azHttpMatch = azHttp.firstMatch(url);
    if (azHttpMatch != null) {
      String? orgName = azHttpMatch.group(1);
      if (_isValidOrgName(orgName)) {
        return orgName;
      }
    }
    // 3. SSH (generic) last
    final sshMatch = sshRegex.firstMatch(url);
    if (sshMatch != null) {
      String? orgName = sshMatch.group(1);
      if (_isValidOrgName(orgName)) {
        return orgName;
      }
    }
    try {
      final trimmed =
          url.endsWith('/') ? url.substring(0, url.length - 1) : url;
      final uri = Uri.parse(trimmed);
      if (uri.pathSegments.isNotEmpty &&
          uri.pathSegments.first.trim().isNotEmpty) {
        String? orgName = uri.pathSegments.first.trim();
        if (_isValidOrgName(orgName)) {
          return orgName;
        }
      }
    } catch (_) {
      // Ignore parse errors
    }
    return null; // Not a recognized format
  }

  /// Returns true if name is valid organization name: [a-z0-9_-] only.
  static bool _isValidOrgName(String? name) =>
      name != null && RegExp(r'^[a-z0-9_-]+').hasMatch(name);

  /// Builds the base URL for an organization, given a repo URL and org name.
  static String buildBaseUrl(String repoUrl, String org) {
    if (repoUrl.contains('ssh.dev.azure.com')) {
      return 'https://ssh.dev.azure.com:v3/$org/';
    }
    if (repoUrl.startsWith('git@')) {
      // Assume github for classic SSH
      return 'https://github.com/$org/';
    }
    final uri = Uri.parse(repoUrl);
    // Only accept hostnames that are valid domain names
    // (letters, digits, hyphens, periods)
    if (uri.host.isEmpty || !RegExp(r'^[A-Za-z0-9.-]+$').hasMatch(uri.host)) {
      // Host is not a valid domain, fallback to github
      return 'https://github.com/$org/';
    }
    return '${uri.scheme}://${uri.host}/$org/';
  }

  /// For tests only: clear the cache.
  static void clearCache() {
    _cache = null;
    _cachePath = null;
  }
}
