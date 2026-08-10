# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run all checks (analyze + format + tests)
gg can commit

# Static analysis
gg check analyze

# Formatting check
gg check format

# Run all tests
dart test

# Run a single test file
dart test test/path/to/file_test.dart

# Commit (always use this, not git commit directly)
gg do commit -m "<message>"

# Push (always use this, not git push directly)
gg do push
```

## Architecture

Gg Multi is a multi-repository workspace management CLI for Dart/Flutter projects. It orchestrates actions (commit, push, publish, review) across all repos in a ticket workspace, resolving them in dependency order.

Since ticket 96 the implementation lives in four sub-packages; this repo is the **umbrella**: it wires the command tree, ships the `gg_multi` executable and re-exports the family's public API.

### The gg_multi tool family

| Package               | Role                                                                                                                                                      |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `gg_multi_core`       | The workspace model: ocean/tickets/trash layout, organization folders, url parsing, git platforms, ticket metadata & state, git snapshot helpers, the publish skip check, the `PublishPlanner` shared by `do review` and `do publish`, the shared `ProcessRunner`/`EditMessage` typedefs. |
| `gg_multi_workspace`  | Workspace management commands: `do add`, `do import ticket`, `do rm repo/ticket`, `do create ticket/graph`, `do upgrade ocean`, `do init workspace/claude`, `do code`, `do ls …`, `do exec cmd`. Depends on core. |
| `gg_multi_commit`     | Daily ticket flows: `can/did/do commit`, `push`, `review` — which also plans the release, asks the version increments and opens the pull requests of the repos that are actually published — and `do upgrade deps`. Depends on core. |
| `gg_multi_do_publish` | The publish orchestrator: `do publish` (+ `--merge-only`), `do configure-publish`, `can publish`, `EnsureInRegistry`, the registry checkers. Depends on core + commit. |

Each sub-package carries its own `CLAUDE.md` with the detailed behavior notes for its commands; consult those when working on the respective flows.

### What lives here

```
bin/gg_multi.dart                    – executable entry point
lib/gg_multi.dart                    – re-exports the four sub-packages + GgMulti
lib/src/gg_multi.dart                – GgMulti command (adds Can, Did, Do)
lib/src/commands/gg_multi_can.dart   – `can` group: commit, publish, push, review
lib/src/commands/gg_multi_did.dart   – `did` group: commit, push, review
lib/src/commands/gg_multi_do.dart    – `do` group: all workspace/flow/publish commands
lib/src/commands/do/upgrade.dart     – `do upgrade` group (deps → commit pkg, ocean → workspace pkg)
```

`do/upgrade.dart` stays here because its two subcommands live in two different sub-packages.

`test/integration/gg_multi_review_integration_test.dart` exercises the composed CLI across the packages (init workspace → add → commit → review), and `test/sample_folder/` holds its fixture packages.

## Maintain `<repo>/.gg/publish_config.json` — per repository

Every repository of a ticket carries `.gg/publish_config.json`. It is where you record what you changed, and gg reads it back: `gg do commit` proposes `nextCommitMessage`, `gg do review` proposes `versionIncrement` and uses `mergeMessage` as the pull-request title with `commits` as its description. Both files are gitignored and are removed before the merge into main.

```json
{
  "publishConfig": {
    "mergeMessage": "Add tracking",
    "versionIncrement": "major|minor|patch",
    "nextCommitMessage": {
      "firstLine": "Adapt message.json",
      "details": ["Detail 0", "Detail 1"]
    },
    "commits": [
      { "firstLine": "Adapt message.json", "details": ["Detail 0"] }
    ]
  }
}
```

Your obligations:

- **Keep `nextCommitMessage` current at all times.** After every change to a repository, rewrite its `firstLine` and `details` so they describe the work that is currently uncommitted. gg neither clears nor consumes the field — it is a standing proposal, not a buffer — so there must never be a moment where the default the next `gg do commit` shows is out of date.
- **`firstLine`: at most 60 characters**, imperative mood. gg rejects a longer one and re-opens the editor. `details`: one array entry per notable change.
- **`versionIncrement`** follows the strictest rule the change hits: breaking change → `major`, new feature → `minor`, bugfix/refactor/docs → `patch`. Never lower an increment already recorded within the ticket.
- **`mergeMessage`** is the pull-request title of that repository. It is initialized from the ticket description; sharpen it when the repository's change deserves a more precise title.
- **No cross-talk between packages.** A repository's file describes that repository's changes and nothing else. When one edit touches three repositories, write three different files with three different messages.
- **Never hand-edit `commits`** — `gg do commit` appends there — and never create `.gg/publish_state.json`, which belongs to the publish run.

## Code Standards

- **Line length**: 80 characters maximum.
- **Quotes**: Single quotes (`prefer_single_quotes`).
- **Trailing commas**: Required in all parameter/argument lists.
- **Return types**: Always declared explicitly.
- **Public API docs**: All public members require dartdoc comments.
- **Strict analyzer**: `strict-casts`, `strict-inference`, `strict-raw-types` enabled.
- **Test coverage**: 100% required. Every file under `lib/src/` must have a matching test at the same relative path under `test/`. Use `// coverage:ignore-line` and `// coverage:ignore-start/end` only when unavoidable.
- **Mocks**: Mock classes live in the same file as the class they mock, extending `MockDirCommand`.
- **Commits/pushes**: Always go through `gg do commit` / `gg do push`, never raw `git commit` / `git push`.
