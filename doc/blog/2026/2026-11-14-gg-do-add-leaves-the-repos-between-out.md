<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# gg do add leaves the repos between out

## Motivation

- The README of the tool family explains how a ticket gets its repos.
  Its section »Lean tickets« described `gg do add` as adding the repos
  *between* the ticket repos by default, with `~/.gg_rc` as the way to
  turn that off
- gg_multi_workspace turned this around: `gg do add a c` adds only `a`
  and `c` now. The repos between are needed only when a release breaks
  its dependents, and they can be added exactly then
- The README has to tell the new story, and the command tree this package
  wires has to reach the new behavior

## Strategy

- Rewrite the section »Lean tickets« for the new default
- Change no code: `do add` is wired as before, with `GgRc.load` as its
  settings reader
- Take the newer sub-packages through the constraint upgrade of the push

## README

- `gg do add a c` adds only `a` and `c`; `--transitive` adds `b` for one
  run
- `{"do": {"add": {"transitive": true}}}` in `~/.gg_rc` adds the repos
  between with every `gg do add`
- `~/.gg_rc` is written with every default the first time `gg do add`
  runs and is not rewritten afterwards — unless it still holds exactly
  what an older gg wrote there; then gg writes the new defaults into it
- Without the setting the repos between are added when needed:
  `gg do add transitive for <repo>` or `gg do add transitive`
- `gg do review` still adds them by itself when the plan gives a repo a
  breaking increment

## Dependency updates

- The push upgraded the constraints to the newest sub-packages, among
  them `gg_multi_core: ^4.20.0`, `gg_multi_commit: ^4.11.0`,
  `gg_multi_do_publish: ^4.8.0` and `gg_multi_workspace: ^4.25.0`
- gg_multi_workspace: `gg do add` takes the default of `do.add.transitive`
  from the settings and logs `Skip adding transitive repos (default)` when
  it leaves the repos between out
- gg_one_core: the built-in default of `do.add.transitive` is `false`; an
  untouched `~/.gg_rc` of an older gg gets the new defaults
- Both arrive with the next resolve: the constraints already admit the
  versions that carry them
- The upgrade also wrote the repository settings `.gg/gg_rc` with their
  defaults and keeps it tracked

## Open Points

- The constraints do not require the versions with the new default yet;
  a lock file from before keeps adding the repos between until the next
  upgrade
