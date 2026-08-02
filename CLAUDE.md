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
       ├─ Do    – execute across all repos (do commit, do push, do publish, do merge, do review, do add, do checkout, do claude, …)
       ├─ Did   – report what happened (did commit, did push)
       └─ Ls    – list workspace contents (repos, organizations, deps)
```

Each command group lives in `lib/src/commands/gg_multi_can.dart`, `gg_multi_do.dart`, `gg_multi_did.dart`, and `ls.dart`. Subcommands are in `lib/src/commands/<group>/<name>.dart`.

### Workspace Hierarchy

The tool manages three folders at the workspace root:

- **Master workspace** (`<root>/.master/`) — contains all registered repositories and organizations.
- **Ticket workspace** (`<root>/tickets/<ticket-name>/`) — contains clones of repos scoped to a ticket.
- **Trash** (`<root>/.trash/<ticket-name>/`) — the sibling of `.master` that holds what gg removed from a ticket. `Trash` (in `lib/src/backend/trash.dart`) owns it: `do create ticket` creates the per-ticket folder up front, and `do publish` moves the published repos (keeping their `<org>/<repo>` path) plus the `<ticket>.code-workspace` file there instead of deleting them, so an overlooked local change stays recoverable. A target name that is already taken gets a ` (2)`, ` (3)`, … suffix — trash content is never overwritten. `moveFromTicket` renames and falls back to copy + delete when trash and ticket live on different volumes. Emptying the trash is the user's job; gg never does.

`WorkspaceUtils.detectTicketPath()` (in `lib/src/backend/workspace_utils.dart`) navigates up the directory tree to locate which context the CLI is running in.

### Organization folders

Both workspaces group their repositories by the organization of the repo's git URL:

```
<root>/.master/<org>/<repo>          e.g. .master/ggsuite/gg_multi
<root>/tickets/<ticket>/<org>/<repo> e.g. tickets/33_org_folders/ggsuite/gg_multi
```

Without the org level, two organizations owning a repo of the same name would collide in one flat folder. The ticket mirrors the master layout, so a repo has the same relative path in both.

`RepoFolderResolver` (in `lib/src/backend/repo_folder_resolver.dart`) owns the layout:

| Member                                          | Role                                                                                                                                                                                                                                                                                                                                                             |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `destination(workspacePath, repoUrl, repoName)` | Where a repo is cloned to. `organizationOf(url)` needs a repo in the URL — `https://host/repo.git` has a single segment and that is the repo, so such a repo stays flat. On **Azure DevOps it returns the project**, not the account Azure calls the organization: repo names are unique per project, so `dev.azure.com/mhk-carat/ds_cdm` groups under `ds_cdm`. |
| `repoDirs(workspacePath)`                       | All repos of a workspace. A direct child is an _organization folder_ when it is no repo itself (`isRepoDir`: `.git`, `pubspec.yaml` or `package.json`) but holds at least one — so a repo is never descended into and its inner packages (`example/`, fixtures) stay invisible. Hidden folders are skipped.                                                      |
| `resolve(workspacePath, repoName)`              | Finds a repo anywhere in the workspace: exact path, then folder name, then manifest package name. Never returns an organization folder.                                                                                                                                                                                                                          |
| `relativePath(workspacePath, repoDir)`          | `<org>/<repo>` — used for the ticket copy destination and the `.code-workspace` entries (written with forward slashes).                                                                                                                                                                                                                                          |
| `removeEmptyOrgFolder(...)`                     | Drops an organization folder that lost its last repo.                                                                                                                                                                                                                                                                                                            |

Repositories that still sit directly in the workspace keep working everywhere; `migrateToOrgFolders` (below) moves them.

`UrlParser` is what makes the folder correct, so it covers every shape the platforms hand out — for Azure that is `dev.azure.com/<org>/<project>`, `.../<org>/<project>/_git/<repo>` (what `az repos list` reports), the `<org>/_git/<repo>` shortcut where project and repo share a name, `v3/<org>/<project>/<repo>` on the ssh host (including the unparsable-as-Uri `https://ssh.dev.azure.com:v3/…` form gg builds itself), and the legacy `<org>.visualstudio.com/<project>/_git/<repo>`. `_git` is Azure's separator between project and repository, so what follows it is never the project.

### Ambiguous plain repo names

