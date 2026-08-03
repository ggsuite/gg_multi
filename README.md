# gg_multi

`gg_multi` is the multi-repository workspace engine of the Gg Multi
Suite. It manages a **master workspace** of registered repositories
and organisations, lets you create **ticket workspaces** that scope a
subset of those repos to a single feature or bugfix, and orchestrates
cross-repo actions (commit, push, review, publish, …) in dependency
order.

`gg_multi` is normally driven via the `gg` CLI (which auto-detects
workspace vs. single-package mode), but it also ships its own
executable for direct use and in CI/CD pipelines.

> A complete German hands-on walkthrough is available in
> [`handbook.md`](handbook.md) — recommended reading for new users.

## What gg_multi gives you

- A persistent master workspace under `.master/` containing every
  registered repo and organisation, grouped as `.master/<org>/<repo>`.
- Per-ticket workspaces under `tickets/<id>/` that hold scoped clones
  of the repos you need for one feature, in the same `<org>/<repo>`
  layout.
- A trash under `.trash/<id>/`: when a ticket is published, its repos
  and its `.code-workspace` file are moved there instead of being
  deleted, so nothing you forgot to commit is lost. Emptying it is up
  to you.
- Automatic dependency resolution: every cross-repo command runs in
  dependency order so downstream packages see consistent upstream
  state.
- Path localisation: while you work on a ticket, intra-workspace
  `pubspec.yaml` references point to local paths; on review they are
  re-localised to Git refs.
- A single review pipeline (`do review`) that brings every repo of a
  ticket into a state ready for merge or publish.

## Installation

```bash
git clone https://github.com/ggsuite/gg_multi.git
cd gg_multi
./install         # or install.bat on Windows
```

This installs the `gg_multi` executable globally. In most day-to-day
work you will use the `gg` CLI instead (`dart pub global activate
gg`), which routes its shared `can`/`did`/`do` commands to `gg_multi`
whenever you are inside a workspace.

## Command Hierarchy

```
gg_multi
├── ls    repos | organizations | deps <target> | tickets
├── can   commit | push | publish | review
├── did   commit | push
└── do    commit | push | publish | review [--abort]
          add | rm | create ticket
          init | code | claude
          maintain exec
```

All cross-repo commands run inside a ticket directory
(`tickets/<id>/`) and iterate over the ticket's repos in dependency
order.

### `gg_multi ls`

| Command                                | Purpose                                                            |
| -------------------------------------- | ------------------------------------------------------------------ |
| `gg_multi ls repos`                    | list every repo in the master workspace, sorted by name            |
| `gg_multi ls organizations`            | list every GitHub organisation represented in the master workspace |
| `gg_multi ls deps <target>`            | list `dependencies` / `dev_dependencies` of `<target>`             |
| `gg_multi ls tickets`                  | list every ticket workspace under `tickets/`                       |

### `gg_multi do` — workspace setup

| Command                                                | Purpose                                                                              |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------ |
| `gg_multi do init`                                     | initialise the master workspace in the current directory                             |
| `gg_multi do add <target> [-f|--force]`                | add a repo or all repos of an organisation to the workspace                          |
| `gg_multi do rm <target>`                              | remove a repo from the master workspace or delete a ticket workspace                 |
| `gg_multi do update master [-n|--dry-run]`             | sync `.master` with every registered organisation: clone new repos, trash gone ones   |
| `gg_multi do create ticket <id> [-m <description>]`    | create `tickets/<id>/` with a `.ticket` file                                         |
| `gg_multi do create graph [--format=…] [-o <file>]`    | write the dependency graph of the workspace to stdout or a file                      |
| `gg_multi do code`                                     | open the current ticket in VS Code                                                   |
| `gg_multi do claude`                                   | aggregate each repo's `CLAUDE.md` into one ticket-level `CLAUDE.md`                  |
| `gg_multi do maintain`                                 | list the maintenance tasks available for the current ticket                          |
| `gg_multi do maintain exec <cmd>`                      | run a shell command in every ticket repo                                             |

