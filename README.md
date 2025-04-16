# Kidney Core

Kidney Core is the heart of the Kidney Suite. It provides both a 
backend service and a command line interface for managing 
repositories, organizations, and dependencies of your projects.

## Overview

Kidney Core allows you to:
- Add repositories or all repositories from an organization into 
the master workspace.
- List repositories, organizations, and dependencies from projects 
in the master workspace.
- Run various commands to interact with different parts of your 
  project.

## Available Commands

After installation, you can use the following commands:

- `kidney_core add <target>`
  - Adds a repository or all repositories from the specified 
    organization into the master workspace.

- `kidney_core list`
  - Lists available items. You can use one of these 
    subcommands:
    - `kidney_core list repos`
        - Lists all repositories in the master workspace. It sorts the
          repositories by name.
    - `kidney_core list organizations`
        - Lists all organizations from the repositories in the master 
          workspace. Organizations whose name is unknown are skipped or 
          marked as "unknown".
    - `kidney_core list deps <target>`
        - Lists dependencies and dev_dependencies from the specified 
          project in the master workspace.

- `kidney_core add-deps <target>`
  - Iterates over all dependencies (both `dependencies` and 
    `dev_dependencies`) specified in a project's `pubspec.yaml` and 
    adds each dependency as a cloned repository.

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
   install.bat
   ```

## Running Tests

Kidney Core is fully tested with nearly 100% coverage. To run the 
tests, use:

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
- For state management, Riverpod is used whenever necessary.
- The codebase follows modern Dart best practices, including extensive 
  testing and error handling.
- Contributions are welcome. Please ensure that new features are accompanied 
  by relevant tests and updated documentation.

## License

Kidney Core is licensed under the terms specified in the LICENSE file.