`gg do add <repoName>` names no organization, and the same name can exist in several of them. `organizationsOwningRepo` therefore asks every organization from `.organizations` whether it owns that repo (`GitHandler.remoteExists` → `git ls-remote`, in parallel, result kept in registration order). With more than one owner, `selectOrganization` — the injectable prompt, `defaultSelectOrganization` by default — offers `<org>/<repo>` via interact's `Select`, the same cursor-key prompt `do configure-publish` uses for the version increment. One owner clones straight away, none falls back to the old behaviour (guess `github.com/<name>/<name>`, then try each organization in turn).

No remote is asked when fewer than two organizations are known or when the repo is already in the workspace, so the common case stays offline. Headless runs fail fast through gg_one's `throwWhenNotATerminal` instead of hanging on the prompt.

The two graph builders gg_multi delegates to know the layout as well: `Graph`/`SortedProcessingList` (gg_local_package_dependencies) descend into grouping folders, and `MultiLanguageGraph` (gg_localize_refs) resolves the workspace root one level up when the repo sits in an organization folder, so path refs across organizations are localized. Both changes are backwards compatible with a flat workspace.

### Maintenance: migrating an old workspace

`migrateToOrgFolders` (in `lib/src/backend/workspace_migration.dart`) recognizes a workspace created before the org folders existed — its repositories lie flat in it — and renames each into `<workspace>/<org>/<repo>`, with the org read from the repo's git remote. It returns the moved repo names, is a no-op once everything is nested, and skips (with a message) a repo whose organization is unknown or whose target folder is taken, so a half-migrated workspace never loses a repo.

It runs at the start of `do add` (master **and** ticket) and of `do checkout` (master only, the ticket it builds is fresh). Moving a ticket repo invalidates the relative path refs between the ticket repos — `do add` repairs them in its closing re-localization pass, which is why the ticket is only migrated there.

### Backend Modules (`lib/src/backend/`)

| Module                       | Role                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `workspace_utils.dart`       | Detects master/ticket paths from any working directory                                                                                                                                                                                                                                                                                                                                                                                                |
| `git_handler.dart`           | Clone & create-branch (workspace-specific); generic git ops (fetch, checkout, show-file, remote-branches) live in `gg_git`                                                                                                                                                                                                                                                                                                                            |
| `git_snapshot.dart`          | Shared rollback helpers for `do review` + `do publish`: `runGit` (throw-on-non-zero unless `allowFailure`) and `captureUncommitted` (stash tracked+staged/unstaged+untracked into a dangling commit, tree left unchanged). One copy so the two rollback paths cannot drift.                                                                                                                                                                           |
| `ticket_json.dart`           | Reads/writes/parses `<ticket>/ticket.json` — local only, never committed                                                                                                                                                                                                                                                                                                                                                                                  |
| `git_platform.dart`          | Git-platform abstraction. `GitHubPlatform.fetchOrgRepos` lists an org's repos via the **GitHub CLI** (`gh repo list --json name,sshUrl,url`), `AzureDevOpsPlatform` via `az repos list`. Using the CLIs reuses the caller's existing auth so **private** orgs work (an unauthenticated REST call only ever sees public repos); cloning then uses each repo's ssh url. Both require the respective CLI for org-add and emit an install hint otherwise. |
| `list_backend.dart`          | Lists repos/orgs/deps with metadata                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `add_repository_helper.dart` | Logic for adding repos to a workspace. Accepts a repo URL/`owner/repo`/name, or an **org** URL (`github.com/<org>` or the browser form `github.com/orgs/<org>`) to clone every repo of that org. Clones into `<workspace>/<org>/<repo>`; an existing copy is looked up across the whole workspace, so a repo that is still flat is not cloned a second time.                                                                                          |
| `repo_folder_resolver.dart`  | The `<workspace>/<org>/<repo>` layout: listing, resolving, destination — see _Organization folders_ below                                                                                                                                                                                                                                                                                                                                             |
| `workspace_migration.dart`   | Moves the repos of an old flat workspace into their organization folders — see _Maintenance_ below                                                                                                                                                                                                                                                                                                                                                    |
| `pub_dev_checker.dart`       | Checks published versions on pub.dev                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `legacy_git_hooks.dart`      | Deletes the obsolete `gg`-generated `pre-push` hook (and its `.gg/verify_push.dart`) from a repo. `gg` no longer installs hooks — see _No git hooks_ below.                                                                                                                                                                                                                                                                                           |
| `constants.dart`             | Directory name constants (`.master`, `tickets`, `.trash`)                                                                                                                                                                                                                                                                                                                                                                                             |
| `trash.dart`                 | `<root>/.trash/<ticket>` — where removed repos and workspace files go instead of being deleted                                                                                                                                                                                                                                                                                                                                                        |
| `dependency_overrides.dart`  | Removes packages from the `pubspec_overrides.yaml` of the repos that stay in a ticket                                                                                                                                                                                                                                                                                                                                                                 |

