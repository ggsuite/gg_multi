# Changelog

## Unreleased

### Changed

- CLAUDE.md and handbook document the per-repo `.gg/publish_config.json` the AI maintains
## 9.0.0 - 2026-08-10

### Changed

- No tickets folder anymore. Plain repos in ticket.

## 8.3.2 - 2026-08-10

### Fixed

- Various fixes

## 8.3.1 - 2026-08-10

### Fixed

- Fix »gg do rm« issues

## 8.3.0 - 2026-08-10

### Changed

- Don't review skipped packages
- Merge origin/main

## 8.2.0 - 2026-08-09

## 8.1.0 - 2026-08-08

## 8.0.0 - 2026-08-08

## 7.13.1 - 2026-08-05

### Changed

- Split gg_multi into multiple packages

## 7.13.0 - 2026-08-04

### Changed

- Show ticket deletion dialog at the beginning of publish. Recolorize.
- Use overrides in package.json

## 7.12.0 - 2026-08-04

## 7.11.2 - 2026-08-04

### Changed

- Fix issues with CHANGELOG.md

## 7.11.1 - 2026-08-04

### Removed

- Remove duplicate upgrade calls from publish workflow

## 7.11.0 - 2026-08-04

### Changed

- Improve push and publish workflow
- Rename »gg do upgrade dependencies« into »gg do upgrade deps«

## 7.10.0 - 2026-08-04

### Changed

- Rename .master to .ocean with automatic migration at next start
- Rename ocean workspace -> ocean

## 7.9.5 - 2026-08-04

### Changed

- Finetune command line output
- Update dependencies

## 7.9.4 - 2026-08-03

### Changed

- Prevent pubspec.lock interrupting publishing

### Fixed

- Fix issues with pubspec.lock

## 7.9.3 - 2026-08-03

### Fixed

- Fix test error paths

### Removed

- Remove ./ from test error paths to allow directly opening it in vscode

## 7.9.2 - 2026-08-03

### Changed

- Improve review workflow
- Improve workflow

## 7.9.1 - 2026-08-03

### Changed

- dart pub upgrade --major-versions --tighten
- shorten the long CLI messages and share the duplicated ones: one
unfinishedPublishMessage, one continueConflictMessage, one editMessage
- use the semantic colors of gg_console_colors: cAction for instructions,
cWarn for warnings, cDetail for progress, cCmd/cPath inside a message
- wrap every exception text in cError
- assert the plain text in the tests, not the escape codes (rmC)
- replace the ✓/✗ emoji by the plain marks ✓/✗ — gg_status_printer 1.2.0
colors them via cSuccess/cError
- use rmC from gg_console_colors in the tests instead of a local copy of
the color stripper
- print a blank line before each cyan repo name so the per-repo blocks
are visually separated
- replace do cancel-review with do review --abort
- move ls under do
- refactor: rename publish --reconfigure to --restart
- refactor: shorten all CLI help texts to 60 chars
- Rework CLI texts
- refactor(gg_multi): move do maintain exec to do exec
- rename do update to do upgrade — do upgrade master instead of do update master
- move do exec to do exec cmd
- move do checkout to do import ticket
- move do init to do init workspace and do claude to do init claude
- reword the remaining command descriptions to the same terse imperative
the rest of the CLI uses
- Rework console colors
- Improve cli log and colors

### Fixed

- Fix unit test errors

### Removed

- remove do install-git-attributes command
- remove do add-deps command
- remove do configure-publish from the CLI — do publish calls it itself
- Remove unused CLI commands

## 7.9.0 - 2026-08-02

### Added

- `gg do review` opens a pull request for every ticket repo right after pushing it and prints its url, so the work can be reviewed while the ticket is still open. The pull requests carry **no** auto-merge flag — `gg do publish` reuses them and sets it when the release is done. An existing open pull request is reused, and a repo whose pull request cannot be opened (no GitHub/Azure DevOps remote, missing `gh`/`az`) is reported without failing the review.

### Changed

- Create pull request as part of the review

## 7.8.0 - 2026-08-02

### Added

