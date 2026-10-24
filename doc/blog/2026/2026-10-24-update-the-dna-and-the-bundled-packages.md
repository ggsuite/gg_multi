<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Update the DNA and the bundled packages

## Motivation

- gg_multi bundles `gg_multi_commit`, `gg_multi_core`,
  `gg_multi_do_publish` and `gg_multi_workspace` into the multi-repo
  command line and re-exports them
- Its own change is small: the DNA files go to dna_ggsuite 1.0, and two
  bundled packages get lower bounds that match their latest releases
- The bundled packages change more; their changes reach the commands of
  gg_multi, so this post lists them under "Dependency updates"

## Strategy

- Raise the dev dependency `dna_ggsuite` from ^0.5.0 to ^1.0.0
- Raise `gg_multi_core` to ^4.11.1, `gg_multi_workspace` to ^4.16.0 and
  `pubspec_parse` to ^1.7.0
- Let helix regenerate the DNA files, committed as `#gg: generated DNA`
- Change nothing in `lib/`, `bin/` and `test/`

## Implementation 1: Ticket workflow

- New skill `/gg-review`: checks the diff of every repo against its scope,
  writes the blog posts, updates README.md and `index.jsonc`, then opens
  the pull requests and runs `/review-light`
- The blog posts move from the publish to the review phase; `/gg` and the
  `CLAUDE.md` block list `/gg-review`, `/gg-publish` checks for the post
- `/gg-commit` proposes one message per repo, in the repo's own terms;
  `ai-dev-guide.md` and `/gg-ticket` add scope, `index.jsonc` and
  requirements rules
- The code guide drops the package prefix on types and file names; new
  hooks keep the prompts in the project management repo

## Implementation 2: Lower bounds of the bundle

- `gg_multi_workspace` ^4.16.0: 4.15.0 copies the Claude Code hooks and
  their settings into tickets; 4.16.0 lets `do add` take `ssh://`,
  `git://` and `git+` URLs as well as `org/repo.git`
- `gg_multi_core` ^4.11.1 keeps a `.git` inside the repository names of
  SSH and `org/repo` targets
- `pubspec_parse` ^1.7.0 is used by an integration test only

## Dependency updates

- `dna_ggsuite` 1.0.0 brings `dna_gg` 1.0.0 (workflow skills, AI guide,
  hooks) and `dna_clean_code` 0.2.2 (code and test guides)
- `gg_multi_commit`: `do push`, `do review` and `do upgrade deps` no longer
  tighten the constraints. Inside a ticket the overrides point at the
  local checkouts, and pub crashes when it tightens against a sibling
  newer than the constraint
- `gg_multi_commit`: the upgrade commit of `do push` now reads
  `#gg: dart pub upgrade --major-versions`
- `gg_multi_do_publish`: `do publish` tightens explicitly, once the
  references point at the registry again; it is the only step of the
  ticket flow that tightens
- `gg_multi_commit`: `do commit` asks no message of a repo with nothing to
  commit and records none for it; the shared message is asked only when a
  repo without a proposal of its own needs one
- `gg_multi_workspace`: `do add --no-fetch` copies the ocean repos as they
  are; without it, each is first brought to `origin/<default branch>`
- `gg_multi_core` changes only its tests: they skip symbolic links where
  the system cannot create them
- Through `gg_one`: a `#gg: generated DNA` commit counts as bookkeeping, so
  `do publish` can skip a pass-through repo that only got a DNA update

## Open Points

- The lower bounds of the bundled packages still name releases without the
  changes above; the publish tightens them to the new releases
- `.claude/hooks/pm-prompts.json` names no project management repo yet, so
  the hooks keep no prompts; they need Node.js to run at all
- The repo has no `index.jsonc` yet, although the new guides ask for one
- `pubspec_overrides.yaml` points the dependencies at the sibling
  checkouts while the ticket is open; it goes when the references return
  to pub.dev