### `do claude` Command

`DoClaudeCommand` (in `lib/src/commands/do/claude.dart`) generates an aggregated `CLAUDE.md` at the ticket-workspace root. It:

1. Detects the ticket path via `WorkspaceUtils.detectTicketPath()`.
2. Resolves repos in dependency order with `SortedProcessingList` (from `gg_local_package_dependencies`).
3. Reads each repo's `CLAUDE.md` (throws with a helpful message if one is missing — the user must run `/init` in that repo first).
4. Writes a single `<ticket-dir>/CLAUDE.md` combining workspace overview, commands, per-repo architecture sections, and code standards.

### `ticket.json` — local, never uploaded

`do add` writes a pretty-printed `ticket.json` into the **ticket folder** (`<root>/tickets/<ticket>/ticket.json`), overwriting it on each `add` so it stays current. It holds `issue_id`, `description` and the full list of repos with their git URLs. Logic lives in `lib/src/backend/ticket_json.dart` (`writeTicketJson`, `readTicketJson`, `buildTicketJson`).

It sits **next to** the repositories, never inside one, so git never sees it and the ticket description cannot reach a remote — a private ticket stays private. Sharing a ticket is therefore an explicit act: hand the file over, or put it behind a URL, and the recipient runs `gg do checkout <path|url>`.

**Legacy**: gg used to write the marker into every repo's `.gg/` folder, force-stage it (`git add -f`) and commit it, so it travelled with the feature branch; the `.gitignore` of each repo whitelisted it. That is gone. `.gg/ticket.json` and `.gg/.ticket.json` are now plainly gitignored, and `copyDirectory` skips both names. gg_one still strips a leftover marker from branches an older gg pushed: `do publish` drops it before the version bump and registry upload (so it never ships to pub.dev/npm) and its merge step drops it before merging (so it never reaches `main`; gg_one has no `do merge` command anymore — the merge lives in `MergeFlow`, driven by `do publish`). `do checkout` can still read such a marker (see below), which is the only reason the legacy paths are still known.

### No git hooks

`gg` does **not** install git hooks. An earlier version made `do add` write a `pre-push` hook that ran `dart run .gg/verify_push.dart` and refused a push to `main`/`master` unless `gg did commit` reported a clean tree. Pushing to `main` is blocked by the remote and every change lands through a pull request, so the hook only duplicated a rule the server already enforces.

Because the hook lives in the untracked `.git/hooks/`, it survives in every checkout that ever ran an older `do add`. `removeLegacyGitHooks` (in `lib/src/backend/legacy_git_hooks.dart`) therefore deletes it — plus the `.gg/verify_push.dart` it invoked — from every ticket repo on each `do add`. A `pre-push` hook that does _not_ reference `.gg/verify_push.dart` is the user's own and is left alone. Both files are untracked (`.git/hooks` is never tracked, `.gg/verify_push.dart` falls under the `.gg/*` gitignore rule), so the cleanup never dirties the working tree and needs no commit.

### `do create ticket` Command

`TicketCommand` (in `lib/src/commands/do/create/ticket.dart`) creates `tickets/<issue-id>/` with the root `.ticket` file and the VS Code workspace `<issue-id>.code-workspace`, so `do code <ticket>` opens something before the first `do add`. It also creates the ticket's trash folder `<root>/.trash/<issue-id>/`, so the place a later `do publish` moves the repos to exists from the start. A ticket without repos gets the ticket folder itself (`{"path": "."}`) as its single entry — `writeCodeWorkspaceFile` never writes an empty folder list, because VS Code then shows a window with nothing in it and no way to add the first folder. `do add` rewrites the file with one `<org>/<repo>` entry per repository.

### `do checkout` Command

`DoCheckoutCommand` (in `lib/src/commands/do/checkout.dart`) reproduces a whole ticket from a `ticket.json` (e.g. one another person created) — its repositories on their feature branch, not a byte-identical clone of a fresh `do add` (no `.gitattributes` reinstall). `gg do checkout <X>` resolves `<X>` in this order:

1. **`<X>` is an `http(s)` URL** → the `ticket.json` is downloaded from it (`package:http`, injectable as `TicketJsonFetcher` so tests need no network).
2. **`<X>` is a path** → the file itself is read; a **directory** is taken as a ticket folder and its `ticket.json` is read. A path that exists but holds no `ticket.json` fails with that message instead of falling through — an argument carrying a separator is meant as a path, not as a name.
3. _(legacy)_ **`<X>` is a name** → the marker older gg versions committed is read from `origin/<X>`: inside a `.master` repo `<X>` is the ticket name (the repo is found one _or_ two levels below the master workspace, so `.master/<org>/<repo>` counts); a known `.master` repo means "fetch it and pick a ticket branch interactively"; otherwise `<X>` is searched across all `.master` repos. Both `.gg/.ticket.json` and `.gg/ticket.json` are tried, and a deprecation hint points at the path/URL form.

Once the `ticket.json` is in hand, it recreates the ticket folder + root `.ticket` + a local `ticket.json`, clones any missing repos from their URLs (into `<master>/<org>/<repo>`), copies each into the matching `<ticket>/<org>/<repo>`, checks out the existing feature branch, and installs deps.

### `do rm` Command

`RemoveCommand` (in `lib/src/commands/do/rm.dart`) deletes a single repo folder. From the workspace root it deletes the master copy only when no ticket still references the repo, otherwise it lists the offending tickets. From inside a ticket it deletes that ticket's copy only — master and sibling tickets are never touched. The context is resolved from the working directory with `WorkspaceUtils.detectTicketPath` / `defaultGgMultiWorkspacePath`, so the command works from any sub-folder (e.g. inside one of the ticket's repos), not just from the ticket or workspace root. The repo is addressed by its plain name and resolved inside its organization folder; an organization folder that loses its last repo is removed with it.

**`ticket.json` upkeep**: after a ticket-scoped deletion the ticket's `ticket.json` is rewritten without the deleted repo (`issue_id`/`description` come from the root `.ticket` via `buildTicketJson`, same as `do add`). Only a ticket that already has one is touched, so a ticket that never saw a `do add` does not gain one.

**`pubspec_overrides.yaml` upkeep**: gg*localize_refs points the overrides of every ticket repo at its sibling checkouts (`path: ../<repo>`). A ticket-scoped `rm` therefore removes the deleted repo from the `pubspec_overrides.yaml` of every remaining repo (`removeDependencyOverrides`, `lib/src/backend/dependency_overrides.dart`) — otherwise the dangling path breaks `dart pub get` in all of them. A file whose only entries were the removed ones is deleted rather than left as an empty (invalid) `dependency_overrides`. The repo is matched under every name it can appear as: folder name, the name it was addressed with, and its package name/aliases from the dependency graph — collected \_before* the folder is gone. An unparsable file is the user's and is left untouched.

**Dependency-chain guard**: a ticket-scoped `rm` refuses to delete a repo that _links_ two other repos of the ticket — one that has both a dependent and a dependency inside the ticket (`a → b → c`, removing `b`). The offending edges are listed and an exception is thrown, so the chain cannot be torn apart; remove the dependents first. Repos at either end of a chain (no dependents, or no dependencies within the ticket) and folders that are no package at all delete without complaint. The graph comes from `SortedProcessingList` (injectable for tests) over the ticket folder.

### `do maintain` Command

`MaintainCommand` (in `lib/src/commands/do/maintain.dart`) groups the maintenance tasks that run across the repos of a ticket; its subcommands live in `lib/src/commands/do/maintain/`. It has no `run()` of its own, so a bare `gg do maintain` prints the tasks available — the same shape as `do create`. Today that is `exec` (formerly the top-level `do execute`).

`DoExecuteCommand` (in `lib/src/commands/do/maintain/exec.dart`) runs one shell command in every ticket repo in dependency order (`SortedProcessingList`), logging each repo name before its output. It collects the repos whose command exited non-zero instead of stopping at the first one, then lists them and throws — so a `gg do maintain exec dart pub get` reports _every_ broken repo in one pass. The injectable `ProcessRunner` runs with `runInShell: true`; the `-l`/`--line-length` option exists only so an argument like `dart fmt -l 120` does not fail arg parsing before it reaches the tool.

### `do commit` Command

`DoCommitCommand` (in `lib/src/commands/do/commit.dart`) commits every ticket repo in dependency order with one shared message, delegating to gg_one's `gg do commit` per repo.