`gg_multi do add` is context-aware:

- run from the workspace root: the repo is cloned into
  `.master/<org>/`,
- run from inside a ticket (`tickets/<id>/`): the repo is also
  copied into `tickets/<id>/<org>/` and its local dependencies are
  pulled in.

### `gg_multi can` — preflight checks

| Command                  | Purpose                                                                |
| ------------------------ | ---------------------------------------------------------------------- |
| `gg_multi can commit`    | run `gg can commit` in every ticket repo (analyze + format + tests)    |
| `gg_multi can push`      | check that every ticket repo is push-ready                             |
| `gg_multi can publish`   | check that every publishable repo is publish-ready                     |
| `gg_multi can review`    | check that every repo is `localized` and has no uncommitted changes    |

Each `can` command aborts on the first failure so you find out early
when a repo is in a bad state.

### `gg_multi do` — execute across ticket repos

| Command                              | Purpose                                                                              |
| ------------------------------------ | ------------------------------------------------------------------------------------ |
| `gg_multi do commit [-m <message>]`  | commit every ticket repo with the same message (defaults to the ticket description)  |
| `gg_multi do push [--force]`         | push every ticket repo                                                               |
| `gg_multi do review`                 | unlocalise → localise as Git refs → `pub upgrade` → commit → push, for every repo    |
| `gg_multi do review --abort`         | revert a review and return to local working mode                                     |
| `gg_multi do publish`                | publish every publishable package of the ticket                                      |

### `gg_multi did` — reporting

| Command              | Purpose                                                          |
| -------------------- | ---------------------------------------------------------------- |
| `gg_multi did commit` | report which repos have new commits since the last reference    |
| `gg_multi did push`   | report which repos have new pushed commits                      |

## Folder layout

```
my_project/
├── .master/                    # every registered repo (managed by gg_multi)
│   ├── ggsuite/                # one folder per organization
│   │   ├── gg/
│   │   └── gg_multi/
│   └── acme/
│       └── app_core/
├── tickets/
│   └── PROJ-123/               # one ticket workspace
│       ├── .ticket             # JSON with id + description
│       ├── ggsuite/
│       │   └── gg_multi/       # ticket-scoped clone
│       └── acme/
│           └── app_core/
└── .trash/
    └── PROJ-123/               # what `do publish` removed from the ticket
        ├── PROJ-123.code-workspace
        └── ggsuite/
            └── gg_multi/
```

`WorkspaceUtils.detectTicketPath()` walks up the directory tree from
wherever you invoke `gg_multi` to find the matching workspace, so the
commands work from any sub-directory inside it.

### Organization folders

Every repo lives in a folder named after the organization of its git
URL — `.master/ggsuite/gg_multi` for
`https://github.com/ggsuite/gg_multi.git`. This lets same-named repos
from different organizations coexist on disk. A ticket mirrors the
master layout, so a repo has the same relative path in both, and the
`.code-workspace` file lists its folders as `<org>/<repo>`.

On **Azure DevOps the folder is the project**, not the account Azure
calls the organization: repository names are unique per project, so two
projects of one account can each own a `common` repo. Adding
`https://dev.azure.com/mhk-carat/ds_cdm` therefore puts its repos into
`ds_cdm/`.

You address a repo by its plain name everywhere — `gg_multi do add
gg_test`, `gg_multi do rm gg_test`, `gg_multi do code PROJ-123/gg_test`
— gg_multi finds it in whichever organization folder it sits. A repo is
resolved by exact folder name first, then by the package name in its
manifest, then by its git remote URL. An organization folder that loses
its last repo is removed.

When you add a repo by its plain name and several known organizations
own a repo of that name, gg_multi lists them and lets you pick one with
the cursor keys. It asks nothing when only one organization owns it,
when only one organization is known at all, or when the repo is already
in the workspace.

