# Kidney Core

Kidney Core is the heart of the Kidney Suite. It provides a backend
service and a command line interface for managing repositories,
organizations, and dependencies of your projects.

## Overview

Kidney Core allows you to add
repositories, list repositories, and display project dependencies.

## Installation

1. Clone the repository:

   ```bash
   git clone https://github.com/ggsuite/kidney_core.git
   ```

2. Navigate to the project directory:

   ```bash
   cd kidney_core
   ```

3. Install Kidney Core:

   ```bash
   install.bat
   ```

## Available Commands

After installation, you can use the following commands:

- kidney_core add <target>
    Adds a repository or all repositories from the specified
    organization into the master workspace.

- kidney_core list
    Lists available items. Additionally, you can use one of these
    subcommands:

  - kidney_core list repos
      Lists all repositories in the master workspace.

  - kidney_core list organizations
      Lists all organizations from the repositories in the master
      workspace.

  - kidney_core list deps
      Lists dependencies and dev_dependencies from the current
      project.