- `do update master`: syncs the master workspace with the git platforms. It walks every organization of `.organizations`, fetches its current repository list, clones the repos master lacks and moves the ones the organization no longer offers to `<root>/.trash/.master/<org>/<repo>`. Repos are matched by remote url, so a folder named after the package is recognized. Nothing is removed on a guess: an unparsable/missing remote, an unregistered organization and every repo of an organization whose fetch failed stay untouched. `--dry-run` reports without changing anything.
- `Trash.moveFromMaster`: moves a master repository into `<root>/.trash/.master`, with the same never-overwrite ` (2)` suffixing and cross-volume fallback `moveFromTicket` uses.
- Add gg do update master

### Changed

- Do not write dart specific code into pure typescript .gitattributes
- Throw an error when added repo in master is not clean
- Either copy symlinks or throw an exception that symlinks are not supported

### Fixed

- Fix gg do add errors

## 7.7.0 - 2026-08-02

### Changed

- Use gg_args 2.1.0 which reports unknown sub commands itself
- Keep gg bookkeeping commits out of CHANGELOG.md using --no-log

### Removed

- Remove gg do merge, use gg do publish --merge-only which asks for no version increment

## 7.6.0 - 2026-08-02

### Added

- Add »gg do create graph« to output mermaid graphs
- `gg do create graph` boxes the repositories of each organization in a mermaid
`subgraph` when more than one organization is shown. `--no-group-by-orgs`
turns the boxes off.
- Add »gg do add --no-localize«, »--org« and »--all«

### Changed

- Allow to group nodes by org
- Allow to print dependency graphs using "gg do create graph"
- Allow to print dependency graphs using "gg do create graph"
- dependency_graph

## 7.5.0 - 2026-08-01

### Added

- `gg do create graph` Writes the dependency graph to stdout or file,
as `mermaid` (default) or `json`. Inside a ticket it graphs the ticket repos
and what they reach, outside a ticket the whole master workspace, and
`--org <name>` narrows it down to one organization. Redundant edges are
hidden by default (`--no-transitive-reduction` keeps them); further options
are `--orientation`, `--(no-)dev-dependencies` and `--3rdparty-deps`.
`--output <file>` (`-o`) writes the graph into a file instead of stdout.
Arrows point from the dependency to the dependent, so a horizontal chart
lists the dependencies on the left and the dependents on the right.

## 7.4.1 - 2026-08-01

### Changed

- `gg can publish` verifies the npm login of every repo as its own step. It therefore stays a ticket-wide, up-front check even though the rest of the per-repo publish readiness moved into `do publish`, so a missing npm login is still reported before the first package is uploaded.
- A failed `gg do merge` reports "Merging … failed" and "The merge is marked as »failed«" instead of the publish wording.
- New `CanPublishCommand.checkTicket(…, includeCanPublish:)` and `CanPublishCommand.checkRepo(…)`. `gg can publish` itself is unchanged apart from the added npm step.
- Can publish runs per repo right before that repo is published

### Fixed

- `do publish`/`do merge` no longer fail on a ticket whose repos depend on each other. `gg can publish` ran pana for every repo up front, where a constraint naming an as-yet-unpublished sibling version cannot resolve. The check now runs per repo, right before that repo is published — after its refs were unlocalized and committed and before it is pushed — so every dependency published earlier in the same run is already on its registry.

## 7.4.0 - 2026-08-01

### Changed

- **Breaking:** `ticket.json` is no longer written into the repositories of a ticket, force-staged and pushed. It now lives in the ticket folder only (`tickets/<ticket>/ticket.json`), so a private ticket's description and repo list never reach a remote.
- **Breaking:** `do checkout` takes the path or an `http(s)` URL of a `ticket.json`; a directory is read as a ticket folder. Reading the marker from `origin/<branch>` still works for branches an older gg pushed, but warns that it is deprecated.
- Do not upload ticket.json. Share it manually and import it using "gg do checkout"

### Fixed

- `.gg/ticket.json` and `.gg/.ticket.json` are gitignored again instead of whitelisted, and `copyDirectory` skips both names.

## 7.3.2 - 2026-08-01

### Changed

- Merge gg one do merge to gg one do publish --merge-only

### Removed

- Dead »MockGgDoMerge« stubs in the do-review tests — gg_one's »DoMerge« class is gone, its merge implementation is now gg_one's »MergeFlow«

