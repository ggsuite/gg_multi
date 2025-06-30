// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_log/gg_log.dart';
import '../../backend/organization_utils.dart';

/// Command to add an organization to the
/// .organizations file in the master workspace.
class AddOrganizationCommand extends Command<void> {
  /// Constructor
  AddOrganizationCommand({
    required this.ggLog,
    required this.workspacePath,
  });

  /// Logger function
  final GgLog ggLog;

  /// Absolute path to the master workspace
  final String workspacePath;

  @override
  String get name => 'organization';

  @override
  String get description => 'Adds an organization to .organizations file.';

  @override
  Future<void> run() async {
    if (argResults!.rest.isEmpty) {
      throw UsageException('Missing organization parameter.', usage);
    }
    final orgArg = argResults!.rest.first;
    // Compose repo URL candidate
    final String repoUrl;
    if (orgArg.startsWith('http') || orgArg.startsWith('git@')) {
      repoUrl = orgArg;
    } else {
      repoUrl = 'https://github.com/$orgArg';
    }
    final orgName = OrganizationUtils.extractOrganizationFromUrl(repoUrl);
    if (orgName == null || orgName.isEmpty) {
      ggLog(red('Could not determine organization name from input: $orgArg'));
      return;
    }
    final orgsBefore = OrganizationUtils.readOrganizations(workspacePath);
    OrganizationUtils.appendOrganization(workspacePath, repoUrl);
    if (orgsBefore.containsKey(orgName)) {
      ggLog(darkGray('Organization $orgName already exists.'));
    } else {
      ggLog(green('Added organization $orgName.'));
    }
  }
}
