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

### Entry Point & Command Groups

```
bin/gg_multi.dart
  └─ GgMulti (lib/src/gg_multi.dart)
       ├─ Can   – validate before acting (can commit, can push, can publish, can review)
       ├─ Do    – execute across all repos (do commit, do push, do review, do add, do checkout, do claude, …)
       ├─ Did   – report what happened (did commit, did push)
       └─ Ls    – list workspace contents (repos, organizations, deps)
```

Each command group lives in `lib/src/commands/gg_multi_can.dart`, `gg_multi_do.dart`, `gg_multi_did.dart`, and `ls.dart`. Subcommands are in `lib/src/commands/<group>/<name>.dart`.

### Workspace Hierarchy

The tool manages two levels of workspace:

- **Master workspace** (`<root>/.master/`) — contains all registered repositories and organizations.
- **Ticket workspace** (`<root>/tickets/<ticket-name>/`) — contains clones of repos scoped to a ticket.

`WorkspaceUtils.detectTicketPath()` (in `lib/src/backend/workspace_utils.dart`) navigates up the directory tree to locate which context the CLI is running in.

### Backend Modules (`lib/src/backend/`)

| Module | Role |
|--------|------|
| `workspace_utils.dart` | Detects master/ticket paths from any working directory |
| `git_handler.dart` | Clone & create-branch (workspace-specific); generic git ops (fetch, checkout, show-file, remote-branches) live in `gg_git` |
| `git_snapshot.dart` | Shared rollback helpers for `do review` + `do publish`: `runGit` (throw-on-non-zero unless `allowFailure`) and `captureUncommitted` (stash tracked+staged/unstaged+untracked into a dangling commit, tree left unchanged). One copy so the two rollback paths cannot drift. |
| `ticket_json.dart` | Reads/writes/parses the per-repo `.gg/.ticket.json` ticket marker |
| `git_platform.dart` | Git-platform abstraction. `GitHubPlatform.fetchOrgRepos` lists an org's repos via the **GitHub CLI** (`gh repo list --json name,sshUrl,url`), `AzureDevOpsPlatform` via `az repos list`. Using the CLIs reuses the caller's existing auth so **private** orgs work (an unauthenticated REST call only ever sees public repos); cloning then uses each repo's ssh url. Both require the respective CLI for org-add and emit an install hint otherwise. |
| `list_backend.dart` | Lists repos/orgs/deps with metadata |
| `add_repository_helper.dart` | Logic for adding repos to a workspace. Accepts a repo URL/`owner/repo`/name, or an **org** URL (`github.com/<org>` or the browser form `github.com/orgs/<org>`) to clone every repo of that org. |
| `pub_dev_checker.dart` | Checks published versions on pub.dev |
| `constants.dart` | Directory name constants (`.master`, `tickets`) |

### `do claude` Command

`DoClaudeCommand` (in `lib/src/commands/do/claude.dart`) generates an aggregated `CLAUDE.md` at the ticket-workspace root. It:

1. Detects the ticket path via `WorkspaceUtils.detectTicketPath()`.
2. Resolves repos in dependency order with `SortedProcessingList` (from `gg_local_package_dependencies`).
3. Reads each repo's `CLAUDE.md` (throws with a helpful message if one is missing — the user must run `/init` in that repo first).
4. Writes a single `<ticket-dir>/CLAUDE.md` combining workspace overview, commands, per-repo architecture sections, and code standards.

### `.gg/.ticket.json` ticket marker

`do add` writes a pretty-printed `.gg/.ticket.json` into **every** repo of a ticket (overwriting on each `add` so it stays current). It holds `issue_id`, `description` and the full list of repos with their git URLs, and is whitelisted in each repo's `.gitignore` (`!.gg/.ticket.json`) so it travels with the feature branch. `gg_one do merge` removes it again before merging so it never reaches `main`. Logic lives in `lib/src/backend/ticket_json.dart`.

### `do checkout` Command