## 7.3.1 - 2026-08-01

### Changed

- Take base version from git tags when publish_to is none

## 7.3.0 - 2026-08-01

### Changed

- \#gg: changed references to pub.dev

### Fixed

- Fix missing git references

### Removed

- Remove code modifying publish_to because it is not used anymore

## 7.2.2 - 2026-08-01

### Changed

- Fix: Skipping unchanged repos from publishing does not work

### Fixed

- Fixes

## 7.2.1 - 2026-08-01

### Added

- »do publish« makes sure every repo has at least one version on its
registry (pub.dev / npm) before it is published. A repo that was never
published is published manually by the user first — the shell commands to
execute are shown, the publish continues after the package became visible
on the registry

### Changed

- Make sure package is already published in registry before publishing
- Adapt first-publish gate to merge-only mode from main
- Make sure, package is already published in registry before publishing

## 7.2.0 - 2026-08-01

### Changed

- Introtruce .trash for deleted tickets and repos

### Removed

- Introduce .trash for published tickets and removed repos

## 7.1.4 - 2026-08-01

### Changed

- Auto merge CHANGELOG.md
- Tidy CHANGELOG entry
- \#gg: changed references to git

### Fixed

- Fix gg do rm repo does not work only work in ticket root but not when in one of the subfolders
- Fix »gg do merge« conflicting with a leftover remote feature branch of an already merged ticket
- Fix error while executing gg do merge

## 7.1.0 - 2026-08-01

### Added

- Add »gg do merge«

## 7.0.1 - 2026-07-31

### Changed

- Require minimum gg version

## 7.0.0 - 2026-07-31

### Changed

- Do not publish unchanged packages: skip repos without manual changes when no dependency outgrew its published constraint
- Prefix all gg-generated commit messages with "#gg: "; the unchanged-repo check treats such commits as not user generated
- Treat gg-labeled commits touching non-gg files as manual changes so force-committed user work blocks the skip
- Do not update unchanged packages

## 6.0.4 - 2026-07-31

### Changed

- Print »waiting until ... appears on pub.dev only one time
- Don't hide files in .gg folder

## 6.0.3 - 2026-07-31

### Changed

- Rename exec into maintain

## 6.0.2 - 2026-07-31

### Changed

- Colorize 'Deleted repository from ticket message'

## 6.0.1 - 2026-07-31

### Changed

- Print publish fail reason to console

## 6.0.0 - 2026-07-31

### Changed

- Put repos into org folders

## 5.12.10 - 2026-07-30

### Changed

- Improve main merging behavior

## 5.12.9 - 2026-07-30

### Removed

- Remove gg_multi_ui - heavy dependency from gg_multi

## 5.12.8 - 2026-07-30

### Changed

- »gg do rm« deletes repos from ticket

## 5.12.7 - 2026-07-30

### Changed

- Don't fail when repo is already deleted on merging

## 5.12.6 - 2026-07-30

### Fixed

- Stale `.gg/.gg-publish.json` publish progress is no longer carried from the
master workspace into ticket copies: `copyDirectory` skips the file and
`do add` deletes a leftover from the master repo before copying. Such a
leftover made a fresh `gg do publish` in the new ticket abort with
»An unfinished publish left progress …«.
- Fix publishing error

## 5.12.5 - 2026-07-30

### Changed

- Don't show duplicate output when adding repos

## 5.12.4 - 2026-07-30

## 5.12.3 - 2026-07-30

### Removed

- Remove doublicate cli output when adding organisations

## 5.12.2 - 2026-07-29

### Changed

