<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Require the sub-packages that compile together

## Motivation

- `lib/gg_multi.dart` re-exports the public API of its sub-packages in
  full: gg_multi_core, gg_multi_commit, gg_multi_do_publish and
  gg_multi_workspace. Their names all meet in one library.
- gg_multi_do_publish 4.7.1 and gg_multi_workspace 4.22.0 to 4.24.1 each
  declared a typedef `ReadSettings` of their own. The two were identical,
  but Dart counts them as two declarations, and this library stopped
  compiling:
  `'ReadSettings' is exported from both …`
- The constraints `gg_multi_do_publish: ^4.7.0` and
  `gg_multi_workspace: ^4.22.0` admitted exactly these versions. A fresh
  resolve picks the newest versions and is fine, but a lock file or a
  pinned resolve could still land on the broken pair.
- The sub-packages are fixed now: gg_multi_core 4.18.0 declares
  `ReadSettings` once, next to `GgRc`, and the others re-export that one.
  The constraints of this package should admit only versions from there
  on.

## Strategy

- Raise each constraint to the first sub-package version of the fix
- Raise gg_multi_commit and gg_multi_core along with them, so the four
  move together
- Change no code: the command tree and the re-exports stay as they are
- Prove that the broken pair no longer resolves

## Implementation

- `pubspec.yaml`:

  | Dependency            | Before    | After     |
  | --------------------- | --------- | --------- |
  | `gg_multi_core`       | `^4.15.0` | `^4.18.0` |
  | `gg_multi_commit`     | `^4.9.0`  | `^4.9.2`  |
  | `gg_multi_do_publish` | `^4.7.0`  | `^4.7.2`  |
  | `gg_multi_workspace`  | `^4.22.0` | `^4.24.2` |

- Asking for gg_multi_do_publish 4.7.1 together with this package now
  fails to resolve: `gg_multi_do_publish ^4.7.2 is required`
- `index.jsonc` is new: summary, domain and the interfaces of the
  package, with `ReadSettings` among what it re-exports from
  gg_multi_core

## Dependency updates

- gg_multi_core 4.18.0: `ReadSettings` is declared next to `GgRc` and
  exported from there, so it is part of this library's API as well
- gg_multi_do_publish 4.7.2 and gg_multi_workspace 4.24.2: no own
  `ReadSettings` any more; both re-export the one of gg_multi_core
- `gg_one`, `gg_publish`, `gg_status_printer` and `dna_ggsuite`:
  tightened to their current versions by the regular dependency upgrade

## Result

- Every version of this package from here on compiles with every
  resolution it allows
- Released as a patch version

## Open Points

- A user whose installed lock file still holds the broken pair keeps it
  until the package is resolved again
