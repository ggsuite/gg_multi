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

Kidney Core is a multi-repository workspace management CLI for Dart/Flutter projects. It orchestrates actions (commit, push, publish, review) across all repos in a ticket workspace, resolving them in dependency order.

### Entry Point & Command Groups

```
bin/kidney_core.dart
  └─ KidneyCore (lib/src/kidney_core.dart)
       ├─ Can   – validate before acting (can commit, can push, can publish, can review)
       ├─ Do    – execute across all repos (do commit, do push, do review, do claude, …)
       ├─ Did   – report what happened (did commit, did push)
       └─ Ls    – list workspace contents (repos, organizations, deps)
```

Each command group lives in `lib/src/commands/kidney_can.dart`, `kidney_do.dart`, `kidney_did.dart`, and `ls.dart`. Subcommands are in `lib/src/commands/<group>/<name>.dart`.

### Workspace Hierarchy

The tool manages two levels of workspace:

- **Master workspace** (`<root>/.master/`) — contains all registered repositories and organizations.
- **Ticket workspace** (`<root>/tickets/<ticket-name>/`) — contains clones of repos scoped to a ticket.

`WorkspaceUtils.detectTicketPath()` (in `lib/src/backend/workspace_utils.dart`) navigates up the directory tree to locate which context the CLI is running in.

### Backend Modules (`lib/src/backend/`)

| Module | Role |
|--------|------|
| `workspace_utils.dart` | Detects master/ticket paths from any working directory |
| `git_handler.dart` | Clone, branch, and Git operations |
| `git_platform.dart` | GitHub API abstraction |
| `list_backend.dart` | Lists repos/orgs/deps with metadata |
| `add_repository_helper.dart` | Logic for adding repos to a workspace |
| `pub_dev_checker.dart` | Checks published versions on pub.dev |
| `constants.dart` | Directory name constants (`.master`, `tickets`) |

### `do claude` Command

`DoClaudeCommand` (in `lib/src/commands/do/claude.dart`) generates an aggregated `CLAUDE.md` at the ticket-workspace root. It:

1. Detects the ticket path via `WorkspaceUtils.detectTicketPath()`.
2. Resolves repos in dependency order with `SortedProcessingList` (from `gg_local_package_dependencies`).
3. Reads each repo's `CLAUDE.md` (throws with a helpful message if one is missing — the user must run `/init` in that repo first).
4. Writes a single `<ticket-dir>/CLAUDE.md` combining workspace overview, commands, per-repo architecture sections, and code standards.

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
