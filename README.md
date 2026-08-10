# gg_multi

`gg_multi` is the multi-repository workspace engine of the Gg Multi
Suite. It manages a **ocean** of registered repositories
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

- A persistent ocean under `.ocean/` containing every
  registered repo and organisation, grouped as `.ocean/<org>/<repo>`.
- Per-ticket workspaces under `tickets/<id>/` that hold scoped clones
  of the repos you need for one feature, in the same `<org>/<repo>`
  layout.
- A trash under `.trash/<id>/`: when a ticket is closed — via
  `do rm ticket`, or by accepting the offer `do publish` makes up
  front — the whole ticket folder is moved there in one piece
  instead of being deleted: repos as they are, `ticket.json`, the
  `.code-workspace` file, everything. Nothing you forgot to commit is
  lost, and the closed ticket can still be re-imported from the trash.
  Emptying it is up to you.
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
├── can   commit | push | publish | review
├── did   commit | push | review
└── do    commit | push | publish | review
          add | rm | create ticket
          init workspace | init claude | code
          exec cmd
          ls repos | organizations | deps <target> | tickets
```

All cross-repo commands run inside a ticket directory
(`tickets/<id>/`) and iterate over the ticket's repos in dependency
order.

### `gg_multi do ls`

| Command                        | Purpose                                                 |
| ------------------------------ | ------------------------------------------------------- |
| `gg_multi do ls repos`         | list every repo in the ocean, sorted by name            |
| `gg_multi do ls organizations` | list every GitHub organisation represented in the ocean |
| `gg_multi do ls deps <target>` | list `dependencies` / `dev_dependencies` of `<target>`  |
| `gg_multi do ls tickets`       | list every ticket workspace under `tickets/`            |

### `gg_multi do` — workspace setup

| Command                                             | Purpose                                                             |
| --------------------------------------------------- | ------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `gg_multi do init workspace`                        | initialise the ocean in the current directory                       |
| `gg_multi do add <target> [-f                       | --force]`                                                           | add a repo or all repos of an organisation to the workspace                        |
| `gg_multi do rm repo <name…> [--from-master]`       | delete repos from the current ticket (or, with the flag, from the ocean) |
| `gg_multi do rm ticket [<ticket-id>...]`            | close tickets (default: the current one): delete remote branches, move them to `.trash` |
| `gg_multi do upgrade ocean [-n                      | --dry-run]`                                                         | sync `.ocean` with every registered organisation: clone new repos, trash gone ones |
| `gg_multi do create ticket <id> [-m <description>]` | create `tickets/<id>/` with a `.ticket` file                        |
| `gg_multi do create graph [--format=…] [-o <file>]` | write the dependency graph of the workspace to stdout or a file     |
| `gg_multi do code`                                  | open the current ticket in VS Code                                  |
| `gg_multi do init claude`                           | aggregate each repo's `CLAUDE.md` into one ticket-level `CLAUDE.md` |
| `gg_multi do exec cmd <cmd>`                        | run a shell command in every ticket repo                            |

`gg_multi do add` is context-aware:

- run from the workspace root: the repo is cloned into
  `.ocean/<org>/`,
- run from inside a ticket (`tickets/<id>/`): the repo is also
  copied into `tickets/<id>/<org>/` and its local dependencies are
  pulled in.

### `gg_multi can` — preflight checks

| Command                | Purpose                                                             |
| ---------------------- | ------------------------------------------------------------------- |
| `gg_multi can commit`  | run `gg can commit` in every ticket repo (analyze + format + tests) |
| `gg_multi can push`    | check that every ticket repo is push-ready                          |
| `gg_multi can publish` | check that every publishable repo is publish-ready                  |
| `gg_multi can review`  | check that every repo is on a feature branch and committed          |

Each `can` command aborts on the first failure so you find out early
when a repo is in a bad state.

### `gg_multi do` — execute across ticket repos

| Command                             | Purpose                                                                             |
| ----------------------------------- | ----------------------------------------------------------------------------------- |
| `gg_multi do commit [-m <message>]` | commit every ticket repo with the same message (defaults to the ticket description) |
| `gg_multi do push [--force]`        | merge the main branches into the feature branches and push every ticket repo        |
| `gg_multi do review`                | push (incl. main merge), plan the release, open a pull request per released repo and record the review |
| `gg_multi do publish`               | publish every publishable package of the ticket (requires `did review`)             |

`do review` runs `do push` automatically before it opens the pull
requests; a `do push` after the review updates them.

### `gg_multi did` — reporting

| Command               | Purpose                                                      |
| --------------------- | ------------------------------------------------------------ |
| `gg_multi did commit` | report which repos have new commits since the last reference |
| `gg_multi did push`   | report which repos have new pushed commits                   |
| `gg_multi did review` | report whether the current ticket state was reviewed         |

## Folder layout

```
my_project/
├── .ocean/                    # every registered repo (managed by gg_multi)
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
    └── PROJ-123/               # the closed ticket, moved here as a whole
        ├── PROJ-123.code-workspace
        ├── ticket.json
        └── ggsuite/
            └── gg_multi/