Workspaces created before this layout hold their repos directly in
`.master/` (and in the ticket). `gg_multi do add` and `gg_multi do
checkout` move them into their organization folder as a first step,
reading the organization from each repo's git remote; a repo whose
organization cannot be determined stays where it is and keeps working.

Note that two packages with the same *manifest* name still collide in
the dependency graph — the organization folder only solves the on-disk
collision.

## Step-by-step: working on a ticket end-to-end

### 0. One-time project setup

```bash
mkdir my_project
cd my_project
gg_multi do init
gg_multi do add https://github.com/my-org    # pull in every repo of an org
```

### 1. Create a ticket workspace

```bash
gg_multi do create ticket PROJ-123 -m 'Simplify login flow'
cd tickets/PROJ-123
```

### 2. Add the repos you need

```bash
gg_multi do add app_core ui_core
```

Local dependencies are pulled in automatically and `pubspec.yaml`
references are localised to relative paths inside the ticket.

### 3. Open the ticket (optional)

```bash
gg_multi do code
```

### 4. Develop and iterate locally

Work in each repo as you normally would. Inside a single repo you can
run `gg one check` for the full single-repo check pipeline.

### 5. Commit across all ticket repos

```bash
gg_multi can commit
gg_multi do commit -m 'Simplify login flow'
```

`can commit` runs the per-repo check pipeline in dependency order and
aborts on the first failure; `do commit` then commits each repo with
the same message.

Without `-m`, `do commit` reuses the ticket description from the
`.ticket` file and opens it in the same editor `do publish` uses for its
merge messages — so you can adjust it before it is applied to every repo:

```bash
gg_multi do commit
# Edit commit message (Simplify login flow) ›
```

### 6. Push

```bash
gg_multi can push
gg_multi do push
```

### 7. Review

```bash
gg_multi do review
```

For every ticket repo this runs:

1. Unlocalise references (back to original form via
   `gg_localize_refs`), status → `unlocalized`.
2. Re-localise as Git references, status → `git-localized`.
3. `dart pub upgrade` (if `pubspec.yaml` exists).
4. `gg do commit` with a default review message.
5. `gg do push`.

Need to keep working after starting a review?

```bash
gg_multi do review --abort
```

### 8. Publish (when approved)

```bash
gg_multi can publish
gg_multi do publish
```

Publish is meant to be triggered manually by a human after review
approval.

#### Unchanged repos are not published

Many repos are only part of a ticket because they sit *between* two
changed packages in the dependency chain. Before publishing a repo,
`do publish` therefore checks:

1. Did a dependency published earlier in the run receive a version the
   repo's published constraint cannot absorb (e.g. a whole-number/major
   bump such as `1.x` → `2.0.0`, or `0.3.x` → `0.4.0` for `^0.3.0`)?
2. If not: does the repo contain manual changes — commits not generated
   by gg itself, or uncommitted edits? Commit messages starting with
   `#gg: ` (and the exact bookkeeping messages of older gg versions)
   count as gg-generated; everything else counts as manual.

When neither is the case, the repo is left unpublished and marked
`skipped`; dependents keep resolving against its already-published
version. Anything undecidable errs toward publishing, and on
`--continue` a previously skipped repo is re-checked instead of
trusted. Pass `--publish-unchanged` to force the old behaviour and
publish every repo of the ticket.

#### Configuration up front, and resuming after a failure

`gg_multi do publish` gathers **all** interactive input before the long,
unattended publish starts. When no config is supplied it runs
`gg_multi do configure-publish`, which asks — per repo, in dependency
order — for the version increment (`patch` / `minor` / `major`) and the
merge message, plus a single "delete the ticket?" choice, and writes the
answers to `<ticket>/.gg/.gg-publish.json`. You can also run
`gg_multi do configure-publish` on its own to prepare that file ahead of
time.

