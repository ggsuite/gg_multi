# Kidney Core

Kidney Core is the heart of the Kidney Suite. It provides both a 
backend service and a command line interface for managing 
workspaces, repositories, organizations, tickets, and dependencies of your projects.

## Overview

Kidney Core allows you to:
- Initialize and manage a master workspace.
- Add and remove repositories or entire organizations into or from the master workspace.
- Create and manage ticket workspaces under `./tickets/<ticket_id>`.
- List repositories, organizations, and dependencies of projects in the master workspace.
- Add pubspec dependencies to your workspace automatically.

## Available Commands

After installation, you can use the following commands:

- `kidney_core init`
  - Initializes the master workspace in the project root.

- `kidney_core add <target> [-f|--force]`
  - Adds a repository or all repositories from the specified organization into the master workspace.
  - When run inside a ticket workspace (e.g. `./tickets/<id>`), also copies the repository into that ticket folder.
  - Use `--force` (`-f`) to re-clone even if the repository already exists in the master workspace.

- `kidney_core remove <target>`
  - Deletes a repository or ticket folder.
    - If `<target>` corresponds to a ticket ID, deletes the entire ticket workspace under `./tickets/<id>`.
    - If `<target>` is a repository name that exists only in the master workspace, removes it from the master workspace.
    - If the repository is used in feature branches (`kidney_ws_*`), lists those branches and asks you to remove them first.

- `kidney_core list [repos|organizations|deps <target>]`
  - `repos`: Lists all repositories in the master workspace, sorted by name.
  - `organizations`: Lists all GitHub organizations represented by repositories in the master workspace.
  - `deps <target>`: Lists `dependencies` and `dev_dependencies` of the given project in the master workspace.

- `kidney_core add-deps <target>`
  - Iterates over all `dependencies` and `dev_dependencies` specified in the project's `pubspec.yaml` and adds each dependency to the master workspace.
  - Automatically skips Dart SDK packages hosted under `dart-lang`.

- `kidney_core create ticket <id> [-m|--message <description>]`
  - Creates a ticket folder under `./tickets/<id>` and writes a `.ticket` file in JSON format with the issue ID and optional description.

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/ggsuite/kidney_core.git
   ```

2. Navigate to the project directory:
   ```bash
   cd kidney_core
   ```

3. Install Kidney Core by running the installation script:
   ```bash
   install.bat  # or ./install
   ```

## Running Tests

Kidney Core is fully tested with nearly 100% coverage. To run the tests, use:

```bash
dart test
```

You can also generate a coverage report with:

```bash
dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info
```

## Additional Information

- The project is structured for modular development with clear 
  separation between the CLI commands and backend logic.
- The codebase follows modern Dart best practices, including extensive 
  testing and error handling.
- Contributions are welcome. Please ensure that new features are accompanied 
  by relevant tests and updated documentation.

## License

Kidney Core is licensed under the terms specified in the LICENSE file.