```

`WorkspaceUtils.detectTicketPath()` walks up the directory tree from
wherever you invoke `gg_multi` to find the matching workspace, so the
commands work from any sub-directory inside it.

### Organization folders

Every repo lives in a folder named after the organization of its git
URL — `.ocean/ggsuite/gg_multi` for
`https://github.com/ggsuite/gg_multi.git`. This lets same-named repos
from different organizations coexist on disk. A ticket mirrors the
ocean layout, so a repo has the same relative path in both, and the
`.code-workspace` file lists its folders as `<org>/<repo>`.

On **Azure DevOps the folder is the project**, not the account Azure
calls the organization: repository names are unique per project, so two
projects of one account can each own a `common` repo. Adding
`https://dev.azure.com/mhk-carat/ds_cdm` therefore puts its repos into
`ds_cdm/`.

You address a repo by its plain name everywhere — `gg_multi do add
gg_test`, `gg_multi do rm repo gg_test`, `gg_multi do code
PROJ-123/gg_test` — gg_multi finds it in whichever organization folder
it sits. A repo is
resolved by exact folder name first, then by the package name in its
manifest, then by its git remote URL. An organization folder that loses
its last repo is removed.

When you add a repo by its plain name and several known organizations
own a repo of that name, gg_multi lists them and lets you pick one with
the cursor keys. It asks nothing when only one organization owns it,
when only one organization is known at all, or when the repo is already
in the workspace.

Workspaces created before this layout hold their repos directly in
`.ocean/` (and in the ticket). `gg_multi do add` and `gg_multi do
checkout` move them into their organization folder as a first step,
reading the organization from each repo's git remote; a repo whose
organization cannot be determined stays where it is and keeps working.

The ocean folder used to be called `.master`. A workspace
still carrying that name is renamed to `.ocean` automatically the next
time any gg_multi command resolves the workspace — no manual step
needed. When both `.master` and `.ocean` exist, nothing is touched:
`.ocean` wins and a warning asks you to merge or delete the leftover
`.master` manually.

Note that two packages with the same _manifest_ name still collide in
the dependency graph — the organization folder only solves the on-disk
collision.

## Step-by-step: working on a ticket end-to-end

### 0. One-time project setup

```bash
mkdir my_project
cd my_project
gg_multi do init workspace
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

### 6. Review

```bash
gg_multi do review
```

This runs:

1. `can review` — every repo must be on a feature branch and committed.
2. `do push` — the remote main branch is merged into every feature
   branch, then every repo is pushed.
3. The release is planned: which repos does the ticket actually publish?
   For each of them you are asked for the version increment
   (`patch` / `minor` / `major`) and the merge message.
4. A pull request is opened (or reused) for each of *those* repos, titled
   with its merge message, and its url printed.
5. The ticket state is recorded as reviewed (`did review`).

Repos that are only part of the ticket because they sit between two
changed packages get **no question and no pull request** — they are not
released, so there is nothing to decide and nothing to review. Each one
is reported with the reason instead:

```
gg_multi_workspace
✓ Not published — no pull request. Nothing changed. Skip publishing.
```

The answers are stored in `<ticket>/.gg/gg-publish.json`, so the later
`gg_multi do publish` finds them and asks nothing again. Running
`do review` a second time only asks for what is still unanswered — a
repo that just became releasable, for instance.

The repos keep their local path references — a reviewer who wants to
run the ticket recreates the whole setup with
`gg_multi do import ticket <path|url>` from the ticket's `ticket.json`.

### 7. Iterate on review feedback

```bash
gg_multi do commit -m 'Address review comments'
gg_multi do push
```

`do push` merges the main branches into the feature branches and pushes
every repo — the open pull requests pick the new commits up.

### 8. Publish (when approved)

```bash
gg_multi can publish
gg_multi do publish
```

Publish is meant to be triggered manually by a human after review
approval. It refuses to run when the current ticket state was not
reviewed — commits made after the last `gg_multi do review` require
another review round first.

#### The ticket stays workable

Publishing no longer dismantles the ticket. After each repo is
released, `do publish` brings it back into its working state: the
feature branch is checked out again, the released main state is merged
back into it, the local references return (`pubspec_overrides.yaml` and
`pnpm-workspace.yaml` are restored from the backups taken before the
release; the re-localization then puts the `path:`/`link:` overrides
back on top) and the
state is recorded as `didPublish` in the repo's `.gg/gg.json`. You can
keep working — and publish again from the same branch; repos whose
content is already released are skipped automatically.

Right after the release is planned — and before anything is published —
a menu asks what should happen to the ticket once the run is through.
Pick with the cursor keys:

```
What should happen to the ticket when ready?
❯ Move to .trash and delete the remote branches
  Remove it manually with »gg do rm ticket PROJ-123«