- Support projects without manifest: ProjectType.none, checks skipped, version tracked as git tag only
- do publish: the wait for published dependencies now announces the registry status url, reports progress while polling (via gg_lang's RegistryWaiter logging) and no longer hangs — every registry lookup is bounded by a request timeout; the overall timeout was raised to 15 min (pub.dev, which itself can take up to ~10 min) / 5 min (npm)
- do publish: registry waits show status url and progress, never hang
- Raise pub.dev wait timeout to 15 min (pub.dev can take ~10 min)
- Reuse the ticket message as default

### Fixed

- bin test no longer expects a Windows line ending in the "Missing target parameter." message
- Fix hanging publishing process

## 5.12.1 - 2026-07-29

### Changed

- Delete ticket and remote feature branches by default

## 5.12.0 - 2026-07-29

## 5.11.0 - 2026-07-29

### Changed

- gg_multi: changed references to git

### Removed

- Remove git hooks functionality completely because merging is done via merge requests

## 5.10.1 - 2026-07-29

## 5.10.0 - 2026-07-22

### Changed

- Forward --pr and --no-pr to gg_one so ticket publishes merge via auto-merge pull requests by default
- Update publish docs: the final merge goes through an auto-merge squash pull request by default
- Run npm registry lookups in the package directory so the project-level .npmrc with private feeds is honored
- gg_multi: changed references to git

## 5.9.0 - 2026-07-20

### Changed

- Print repos added to a ticket in blue instead of green - `gg do checkout` included
- gg_multi: changed references to git

### Fixed

- Ignore `.gg/*` instead of the whole `.gg` directory, so `.gg/.gg.json` and `.gg/.ticket.json` stay trackable

## 5.8.0 - 2026-07-20

### Added

- Add rc prerelease channel to gg do publish (channel field/flag, X.Y.Z-rc.N computation, npm --tag rc, single + multi repo)

### Changed

- gg_multi: changed references to git

## 5.7.1 - 2026-07-16

### Added

- The delete-ticket and merge-message default prompts fail fast with an
actionable error when stdin is not a terminal (via gg_one's
throwWhenNotATerminal), instead of hanging forever in CI or piped
shells. Set delete_ticket in `.gg/.gg-publish.json` (or pass `-m` /
`--config`) for headless runs.

### Changed

- Tidy CHANGELOG Unreleased sections
- gg_multi: changed references to git

## 5.7.0 - 2026-07-15

### Added

- `do configure-publish`: new command that interactively writes
`<ticket>/.gg/.gg-publish.json` (per-repo version increment + merge
message, plus one `delete_ticket` choice). `do publish` runs it
automatically when started without a config, so every interactive
decision is made up front before the unattended publish.
- `do publish --continue`: records per-repo progress in
`.gg/.gg-publish.json`, skips already-published repos and resumes the
rest after a failure; the file is deleted on full success. Review /
`can publish` are re-run unless at least one repo already published.
Within a repo, resume: true is forwarded to gg_one's `do publish`,
which resumes at the first open step of its repo-level
`<repo>/.gg/.gg-publish.json` (done_steps) — including the version
tag. The full-restore rollback deletes that repo-level file (its
markers would be stale); the keep-commits rollback keeps it, and
`--reconfigure` discards ticket **and** repo-level files. Each repo's
`.gitignore` gets the `.gg/.gg-publish.json` entry automatically
before the pre-publish commit.
- `do publish --reconfigure`: discards an existing `.gg/.gg-publish.json`
and reconfigures interactively.
- Code-review hardening: `--continue` also skips review/can-publish when
a failed repo's own step file proves irreversible progress (first-repo
failure after registry publish/merge no longer blocks the resume);
`--config` and `do configure-publish` refuse to clobber a runtime file
that still holds progress markers.

### Changed

- `do publish --message` / `-m` is kept, with refined meaning: it is the
default merge message used only when the `.gg/.gg-publish.json` is
written interactively (a fresh run or `--reconfigure`). It seeds every
repo's merge-message prompt and takes precedence over the ticket
description. It is ignored once a config exists or is supplied via
`--config`. `do configure-publish` accepts the same `-m`.
- Tidy CHANGELOGs: single Unreleased section and chronological order
- gg_multi: changed references to git

### Fixed

- Code-review fixes: resume-safe branch handling, progress guards for configure/--config, did-commit check and idempotent branch deletion on resume

## 5.6.0 - 2026-07-13

### Changed

- `do review` and `do publish` now roll back the repository state when
they fail, restoring the snapshot taken before the run. `do review`
restores every changed, not-yet-pushed repo; `do publish` restores only
the failed repo — fully when nothing irreversible happened, otherwise
keeping all commits so a re-run resumes. The shared git runner and
snapshot capture live in `backend/git_snapshot.dart`.

