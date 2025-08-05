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
- add tests for url parser
- Add tests for azure urls
- Add tests for can publish
- Add do execute command
- add tests for kidney add

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
- extractOrganizationFromUrl works with azure dev ops urls
- extract repo name of azure dev ops urls correctly
- Write kidney\_status file
- Abort directly if a command fails in do review
- Execute gg do commit after localizing in kidney add

### Removed

- remove trailing # and / in organization urls
- remove command works also for tickets
- Remove redundant code in appendOrganization
- Remove prints
- Remove gh pr create from review
