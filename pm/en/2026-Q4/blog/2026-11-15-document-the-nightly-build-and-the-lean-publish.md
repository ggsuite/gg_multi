<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Document the nightly build and the lean publish

## Motivation

- gg_multi wires the commands of its sub-packages into one command tree.
  Three of them change how dependencies are kept current:
  - `do push` (gg_multi_commit) no longer upgrades the dependencies
  - `do publish` (gg_multi_do_publish) resolves and analyzes instead of
    upgrading and testing again
  - `do maintain` (gg_multi_maintain) gains `--nightly`, the run that
    raises every dependency, major versions included, every night
- The README of the umbrella has to say so, and gg_multi has to use the
  gg_multi_maintain that brings `--nightly`

## Strategy

- Update the command table and the push section of the README
- Take the new gg_multi_maintain: the ticket references it locally, and its
  release raises the constraint

## README

- The row of `do maintain` lists `--nightly` and what it is
- Below the `do` table a paragraph says that neither `do push` nor
  `do publish` upgrades a dependency — `do push` only with `--upgrade` —
  and that new versions arrive through `do maintain --nightly`

## Dependency updates

- gg_multi_maintain: `--nightly` (`--upgrade-deps --major`) and a
  `report.txt` in the run folder when a repo failed. The old constraint
  `^0.0.2` allowed no newer release, so the publish raises it
- gg_multi_commit: `do push` upgrades only with `--upgrade`
- gg_multi_do_publish: a publish resolves and analyzes, it neither upgrades
  nor tests again
- gg_one: `gg one do publish` upgrades only with `--upgrade`; upgrades cross
  major versions only when a repository's `.gg/gg_rc` allows it

## Open Points

- None
