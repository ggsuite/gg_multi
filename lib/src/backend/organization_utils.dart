// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

/// A utility class to manage organizations
/// associated with the master workspace.
/// Stores organizations in a JSON file (.organizations) with name and base URL.
class OrganizationUtils {
  /// Reads the organizations from the master workspace .organizations file.
  /// Returns a map of organization name to URL.
  static Map<String, String> readOrganizations(String workspacePath) {
    final organizationsFile = File(path.join(workspacePath, '.organizations'));
    if (!organizationsFile.existsSync()) {
      return <String, String>{};
    }
    try {
      final content = organizationsFile.readAsStringSync();
      final data = jsonDecode(content);
      if (data is Map<String, dynamic>) {
        return data.map((key, value) => MapEntry(key, value.toString()));
      }
    } catch (_) {
      // If parsing fails, treat as empty (could consider throwing in future)
    }
    return <String, String>{};
  }

  /// Writes the organizations to the .organizations file.
  static void writeOrganizations(
    String workspacePath,
    Map<String, String> data,
  ) {
    final organizationsFile = File(path.join(workspacePath, '.organizations'));
    organizationsFile.writeAsStringSync(jsonEncode(data), flush: true);
  }

  /// Appends a new organization (if not already present) for a given repo URL.
  /// Does nothing if the organization already exists.
  static void appendOrganization(String workspacePath, String repoUrl) {
    final orgName = extractOrganizationFromUrl(repoUrl);
    if (orgName == null || orgName.isEmpty) {
      return;
    }
    final orgUrl = buildBaseUrl(repoUrl, orgName);
    final orgs = readOrganizations(workspacePath);
    if (!orgs.containsKey(orgName)) {
      orgs[orgName] = orgUrl;
      writeOrganizations(workspacePath, orgs);
    }
  }

  /// Extracts the organization name from a git repo URL (SSH or HTTP).
  /// Only accepts names with [a-z0-9_-]. Returns null for other patterns.
  static String? extractOrganizationFromUrl(String url) {
    // Azure SSH: git@ssh.dev.azure.com:v3/<org>/<project>/<repo>
    final azSsh = RegExp(r'^git@ssh\.dev\.azure\.com:v3/([^/]+)/');
    final azHttp = RegExp(r'^https?://ssh\.dev\.azure\.com[:/]+v3/([^/]+)/');
    // SSH: git@github.com:<org>/<repo>.git
    final sshMatch =
        RegExp(r'^git@[^:]+:([^/]+)/[^/]+(?:\.git)?').firstMatch(url);
    if (sshMatch != null) {
      String? orgName = sshMatch.group(1);
      if (_isValidOrgName(orgName)) {
        return orgName;
      }
    }
    final azSshMatch = azSsh.firstMatch(url);
    if (azSshMatch != null) {
      String? orgName = azSshMatch.group(1);
      if (_isValidOrgName(orgName)) {
        return orgName;
      }
    }
    final azHttpMatch = azHttp.firstMatch(url);
    if (azHttpMatch != null) {
      String? orgName = azHttpMatch.group(1);
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

  /// Builds the base URL for the organization given a repo URL and org name.
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
}