`DoCheckoutCommand` (in `lib/src/commands/do/checkout.dart`) reproduces a whole ticket from a single `.gg/.ticket.json` marker (e.g. one another person created) — its repositories on their feature branch, not a byte-identical clone of a fresh `do add` (no git-hook/`.gitattributes` reinstall). `gg do checkout <X>` resolves `<X>` in three modes:

1. **Inside a `.master` repo** → `<X>` is the ticket name, read from that repo's `origin/<X>` branch.
2. **`<X>` is a known `.master` repo** → fetch it and pick a ticket branch interactively.
3. **Otherwise** → `<X>` is a ticket name, searched across all `.master` repos.

Once found, it recreates the ticket folder + root `.ticket`, clones any missing repos from their URLs, copies each into the ticket, checks out the existing feature branch, and installs deps.

### `do review` Command

`DoReviewCommand` (in `lib/src/commands/do/review.dart`) prepares every ticket repo for review: merge `origin/main` into the feature branch (re-verifying with `gg can commit` when the merge moved HEAD), run `can review`, then per repo localize refs to git feature branches, refresh dependencies, force-commit, integrate the remote feature branch (`pull --rebase`, never force-push) and push.

Before touching anything it snapshots every repo (branch — the commit hash when HEAD is detached, HEAD, `status --porcelain`, plus a `git stash push --include-untracked` commit that captures tracked changes, the staged/unstaged split *and* untracked files, immediately re-applied so the working tree is unchanged). **If any step fails, the changed repos are rolled back to that snapshot** (`merge --abort` → `rebase --abort` → `checkout <branch>` if needed → `reset --hard <head>` → `stash apply --index`); unchanged repos are skipped. Already-pushed repos are **left as-is, not reset** — resetting local behind the pushed commit would desync them and make the next run rebase onto it; they are reported instead, and the next `do review` run integrates those remote commits via the `pull --rebase` step. If the restore itself fails, a manual-recovery hint with the checkout/reset commands *and the stash hash* is logged and the original review error stays the primary one.

### `do configure-publish` Command

`DoConfigurePublishCommand` (in `lib/src/commands/do/configure_publish.dart`) interactively builds the publish configuration for the current ticket and writes it to `<ticket>/.gg/.gg-publish.json`. It walks the repos in dependency order and asks, per repo, for the version increment (via gg_one's `VersionSelector`, with an injectable `InteractAdapter` for tests) and the merge message, plus a single `delete_ticket` choice. The merge-message default (which pre-fills every repo's prompt and is the fallback for an empty entry) is `-m`/`--message` if given, else the ticket description, else `Publish <repo>` — so a merge message is never empty and `-m` wins over the ticket description. `configFileFor(ticketDir)` returns the canonical `.gg/.gg-publish.json` path used everywhere. `do publish` calls this automatically when no config is supplied, so every interactive decision is made **up front** before the long, unattended publish begins.

### `do publish` Command

`DoPublishCommand` (in `lib/src/commands/do/publish.dart`) publishes all ticket repos in dependency order. It first **resolves the publish configuration** (see below), then — unless resuming — runs `do review` + `can publish`, then per repo unlocalize refs, restore `publish_to`, propagate published dependency versions, refresh deps, commit, push and delegate to gg_one's `gg do publish` (version bump → registry publish → merge to main, by default via auto-merge squash pull request → tag → push).

