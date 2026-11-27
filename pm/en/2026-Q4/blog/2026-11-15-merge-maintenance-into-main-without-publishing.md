<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Document that gg do maintain merges without publishing

## Motivation

- `gg_multi_maintain` now merges every maintained repo into main and
  releases nothing

## Implementation

- README: `gg_multi do maintain` merges each changed repo into main
  without publishing
- README: new versions reach main through the nightly build; everything
  that is published goes through a normal ticket and its review

## Dependency updates

- `gg_multi_maintain`: merges with `gg one do publish --merge-only`;
  `--version-increment` and `--pana` are removed