**Message resolution**: an explicit `-m`/`--message` (or the `message` argument of `exec`) is used as-is. Without one, the ticket description — read from the root `.ticket` file via `readTicketDescription` (`lib/src/backend/ticket_json.dart`) — seeds the interactive editor `do configure-publish` uses for merge messages (`interact`'s `Input`, guarded by gg_one's `throwWhenNotATerminal` so headless runs fail fast instead of hanging). The edited text wins; clearing it falls back to the description. When nothing resolves (no `-m`, no description, empty edit) `null` is forwarded and gg_one decides — it only demands a message from repos that actually have something to commit, so an already-committed ticket still passes. The prompt is skipped for an empty ticket (no repos) and whenever a message was passed, so `gg_multi do commit -m …` stays non-interactive.

`readTicketDescription` is the single reader of the root `.ticket` description, shared by `do commit`, `do configure-publish` and `buildTicketJson`.

### `do review` Command

`DoReviewCommand` (in `lib/src/commands/do/review.dart`) prepares every ticket repo for review: fetch + merge `origin/main` into the feature branch (`git fetch origin main` first, so a main that moved on the remote is really merged; re-verifying with `gg can commit` when the merge moved HEAD), run `can review`, then per repo localize refs to git feature branches, refresh dependencies, force-commit, integrate the remote feature branch (`pull --rebase`, never force-push) and push. Finally it **opens a pull request per repo and prints its url**.