**Config resolution** (`_resolvePublishConfig`, precedence): `--continue` reuses the runtime `.gg/.gg-publish.json` (errors if absent) → an explicit `--config <path>` → the runtime `.gg/.gg-publish.json` → the legacy `<ticket>/.gg-publish.json` → an interactive `do configure-publish`. `--reconfigure` skips the two implicit files so the user is asked again. `--config`/legacy files are only *read*; the mutable runtime copy at `.gg/.gg-publish.json` is what receives progress and is deleted on full success (a user's `--config` file is never touched). Merge message + version increment per repo come from `PublishConfig.forRepo` (per-repo override → top-level default). `-m`/`--message` is forwarded to `do configure-publish` as the default merge message and therefore only matters on the interactive/`--reconfigure` path — it is ignored once a config exists or is supplied via `--config`.

**Progress + `--continue`**: after each repo, its status is written into the ticket-level `.gg/.gg-publish.json` (`published` on success, `failed` on failure). `--continue` skips repos already marked `published` (still capturing their version so dependents resolve) and resumes the rest, forwarding `resume: true` to gg_one's `do publish` — which resumes at the first open step of its own repo-level `<repo>/.gg/.gg-publish.json` (`done_steps`; see the gg_one CLAUDE.md). Two levels, one file family: ticket file = repo status, repo file = step progress. `_publishRepo` also ensures `.gg/.gg-publish.json` is in each repo's `.gitignore` (via gg_one's `EnsurePublishConfigIgnored`, `commit: false` — the entry rides along the pre-publish force-commit). Review + `can publish` are skipped on `--continue` **when irreversible progress exists**: some repo is `published`, or some repo's own step file records `done_steps` (the first repo may fail after its registry publish/merge with only `failed` in the ticket file — re-reviewing that partially merged ticket would throw "nothing to merge" and block the resume). A `--continue` after a pure review failure (no progress anywhere) still reviews; gg_one re-checks `did commit` per repo on resume. An explicit `--config` refuses to clobber a runtime file that still holds progress (same guard as the implicit path; combine with `--reconfigure` to discard), and `do configure-publish` refuses likewise. `--reconfigure` discards the ticket file **and** the repo-level step files.

Each repo is snapshotted before its publish (branch — the commit hash when HEAD is detached, HEAD, `status`/stash via the same `stash push --include-untracked` capture as `do review`, package version, `main`/`master` position local + remote, the feature branch's remote head, tags). **When the publish of a repo fails, only that repo is restored — previously published repos stay published.** The restore is two-mode, because gg_one's flow publishes to the registry *before* merging and pub.dev/npm cannot be unpublished:

- **Full restore** — only when provably nothing irreversible happened: end merges/rebases, back to the feature branch, `reset --hard`, restore the local main position, delete tags the run created, re-apply stashed changes with `--index`.
- **Cleanup restore** — otherwise, **keep all commits** so a `--continue` resumes via gg_one's step file (`<repo>/.gg/.gg-publish.json`, `done_steps`), which is kept on this path because its markers stay real. Cleanup is entered on any of: a *committed* version bump (a version change still uncommitted in the working tree is a half-written bump and does **not** count — it is recoverable, so it full-restores), `origin/main` having moved, or the feature branch already pushed. Remote comparisons only conclude "moved" from a concrete differing hash — an unreachable `git ls-remote` (often the very cause of the failure) is treated as *unknown*, never as "already released". The **full restore** additionally deletes the repo-level step file: it is gitignored and survives `reset --hard`, but its markers would describe commits the rollback just removed.

The publish failure always stays the primary error; restore problems are logged with a manual-recovery hint that includes the checkout/reset commands and the stash hash.

## Code Standards

- **Line length**: 80 characters maximum.
- **Quotes**: Single quotes (`prefer_single_quotes`).
- **Trailing commas**: Required in all parameter/argument lists.
- **Return types**: Always declared explicitly.
- **Public API docs**: All public members require dartdoc comments.
- **Strict analyzer**: `strict-casts`, `strict-inference`, `strict-raw-types` enabled.
- **Test coverage**: 100% required. Every file under `lib/src/` must have a matching test at the same relative path under `test/`. Use `// coverage:ignore-line` and `// coverage:ignore-start/end` only when unavoidable.
- **Mocks**: Each command class has a corresponding `Mock<ClassName>` in the same file, extending `MockDirCommand`.
- **Commits/pushes**: Always go through `gg do commit` / `gg do push`, never raw `git commit` / `git push`.