```

Asking here rather than at the end keeps every interactive decision up
front: no prompt ever sits between two publishes or waits for you when
a long unattended run finishes.

The first option deletes the remote feature branches and then moves
the **whole ticket folder** to `.trash/<id>/` in one piece — repos as
they are, `ticket.json`, the `.code-workspace` file, everything.
Afterwards the `cd` command back to the workspace root is printed in
blue, because your shell sits inside a deleted folder at that point.

The second option keeps everything in place; close the ticket whenever
you like with:

```bash
gg_multi do rm ticket PROJ-123
```

Without a terminal (CI, pipes) the menu is skipped and the ticket is
always kept.

#### Unchanged repos are not published

Many repos are only part of a ticket because they sit _between_ two
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

`gg_multi do review` already collected the version increments and merge
messages and wrote them to `<ticket>/.gg/gg-publish.json`, so a reviewed
ticket publishes without a single question. Should an answer be missing
— no review wrote the file, `--restart` discarded it, or a repo only
became releasable afterwards — `do publish` asks for it **up front**,
before the long unattended part starts, and only for the repos it really
publishes. You can also run `gg_multi do configure-publish` on its own to
(re-)write that file ahead of time; it asks every question afresh.

Pass `-m`/`--message` to set the **default merge message** that pre-fills
each repo's prompt (hit enter to accept it, or edit per repo):

```bash
gg_multi do publish -m 'Release: unified publish flow'
```

`-m` only applies while the config is being written interactively (a
fresh run or `--restart`); it takes precedence over the ticket
description and is ignored once a config exists or is supplied via
`--config`. `gg_multi do configure-publish` accepts the same `-m`.

While publishing, each repo's status is recorded in that same file. If a
publish fails partway through, fix the cause and resume with:

```bash
gg_multi do publish --continue
```

`--continue` reuses `.gg/.gg-publish.json`, skips the repos already marked
`published`, skips the up-front review/validation, and picks up at the
repo that failed — and _within_ that repo, gg_one resumes at the first
open publish step (version bump, registry publish, merge, branch
deletion, tag) recorded in the repo's own `.gg/.gg-publish.json`.
Nothing already done is repeated. On a fully successful run the files
are removed again. Use `--restart` to discard an existing
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
  "version_increment": "patch", // "patch" | "minor" | "major"
  "merge_message": "Default merge message",

  // Optional: per-repo overrides. Keyed by the repo's directory name
  // inside the ticket. Each field is independent — anything missing
  // falls back to the top-level value.
  "repos": {
    "<repoName>": {
      "version_increment": "minor",
      "merge_message": "Custom message for this repo",
    },
    "<otherRepo>": {
      "merge_message": "Only override the message, keep the default increment",
    },
  },
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
      "merge_message": "PROJ-123: new public login API",
    },
  },
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
gg_multi do ls -h
```

## Further reading

- [`handbook.md`](handbook.md) — full hands-on walkthrough (German).
- The sibling `gg` package — unified CLI that auto-routes shared
  commands between `gg_one` (single repo) and `gg_multi` (workspace).

## License

`gg_multi` is licensed under the terms specified in the `LICENSE`
file.
