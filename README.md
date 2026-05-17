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
  registered repo and organisation.
- Per-ticket workspaces under `tickets/<id>/` that hold scoped clones
  of the repos you need for one feature.
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
└── do    commit | push | publish | review | cancel-review
          add | add-deps | rm | create ticket
          init | code | claude
          execute | install-git-hooks | install-gitattributes
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
| `gg_multi do create ticket <id> [-m <description>]`    | create `tickets/<id>/` with a `.ticket` file                                         |
| `gg_multi do add-deps <target>`                        | add every `dependencies` / `dev_dependencies` of `<target>` to the master workspace  |
| `gg_multi do code`                                     | open the current ticket in VS Code                                                   |
| `gg_multi do claude`                                   | aggregate each repo's `CLAUDE.md` into one ticket-level `CLAUDE.md`                  |
| `gg_multi do install-git-hooks`                        | install gg's git hooks in every ticket repo                                          |
| `gg_multi do install-gitattributes`                    | install a shared `.gitattributes` in every ticket repo                               |
| `gg_multi do execute <cmd>`                            | run a shell command in every ticket repo                                             |

`gg_multi do add` is context-aware:

- run from the workspace root: the repo is cloned into `.master/`,
- run from inside a ticket (`tickets/<id>/`): the repo is also
  copied into the ticket and its local dependencies are pulled in.

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
| `gg_multi do commit -m <message>`    | commit every ticket repo with the same message                                       |
| `gg_multi do push [--force]`         | push every ticket repo                                                               |
| `gg_multi do review`                 | unlocalise → localise as Git refs → `pub upgrade` → commit → push, for every repo    |
| `gg_multi do cancel-review`          | revert a review and return to local working mode                                     |
| `gg_multi do publish`                | publish every publishable package of the ticket                                      |

### `gg_multi did` — reporting

| Command              | Purpose                                                          |
| -------------------- | ---------------------------------------------------------------- |
| `gg_multi did commit` | report which repos have new commits since the last reference    |
| `gg_multi did push`   | report which repos have new pushed commits                      |

## Folder layout

```
my_project/
├── .master/                # every registered repo (managed by gg_multi)
│   ├── gg/
│   ├── gg_multi/
│   └── …
└── tickets/
    └── PROJ-123/           # one ticket workspace
        ├── .ticket         # JSON with id + description
        ├── app_core/       # ticket-scoped clone
        └── ui_core/
```

`WorkspaceUtils.detectTicketPath()` walks up the directory tree from
wherever you invoke `gg_multi` to find the matching workspace, so the
commands work from any sub-directory inside it.

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
gg_multi do cancel-review
```

### 8. Publish (when approved)

```bash
gg_multi can publish
gg_multi do publish
```

Publish is meant to be triggered manually by a human after review
approval.

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
