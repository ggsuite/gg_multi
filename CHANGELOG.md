# Changelog

## Unreleased

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
- Add command kidney\_core list tickets
- add support in add command for multiple repos
- Add constants.dart and change master folder to .master
- Add tests for creation of .organizations
- Add test: logs error when primary and all fallback organization clones fail
- Add tests for command add organization

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
- change parameter projectName to project\_name in .organizations json file

### Removed

- remove trailing # and / in organization urls
- remove command works also for tickets