**The pull requests** (`_createPullRequests`, gg_one's `CreatePullRequest`): a ticket becomes reviewable while it is still being worked on, not only when it is published, so the pull request is opened as soon as the branches are on the remote. It carries **no auto-merge flag** — that is `do publish`'s job (it reuses the same pull request and sets auto-merge once the release is complete); auto-merging a ticket that is under review would put unreleased work on main. The title is the ticket description (`readTicketDescription`, the same default `do commit` uses), else the ticket name; an already open pull request keeps the title it has, because re-running the review must never duplicate or rewrite it. The step runs **after** the rollback block: everything the review does has succeeded by then and the branches are pushed either way, so a provider that cannot be reached (no GitHub/Azure DevOps remote, missing `gh`/`az`) is reported per repo in yellow and the remaining repos are still processed — it never fails the review or triggers a rollback. The urls are collected first and printed afterwards, because `GgStatusPrinter` overwrites its own line while it runs.

**Integrating the remote feature branch** (`_integrateRemoteBranch`): a branch that does not exist on the remote yet, or whose remote tip is already contained in the local history, needs nothing. Otherwise the local branch is rebased onto it — _unless_ the remote branch is **obsolete**, in which case the rebase would replay the whole main branch onto a tip that predates it and die in conflicts on long-merged, foreign work. That is what happens when a ticket branch was squash-merged into `main`, the provider did not delete it, and the ticket is used again (`do add`/`do checkout`, or a second `gg do merge`): the branch is recreated locally _from the current main_ and therefore carries every commit merged since. `_remoteBranchIsObsolete` says yes only when `origin/main` is contained in `HEAD` **and** every commit the remote branch holds on top of `HEAD` is either already on `origin/main` by content (`git cherry` compares patch ids, so a squash merge is recognized) or one of gg's own bookkeeping commits (`#gg: …` / a legacy subject). A single real, unmerged commit makes it fall back to the rebase, so no work is ever lost. An obsolete branch is overwritten with `git push --force-with-lease=<branch>:<remote head>` — the lease pins the hash the analysis was made from, so a branch somebody moved in between is rejected instead of overwritten; a rejected push fails the review with a hint to delete the leftover branch manually.

Before touching anything it snapshots every repo (branch — the commit hash when HEAD is detached, HEAD, `status --porcelain`, plus a `git stash push --include-untracked` commit that captures tracked changes, the staged/unstaged split _and_ untracked files, immediately re-applied so the working tree is unchanged). **If any step fails, the changed repos are rolled back to that snapshot** (`merge --abort` → `rebase --abort` → `checkout <branch>` if needed → `reset --hard <head>` → `stash apply --index`); unchanged repos are skipped. Already-pushed repos are **left as-is, not reset** — resetting local behind the pushed commit would desync them and make the next run rebase onto it; they are reported instead, and the next `do review` run integrates those remote commits via the `pull --rebase` step. If the restore itself fails, a manual-recovery hint with the checkout/reset commands _and the stash hash_ is logged and the original review error stays the primary one.

**Merge conflicts are not a rollback case.** When merging `origin/main` leaves conflicts (`git diff --name-only --diff-filter=U` is non-empty), the review logs `Please resolve merge conflicts:`, the conflicting files, and `After merging execute: gg do commit -m"Merge main" --no-log`, then throws `MergeConflictException`. That exception bypasses the rollback (and is rethrown unwrapped by `do publish`), so the half-merged working tree survives for the user to resolve. Every other merge failure keeps the old behaviour: wrapped error + full rollback.

### `do configure-publish` Command

`DoConfigurePublishCommand` (in `lib/src/commands/do/configure_publish.dart`) interactively builds the publish configuration for the current ticket and writes it to `<ticket>/.gg/.gg-publish.json`. It walks the repos in dependency order and asks, per repo, for the version increment (via gg*one's `VersionSelector`, with an injectable `InteractAdapter` for tests) and the merge message. There is no `delete_ticket` question — the ticket cleanup is not optional any more (see \_Trashing the ticket* below), so nothing about it is asked or written.

**Increment-preview baseline**: the `Patch (x -> y)` options are calculated from the version the repo last **published to its registry** (gg*publish's `PublishedVersion` — pub.dev/npm, git version tag for private and manifest-less repos, 0.0.0 when nothing resolves), \_not* from the manifest. `gg do publish` bumps from the published version too, so the two must agree: only `main` carries the released version, so a feature branch's `pubspec.yaml` normally lags behind the registry (e.g. manifest 7.0.1 while pub.dev is at 7.1.2) and a manifest baseline would offer a version the publish never creates. The merge-message default (which pre-fills every repo's prompt and is the fallback for an empty entry) is `-m`/`--message` if given, else the ticket description, else `Publish <repo>` — so a merge message is never empty and `-m` wins over the ticket description. `configFileFor(ticketDir)` returns the canonical `.gg/.gg-publish.json` path used everywhere. `do publish` calls this automatically when no config is supplied, so every interactive decision is made **up front** before the long, unattended publish begins.

### `do publish` Command

`DoPublishCommand` (in `lib/src/commands/do/publish.dart`) publishes all ticket repos in dependency order. It first **resolves the publish configuration** (see below), then — unless resuming — runs `do review` + `can publish`, then per repo unlocalize refs, restore `publish_to`, propagate published dependency versions, refresh deps, commit, push and delegate to gg_one's `gg do publish` (version bump → registry publish → merge to main, by default via auto-merge squash pull request → tag → push). The pull request `do review` opened is **reused** — publishing is where the auto-merge flag is finally set.

**First-publish gate** (`EnsureInRegistry`, `lib/src/backend/ensure_in_registry.dart`): right before a repo's `gg do publish` — after unlocalize + restore `publish_to`, so the folder is publishable as-is — the gate checks (via gg_publish's `IsInRegistry`) that at least one version of the package is on its registry (pub.dev / npm). A package that was never published has to be published manually by the user first (authentication, access rights, package creation): the gate prints the shell commands in blue (`cd <repo>` + `dart pub publish` / `pnpm publish --no-git-checks [--access public]`), waits for ⏎ on stdin (`q` aborts, headless runs fail fast via `throwWhenNotATerminal`), re-checks the registry and continues. gg then bumps and uploads the next version automatically. Repos without a public registry are skipped.

**Skipping unchanged repos** (`PublishSkipCheck`, `lib/src/backend/publish_skip_check.dart`): many repos are only part of a ticket because they sit _between_ two changed packages in the dependency chain. Before each repo publishes, the check decides whether a release is needed at all: (1) does any dependency published earlier in the run now carry a version **outside the constraint this repo publishes** (original constraints come from the gg*localize_refs backups — `.gg/.gg_localize_refs_backup.json`, root `.gg_localize_refs_backup.json` — with the manifest as fallback; for >= 1.0.0 that is a whole-number/major bump, for 0.x the minor position is the breaking one, so caret semantics stay correct)? Only \_regular* dependencies count — dev deps of a published package are invisible to its consumers. (2) If not: does the repo carry **manual changes** — a dirty working tree, or any commit on top of the **last release** (merge commits excluded) whose subject was not generated by gg itself? The baseline is the last tag reachable from HEAD (`git describe --tags --abbrev=0`), because a tag is what marks a release: `gg do merge` puts a ticket on the main branch _without_ tagging it, so a main-branch baseline would report a repo full of unreleased work as unchanged and skip its next release. Only a repo that carries no tag at all — nothing was ever released — falls back to `origin/main` (then `origin/master`, local `main`, `master`). Every message gg generates starts with **`#gg: `** (e.g. `#gg: changed references to path`/`…to git`/`…to pub.dev`), so subjects carrying that prefix are treated as not user generated; the exact pre-prefix bookkeeping subjects (`gg_multi: changed references to path/git/local`, `Gg Multi: changed references to pub.dev`) are still recognized so tickets started with an older gg keep skipping correctly. A gg-labeled commit is additionally only trusted when it touches nothing but gg-owned files (manifests, lock files, overrides, `CHANGELOG.md`, `.gitignore`/`.gitattributes`, `.gg/`) — gg's ref commits are _force_ commits that sweep pending user edits into the bookkeeping commit, and such swallowed work must block the skip. If neither, the repo is **not published**: it is logged (`<repo>: not published — …`, plus a `Not published because unchanged: …` summary), marked `skipped` in the ticket file, and its _current_ version is still captured so dependents resolve against the already-published release. Everything undecidable (unknown version, unparsable constraint, uninspectable history) errs toward publishing. `--publish-unchanged` restores the old publish-everything behaviour. On `--continue` a repo marked `skipped` is **re-evaluated instead of trusted** — commits added after a failed run must never be lost to a stale marker (`published` markers are still trusted).

**Config resolution** (`_resolvePublishConfig`, precedence): `--continue` reuses the runtime `.gg/.gg-publish.json` (errors if absent) → an explicit `--config <path>` → the runtime `.gg/.gg-publish.json` → the legacy `<ticket>/.gg-publish.json` → an interactive `do configure-publish`. `--reconfigure` skips the two implicit files so the user is asked again. `--config`/legacy files are only _read_; the mutable runtime copy at `.gg/.gg-publish.json` is what receives progress and is deleted on full success (a user's `--config` file is never touched). Merge message + version increment per repo come from `PublishConfig.forRepo` (per-repo override → top-level default). `-m`/`--message` is forwarded to `do configure-publish` as the default merge message and therefore only matters on the interactive/`--reconfigure` path — it is ignored once a config exists or is supplied via `--config`.

**Progress + `--continue`**: after each repo, its status is written into the ticket-level `.gg/.gg-publish.json` (`published` on success, `failed` on failure, `skipped` when the unchanged-repo check decided against a release). `--continue` skips repos already marked `published` (still capturing their version so dependents resolve) and resumes the rest, forwarding `resume: true` to gg_one's `do publish` — which resumes at the first open step of its own repo-level `<repo>/.gg/.gg-publish.json` (`done_steps`; see the gg_one CLAUDE.md). Two levels, one file family: ticket file = repo status, repo file = step progress. `_publishRepo` also ensures `.gg/.gg-publish.json` is in each repo's `.gitignore` (via gg_one's `EnsurePublishConfigIgnored`, `commit: false` — the entry rides along the pre-publish force-commit). Review + `can publish` are skipped on `--continue` **when irreversible progress exists**: some repo is `published`, or some repo's own step file records `done_steps` (the first repo may fail after its registry publish/merge with only `failed` in the ticket file — re-reviewing that partially merged ticket would throw "nothing to merge" and block the resume). A `--continue` after a pure review failure (no progress anywhere) still reviews; gg_one re-checks `did commit` per repo on resume. An explicit `--config` refuses to clobber a runtime file that still holds progress (same guard as the implicit path; combine with `--reconfigure` to discard), and `do configure-publish` refuses likewise. `--reconfigure` discards the ticket file **and** the repo-level step files.

**Pointing the unpublished repos back at the registry** (`_changeRemainingRefsToPubDev`): a repo that was skipped as unchanged — or, on `--continue`, published by an earlier run — never went through `_publishRepo`, so it still carries the refs `do review` wrote: a `pubspec_overrides.yaml` pinning the ticket's feature branch. The cleanup below deletes exactly that branch (and the provider often deletes it the moment the pull request merges), so those repos are unlocalized, given the versions published in this run and re-resolved (`dart pub get` / the TypeScript equivalent) **before** the cleanup runs — the loop is through by then, so every version of the ticket is known. Without it the trashed repo could never resolve its dependencies again. A repo's own entry is dropped from the version map (a package does not depend on itself), and a failure is reported in yellow and the remaining repos are still processed: everything irreversible has already happened, and aborting here would leave the ticket half cleaned up.

**Trashing the ticket** (`gg do merge` included, it shares this flow): after every repo published, `_cleanUpTicket` deletes each repo's remote feature branch, moves the repo folder to `<root>/.trash/<ticket>/<org>/<repo>`, moves `<ticket>.code-workspace` after them, and finally deletes the (now empty) ticket folder. This is unconditional — the user is never asked, and a `delete_ticket` left over in an old config file is ignored. `--no-delete-remote-branch` keeps the branches on the git remote; **the local folders are moved either way**, because the ticket folder goes away regardless and a repo left inside it would be lost with it. A repo that could not be moved is reported in red and the remaining ones are still processed, but then the ticket folder is _kept_ — nothing is deleted while something is still in it.

**Reporting a failure**: the moment `failed` is written for a repo, `_logPublishFailure` prints why — the repo name plus the exception text in red (the `Exception: ` prefix stripped), followed by a yellow resume hint whose `gg do publish --continue` is blue. It runs _before_ the rollback, otherwise the reason scrolls away above it; and it is printed unconditionally, because the per-repo detail goes to `taskLog`, which is a no-op without `--verbose`. The exception is still rethrown, so the runner's own error line stays as well.

Each repo is snapshotted before its publish (branch — the commit hash when HEAD is detached, HEAD, `status`/stash via the same `stash push --include-untracked` capture as `do review`, package version, `main`/`master` position local + remote, the feature branch's remote head, tags). **When the publish of a repo fails, only that repo is restored — previously published repos stay published.** The restore is two-mode, because gg*one's flow publishes to the registry \_before* merging and pub.dev/npm cannot be unpublished:

- **Full restore** — only when provably nothing irreversible happened: end merges/rebases, back to the feature branch, `reset --hard`, restore the local main position, delete tags the run created, re-apply stashed changes with `--index`.
- **Cleanup restore** — otherwise, **keep all commits** so a `--continue` resumes via gg*one's step file (`<repo>/.gg/.gg-publish.json`, `done_steps`), which is kept on this path because its markers stay real. Cleanup is entered on any of: a \_committed* version bump (a version change still uncommitted in the working tree is a half-written bump and does **not** count — it is recoverable, so it full-restores), `origin/main` having moved, or the feature branch already pushed. Remote comparisons only conclude "moved" from a concrete differing hash — an unreachable `git ls-remote` (often the very cause of the failure) is treated as _unknown_, never as "already released". The **full restore** additionally deletes the repo-level step file: it is gitignored and survives `reset --hard`, but its markers would describe commits the rollback just removed.

The publish failure always stays the primary error; restore problems are logged with a manual-recovery hint that includes the checkout/reset commands and the stash hash.

### `do merge` Command

`DoMergeCommand` (in `lib/src/commands/do/merge.dart`) is `DoPublishCommand` with `mergeOnly: true` — the _same_ flow (config resolution, `do review` + `can publish`, unlocalize refs, restore `publish_to`, propagate versions, refresh deps, commit, push, delegate to gg_one, ticket cleanup) with every release step left out inside gg_one: **no version bump, no `CHANGELOG.md` release heading, no registry upload and no version tag** (`gg do publish --merge-only`, see the gg_one CLAUDE.md). Each repo's main branch therefore keeps its released version and its `## Unreleased` entries; the next `gg do publish` releases them. Because nothing is uploaded, the run also skips the registry-visibility capture — recording a version that never appears on pub.dev/npm would make every dependent repo wait for a release that is not coming. All user-facing wording follows the mode (`merged` instead of `published`, `gg do merge --continue` in the resume hints); the runtime file, the per-repo `status` markers and `--continue`/`--reconfigure`/`--publish-unchanged` are unchanged.

**Precondition**: the merge is refused while any repo of the ticket still redirects a dependency to a local working copy — a `pubspec_overrides.yaml` carrying a `path:` override (gg*one's `NoPubspecOverrides.hasLocalizedRefs`; missing/empty/overrides-free files and files holding only git refs pass, an unparsable one is treated as localized). Merging such a ticket would put references onto the main branch that nobody can resolve, so it has to be \_published*. The guard runs **before `do review`**, because reviewing replaces the path overrides with git refs and would hide the very state being checked. `--force` skips it and is forwarded to gg_one, which then deletes the overrides file like a normal publish.

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
