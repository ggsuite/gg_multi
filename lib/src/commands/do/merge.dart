// @license
// Copyright (c) 2019 - 2025 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_args/gg_args.dart';

import 'publish.dart';

/// Command to merge all repos of the ticket into their main branches.
///
/// Runs the exact same flow as [DoPublishCommand] — review, `can publish`,
/// unlocalize refs, version bump, changelog release, merge, push, ticket
/// cleanup — with the two release steps left out: **nothing is uploaded to a
/// package registry and no version tag is created**.
///
/// Because the merged state is therefore never resolvable against a registry,
/// the command refuses to run while any repository of the ticket still
/// redirects a dependency to a local working copy (a non-empty
/// `pubspec_overrides.yaml`); such a ticket has to be published. `--force`
/// merges anyway.
///
/// Since a merge leaves no tag behind, the work it puts on the main branch is
/// unreleased. `PublishSkipCheck` therefore compares against the last **tag**,
/// not against the main branch — so the next `gg do publish` still sees those
/// commits instead of mistaking the repository for unchanged.
class DoMergeCommand extends DoPublishCommand {
  /// Constructor
  DoMergeCommand({
    required super.ggLog,
    super.name = 'merge',
    super.description =
        'Merges all repositories of the current ticket into their main '
            'branches without publishing them.',
    super.mergeOnly = true,
    super.ggDoCommit,
    super.unlocalizeRefs,
    super.restorePublishTo,
    super.ggDoPush,
    super.ggDoPublish,
    super.sortedProcessingList,
    super.processRunner,
    super.canPublishCommand,
    super.doReviewCommand,
    super.getVersionCommand,
    super.setRefVersionCommand,
    super.getRefVersionCommand,
    super.pubDevChecker,
    super.npmChecker,
    super.publishSkipCheck,
    super.doConfigurePublishCommand,
    super.ensureIgnored,
  });
}

/// Mock for [DoMergeCommand]
class MockDoMergeCommand extends MockDirCommand<void>
    implements DoMergeCommand {}
