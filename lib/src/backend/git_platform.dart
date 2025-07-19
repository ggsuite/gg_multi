// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kidney_core/src/backend/organization.dart';
import 'package:kidney_core/src/backend/url_parser.dart';

/// Interface for Git platforms like GitHub, Azure DevOps, GitLab.
abstract class GitPlatform {
  /// Builds the full clone URL for a repository.
  String buildRepoUrl(String org, String repo, [String? project]);

  /// Fetches the list of repositories for an organization.
  Future<List<Map<String, dynamic>>> fetchOrgRepos(
    String org, {
    http.Client? client,
  });

  /// Extracts organization information from a URL.
  Organization? extractOrgFromUrl(String url);

  /// Builds the base URL for the organization.
  String buildBaseUrl(String org, [String? project]);
}

/// GitHub implementation of GitPlatform.
class GitHubPlatform implements GitPlatform {
  @override
  String buildRepoUrl(String org, String repo, [String? project]) {
    return 'https://github.com/$org/$repo.git';
  }

  @override
  Future<List<Map<String, dynamic>>> fetchOrgRepos(
    String org, {
    http.Client? client,
  }) async {
    client ??= http.Client();
    final uri = Uri.parse('https://api.github.com/orgs/$org/repos');
    final response = await client.get(uri);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch repositories for organization $org: '
        '${response.body}',
      );
    }
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  @override
  Organization? extractOrgFromUrl(String url) {
    final parsed = const UrlParser().parse(url);
    if (parsed.platformType != 'github') return null;
    return Organization(
      name: parsed.org ?? '',
      url: buildBaseUrl(parsed.org ?? ''),
    );
  }

  @override
  String buildBaseUrl(String org, [String? project]) {
    return 'https://github.com/$org/';
  }
}

/// Azure DevOps implementation of GitPlatform.
class AzureDevOpsPlatform implements GitPlatform {
  @override
  String buildRepoUrl(String org, String repo, [String? project]) {
    if (project == null) {
      throw ArgumentError('Project name is required for Azure DevOps.');
    }
    return 'https://ssh.dev.azure.com:v3/$org/$project/$repo.git';
  }

  @override
  Future<List<Map<String, dynamic>>> fetchOrgRepos(
    String org, {
    http.Client? client,
  }) async {
    // Note: Azure DevOps API for fetching repos is more complex and requires
    // authentication. This is a placeholder; implement actual API call if
    // needed.
    throw UnimplementedError(
      'Fetching org repos not implemented for Azure DevOps.',
    );
  }

  @override
  Organization? extractOrgFromUrl(String url) {
    final parsed = const UrlParser().parse(url);
    if (parsed.platformType != 'azure') return null;
    return Organization(
      name: parsed.org ?? '',
      url: buildBaseUrl(parsed.org ?? '', parsed.project),
      projectName: parsed.project,
    );
  }

  @override
  String buildBaseUrl(String org, [String? project]) {
    return project != null
        ? 'https://ssh.dev.azure.com:v3/$org/$project/'
        : 'https://ssh.dev.azure.com:v3/$org/';
  }
}