## 5.5.1 - 2026-07-06

### Changed

- gg_multi: changed references to git

## 5.5.0 - 2026-07-06

### Added

- Org-prefixed repo folders: repos newly added to the master workspace
are cloned into `<org>_<repo>` (Dart) / `<org>-<repo>` (TypeScript)
folders, so same-named repos from different organizations can coexist.
Existing unprefixed folders keep working: `do add`, `do rm`, ticket
copies and transitive-dep cloning now resolve repos by folder name,
manifest package name or git remote URL (`RepoFolderResolver`).
- `do add <name>` now tries the known organizations from `.organizations`
first and uses the bare `<name>/<name>` guess only as a last resort, so
a plain add clones straight from the right org without a failed attempt.
- `can publish` now runs `gg can publish` for every repo in the ticket
(feature branch, CHANGELOG, pana, npm authentication), so publish
blockers — like a missing npm login for an npm-published package —
surface up front instead of as a cryptic 404 mid-publish.

### Changed

- feat: clone whole GitHub org via gg do add - recognize /orgs/<org> URLs and list org repos authenticated through the GitHub CLI so private orgs work

### Fixed

- fix(org-add): handle missing GitHub CLI gracefully and fall back to https clone url when sshUrl is empty (code-review)
- `do review` (and therefore `do publish`) now disables pnpm 11's
`blockExoticSubdeps` while refreshing dependencies, so the transitive
git-referenced dependency chain that localizing to git feature branches
creates installs instead of failing with `ERR_PNPM_EXOTIC_SUBDEP`. This
matches the fix `do publish` already applied to its own refresh step.
- `do review` now surfaces a failed install's output from stdout when
stderr is empty (pnpm writes its errors to stdout), instead of throwing
the cause-less `... (pnpm install failed: )`.

### Reverted

- Revert parallelization of `gg can commit` and `gg do push` (commit
c97a31a). Restores the previous sequential implementation.

## 5.3.2 - 2026-06-26

### Changed

- Preserve dependency constraint operator (^^/~/exact) through publish
- gg_multi: changed references to git

## 5.3.1 - 2026-06-25

### Changed

- gg_multi: changed references to git

### Fixed

- Revert org-prefixed repo folders (ticket org_prefix_folders); keep gg_cross_language_deps

## 5.3.0 - 2026-06-19

### Changed

- Build dependency graph across Dart and TypeScript bridge repos
- Treat dart-typescript bridge repos as TypeScript for can/do review (npm install, skip dart pub get); export isBridgeProject from gg_one
- Introduce checkProjectType() as single source of truth for bridge->TypeScript check rule; add .example() real-instance factories & P:\programs\flutter/bin/internal/exit_with_errorlevel.bat
- Treat bridge repos as both Dart and TypeScript in do add-deps: getManifestDependenciesFromWorkspace now unions both manifests, tagging each dependency with its registry (pub.dev vs npm) so a bridge's deps are cloned from the correct source
- Publish bridges as TypeScript: pnpm-aware publish, dual-manifest version bump, non-swallowed publish errors, idempotent resume, review skips merged repos, link: for local TS deps, package.json scripts check
- gg_multi: changed references to git

### Fixed

- Fix bridge handling: cancel_review now runs npm install for bridges (symmetric to do/review); repo_folder_resolver names bridge clone folders TypeScript-style (hyphen) via checkProjectType
- Fix non-destructive sorted processing order (no longer mutates live Node.dependencies); make do/publish dependency refresh treat bridges as TypeScript via checkProjectType, symmetric with do/review and do/cancel_review
- Review fixes: keep full npm-scoped names in the dependency graph so different scopes stay distinct (no false duplicate-drop / misrouted edges); surface bridges in gg ls (dart+nodejs label, list package.json deps as typescript)

## 5.2.0 - 2026-06-11

### Changed

- gg_multi: changed references to git

## 5.1.0 - 2026-06-09

### Changed

- feat(ts): version-pinned git deps via #semver: + tag-push for npm/pnpm
- gg_multi: changed references to git
- refactor(ts): trim comments to grace-cloud style limits + do_maintain layout
- style: apply grace-cloud comment + 80-char limits across ticket
- gg_multi: changed references to git