Pass `-m`/`--message` to set the **default merge message** that pre-fills
each repo's prompt (hit enter to accept it, or edit per repo):

```bash
gg_multi do publish -m 'Release: unified publish flow'
```

`-m` only applies while the config is being written interactively (a
fresh run or `--reconfigure`); it takes precedence over the ticket
description and is ignored once a config exists or is supplied via
`--config`. `gg_multi do configure-publish` accepts the same `-m`.

While publishing, each repo's status is recorded in that same file. If a
publish fails partway through, fix the cause and resume with:

```bash
gg_multi do publish --continue
```

`--continue` reuses `.gg/.gg-publish.json`, skips the repos already marked
`published`, skips the up-front review/validation, and picks up at the
repo that failed — and *within* that repo, gg_one resumes at the first
open publish step (version bump, registry publish, merge, branch
deletion, tag) recorded in the repo's own `.gg/.gg-publish.json`.
Nothing already done is repeated. On a fully successful run the files
are removed again. Use `--reconfigure` to discard an existing
`.gg/.gg-publish.json` (ticket and repo level) and be asked again.

#### Non-interactive publish via `--config`

To publish without any prompts (scripted runs, CI pipelines, release
tooling), pass `--config <path>` to load the merge messages and
increments from a JSON file instead:

```bash
gg_multi do publish --config .gg-publish.json
```

`gg_multi` looks for the file at `<configArg>` first (relative to the
current directory, or absolute), then under the **ticket directory**.
Missing fields cause a hard `FormatException` — no silent fall-back to
an interactive prompt. The `--config` file is only read; a runtime copy
at `<ticket>/.gg/.gg-publish.json` holds the progress and is removed on
success, so your source file is left untouched.

##### `.gg-publish.json` schema

```jsonc
{
  // Top-level defaults applied to every repo of the ticket.
  "version_increment": "patch",            // "patch" | "minor" | "major"
  "merge_message": "Default merge message",

  // Optional: per-repo overrides. Keyed by the repo's directory name
  // inside the ticket. Each field is independent — anything missing
  // falls back to the top-level value.
  "repos": {
    "<repoName>": {
      "version_increment": "minor",
      "merge_message": "Custom message for this repo"
    },
    "<otherRepo>": {
      "merge_message": "Only override the message, keep the default increment"
    }
  }
}
```

Resolution order per repo:

1. `repos.<repoName>.version_increment` / `merge_message`, then
2. top-level `version_increment` / `merge_message`.

If neither layer supplies a value for a repo that is about to publish,
the run aborts with an error naming the missing field.

##### Example

```jsonc
// tickets/PROJ-123/.gg-publish.json
{
  "version_increment": "patch",
  "merge_message": "PROJ-123: simplify login flow",
  "repos": {
    "app_core": {
      "version_increment": "minor",
      "merge_message": "PROJ-123: new public login API"
    }
  }
}
```

Then:

```bash
cd tickets/PROJ-123
gg_multi do publish --config .gg-publish.json
```

→ `app_core` gets a minor bump with the custom message; every other
ticket repo gets a patch bump with the top-level message.

The same flag exists on the single-repo `gg one do publish` (it reads
the same schema but only uses the top-level fields). See the
[`gg_one` README](../gg_one/README.md) for details.

## Running tests

```bash
dart test
```

A coverage report can be generated with:

```bash
dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info
```

`gg_multi` is held at 100 % test coverage.

## Getting help

```bash
gg_multi -h
gg_multi do -h
gg_multi do add -h
gg_multi can -h
gg_multi ls -h
```

## Further reading

- [`handbook.md`](handbook.md) — full hands-on walkthrough (German).
- The sibling `gg` package — unified CLI that auto-routes shared
  commands between `gg_one` (single repo) and `gg_multi` (workspace).

## License

`gg_multi` is licensed under the terms specified in the `LICENSE`
file.
