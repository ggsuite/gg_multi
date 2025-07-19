// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:kidney_core/src/backend/git_platform.dart';

/// Result of URL parsing.
class ParseResult {
  /// The organization name
  final String? org;

  /// The repository name
  final String? repo;

  /// The project name (Azure)
  final String? project;

  /// The platform type
  final String platformType;

  /// Constructor
  ParseResult({
    this.org,
    this.repo,
    this.project,
    required this.platformType,
  });
}

/// Unified URL parser for different git platforms.
class UrlParser {
  /// Constructor
  const UrlParser();

  /// Parses the given targetArg and returns ParseResult
  ParseResult parse(String targetArg) {
    // Clean trailing '/' and '#'
    var cleaned = targetArg;
    while (cleaned.endsWith('/') || cleaned.endsWith('#')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }

    // Detect platform based on format
    if (cleaned.startsWith('git@ssh.dev.azure.com:')) {
      return _parseAzure(cleaned);
    } else if (cleaned.startsWith('git@')) {
      return _parseGitHubSsh(cleaned);
    } else if (Uri.tryParse(cleaned)?.scheme.startsWith('http') ?? false) {
      return _parseHttp(cleaned);
    } else if (cleaned.contains('/')) {
      return _parseUsernameRepo(cleaned);
    } else {
      return _parsePlainRepo(cleaned);
    }
  }

  ParseResult _parseAzure(String url) {
    final afterColon = url.split(':').skip(1).join(':');
    final segments = afterColon.split('/');
    if (segments.length >= 3) {
      return ParseResult(
        org: segments[1],
        project: segments[2],
        repo: segments.length > 3 ? segments[3].replaceAll('.git', '') : null,
        platformType: 'azure',
      );
    }
    return ParseResult(platformType: 'unknown');
  }

  ParseResult _parseGitHubSsh(String url) {
    final sshRegex = RegExp(r'^git@[^:]+:([^/]+)/(.+?)(?:\.git)?$');
    final match = sshRegex.firstMatch(url);
    if (match != null) {
      return ParseResult(
        org: match.group(1),
        repo: match.group(2)!.replaceAll('.git', ''),
        platformType: 'github',
      );
    }
    return ParseResult(platformType: 'unknown');
  }

  ParseResult _parseHttp(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return ParseResult(platformType: 'unknown');
    final host = uri.host.toLowerCase();
    final platform = host.contains('azure')
        ? 'azure'
        : (host.contains('github') ? 'github' : 'unknown');
    final segments =
        uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
    if (segments.isEmpty) return ParseResult(platformType: platform);
    if (platform == 'azure' && segments[0] == 'v3') {
      // Azure-specific: skip 'v3'
      return ParseResult(
        org: segments.length > 1 ? segments[1] : null,
        project: segments.length > 2 ? segments[2] : null,
        repo: segments.length > 3 ? segments[3].replaceAll('.git', '') : null,
        platformType: 'azure',
      );
    }
    return ParseResult(
      org: segments[0],
      repo: segments.length > 1 ? segments[1].replaceAll('.git', '') : null,
      platformType: platform,
    );
  }

  ParseResult _parseUsernameRepo(String target) {
    final parts = target.split('/');
    if (parts.length == 2) {
      return ParseResult(
        org: parts[0],
        repo: parts[1],
        platformType: 'github', // Assume GitHub as default
      );
    }
    return ParseResult(platformType: 'unknown');
  }

  ParseResult _parsePlainRepo(String repo) {
    if (repo.contains('/') || repo.contains(':')) {
      // Invalid plain repo format
      return ParseResult(platformType: 'unknown');
    }
    return ParseResult(
      org: null,
      repo: repo,
      platformType: 'unknown',
    );
  }

  /// Returns the platform instance based on type.
  GitPlatform getPlatform(String type) {
    switch (type) {
      case 'github':
        return GitHubPlatform();
      case 'azure':
        return AzureDevOpsPlatform();
      default:
        throw ArgumentError('Unknown platform: $type');
    }
  }
}