## 5.0.0 - 2026-06-08

### Changed

- feat(do review): integrate the remote feature branch before pushing to avoid non-fast-forward rejections; on a real rebase conflict it aborts cleanly and fails with an actionable message (never force-pushes)
- feat(do review): after merging origin/main, re-run 'gg can commit' for any repo whose HEAD moved, to catch merges that silently corrupt a manifest (e.g. duplicate keys) before localizing/committing/pushing; aborts early with a clear message
- feat(do add): auto-clone transitive deps into master before graph build & P:\programs\flutter/bin/internal/exit_with_errorlevel.bat
- gg_multi: changed references to git
- feat(do_publish): default askBeforePublishing=false in multi-publish for non-interactive runs
- gg_multi: changed references to git
- gg_multi: changed references to git

### Fixed

- feat: language-aware add/publish via gg_lang (NpmRegistryChecker + RegistryWaiter, manifest-name resolution for scoped packages); exclude fixture sub-packages from analysis and load them via relative imports
- fix(do review): surface the exact failing step and underlying cause instead of only 'Failed to review in: <repo>' — errors now always log through the real output (not the quiet task log) and the thrown exception names the step (merge/can-review/localize/refresh/commit/push) plus the cause
- fix(filesystem_utils): skip node_modules during recursive copy to preserve pnpm symlink graph in TS ticket repos

## 4.5.2 - 2026-05-31

### Changed

- can review fuehrt vor dem Uncommitted-Check dart pub get --offline aus (analog gg_one can commit, mit Status-Printer)

## 4.5.1 - 2026-05-31

### Changed

- Revertiere die Parallelisierung von 'gg can commit' und 'gg do push' (Commit c97a31a). Die vorherige sequentielle Implementierung wird wiederhergestellt.
- Update gg metadata files for revert branch

## 4.5.0 - 2026-05-20

## 4.4.0 - 2026-05-19

### Changed

- gg_multi: changed references to git

## 4.3.1 - 2026-05-19

### Changed

- gg_multi: changed references to git

## 4.3.0 - 2026-05-17

### Changed

- parallelization
- documentation

## 4.2.0 - 2026-05-12

## 4.1.0 - 2026-05-12

### Changed

- gg_multi: changed references to git

## 4.0.1 - 2026-05-11

### Changed

- gg_multi: changed references to git
- Gg Multi: changed references to pub.dev
- **BREAKING**: Renamed package from `kidney_core` to `gg_multi`.
Repository moved to https://github.com/ggsuite/gg_multi. Update
`dependencies:` entries and `import 'package:kidney_core/...'`
statements to `import 'package:gg_multi/...'`. The executable is now
`gg_multi` (previously `kidney_core`).
- **BREAKING**: Replaced dependency `gg ^7.0.5` with `gg_one ^8.0.0`
(the `gg` package itself was renamed to `gg_one` upstream).
- Renamed status marker file `.kidney_status` to `.gg_multi_status`.
Existing checked-out workspaces must rename the file or run the
localization commands again.
- Upgrade gg_localize_refs version

### Removed

- remove unlocalize step from do review command and tests

## 3.1.0 - 2026-05-04

### Added

- Add TypeScript support to do review and do cancel-review

## 3.0.4 - 2026-04-29

## 3.0.3 - 2026-04-28

### Fixed

- Refactor _prepareMasterRepositoryForCopy and fix git tag deletion on macOS

## 3.0.2 - 2026-04-28

### Changed

- check in kidney_core can review, dass kein repo im main branch ist
- Execute dart pub get after changing of pubspec.yaml in kidney_core do publish

## 3.0.1 - 2026-04-24

## 3.0.0 - 2026-04-23

### Changed

- Change Confirm dialogs to Select dialogs

### Removed

- Remove --force option in do publish

## 2.8.1 - 2026-04-15

## 2.8.0 - 2026-04-14

### Added

- Add command do claude

## 2.7.2 - 2026-04-13

## 2.7.1 - 2026-04-08

### Changed

- Run do push before can publish in DoPublishCommand workflow

## 2.7.0 - 2026-04-08

### Added

- Add test for quiet taskLog behavior when verbose is false

### Changed

- kidney: changed references to local
- Run merge main into feat for all repos in ticket during publish
- Swap order of can merge and do push in can publish flow

## 2.6.0 - 2026-04-07

### Added

- Add gg merge main into feat step to can publish command

## 2.5.0 - 2026-04-01

## 2.4.2 - 2026-03-31

## 2.4.1 - 2026-03-30

## 2.4.0 - 2026-03-30

## 2.3.1 - 2026-03-30

## 2.3.0 - 2026-03-30

## 2.2.9 - 2026-03-30

## 2.2.8 - 2026-03-30

## 2.2.7 - 2026-03-30

## 2.2.6 - 2026-03-29

## 2.2.5 - 2026-03-29

## 2.2.4 - 2026-03-29

## 2.2.3 - 2026-03-29

## 2.2.2 - 2026-03-27

### Changed

- new gg version

## 2.2.1 - 2026-03-27

### Changed

- increase gg version

## 2.2.0 - 2026-03-27

### Changed

- Run git and dart commands in shell for add command and tests
- Kidney: changed references to pub.dev
- Upgrade gg_localize_refs version
- Run git commands always in shell

### Removed

- remove unlocalize step from do review command and tests

## 2.1.0 - 2026-03-27

### Added

- Add did commit and did push

### Changed

- run git reset when adding repo to ticket
- Run did commit in can publish

## 2.0.1 - 2026-03-26

### Changed

- kidney: changed references to path
- kidney: changed references to git

### Fixed

- small fixes in tests and version upgrades

## 2.0.0 - 2026-03-26

### Changed

- Upgraded gg to 6.0.1

## 1.1.0 - 2026-03-26

### Removed

- Move add, remove, code, create, init, add_deps to do/ directory and update imports

## 1.0.0 - 2026-03-24

### Added

- Initial boilerplate.
- Add readme
- Add tests
- Add --force parameter to add
- Add console colors
- Add console colors in remove command
- Add init command
- Add tests for create ticket
- Add function defaultKidneyWorkspacePath
- Add force flag correctly to AddCommand
- Add command kidney_core list tickets
- add support in add command for multiple repos
- Add constants.dart and change master folder to .master
- Add tests for creation of .organizations
- Add test: logs error when primary and all fallback organization clones fail
- Add tests for command add organization
- add tests for url parser
- Add tests for azure urls
- Add tests for can publish
- Add do execute command
- add tests for kidney add
- add tests for do publish
- Add VS Code workspace file generation to kidney add command
- Add test for kidney_core can review command failure handling
- add tests for quiet taskLog behavior when verbose is false

### Changed

- Ignore dart dependencies in add-deps
- Log messages start with upper case
- Update Readme
- execute list repos, list organizations and create ticket always in kidney workspace
- Error if ticket already exists
- Successfully open VSCode on Windows
- Rename GitCloner to GitHandler
- restructure code in review command
- code command does not require argument if executed in ticket directory
- change to relative path outputs in log
- suggest cd command to user when new ticket created
- change parameter projectName to project_name in .organizations json file
- extractOrganizationFromUrl works with azure dev ops urls
- extract repo name of azure dev ops urls correctly
- Write kidney_status file
- Abort directly if a command fails in do review
- Execute gg do commit after localizing in kidney add
- Pass gitRef param to _localizeRefs.get in DoReviewCommand and tests
- open ticket as VSCode workspace file instead of individual repos
- Switch gg_localize_refs dependency to use GitHub repo
- Update integration test and add sample folder metadata files
- Update .gg.json with new canCommit success hash value
- Refactor install_git_hooks to simplify error handling logic
- Enforce pre-push commit checks only on main/master branches
- log git and pub commands with darkGray instead of green
- Refactor Node to use manifest field instead of pubspec in tests
- Switch gg_localize_refs dependency from path to git URL
- Update gg_publish to version 3.2.0 in pubspec.yaml
- Update gg and related deps to latest pub versions in pubspec.yaml
- Update version and repository URL in pubspec.yaml
- Update canCheckout hash in .gg.json to match other actions

### Removed

- remove trailing # and / in organization urls
- remove command works also for tickets
- Remove redundant code in appendOrganization
- Remove prints
- Remove gh pr create from review
