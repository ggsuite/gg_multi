# Changelog

## [2.1.0] - 2026-03-27

### Added

- Add did commit and did push

### Changed

- run git reset when adding repo to ticket
- Run did commit in can publish

## [2.0.1] - 2026-03-26

### Changed

- kidney: changed references to path
- kidney: changed references to git

### Fixed

- small fixes in tests and version upgrades

## [2.0.0] - 2026-03-26

### Changed

- Upgraded gg to 6.0.1

## [1.1.0] - 2026-03-26

### Removed

- Move add, remove, code, create, init, add\_deps to do/ directory and update imports

## [1.0.0] - 2026-03-24

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
- add tests for do publish
- Add VS Code workspace file generation to kidney add command
- Add test for kidney\_core can review command failure handling
- add tests for quiet taskLog behavior when verbose is false

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
- Pass gitRef param to \_localizeRefs.get in DoReviewCommand and tests
- open ticket as VSCode workspace file instead of individual repos
- Switch gg\_localize\_refs dependency to use GitHub repo
- Update integration test and add sample folder metadata files
- Update .gg.json with new canCommit success hash value
- Refactor install\_git\_hooks to simplify error handling logic
- Enforce pre-push commit checks only on main/master branches
- log git and pub commands with darkGray instead of green
- Refactor Node to use manifest field instead of pubspec in tests
- Switch gg\_localize\_refs dependency from path to git URL
- Update gg\_publish to version 3.2.0 in pubspec.yaml
- Update gg and related deps to latest pub versions in pubspec.yaml
- Update version and repository URL in pubspec.yaml
- Update canCheckout hash in .gg.json to match other actions

### Removed

- remove trailing # and / in organization urls
- remove command works also for tickets
- Remove redundant code in appendOrganization
- Remove prints
- Remove gh pr create from review

[2.1.0]: https://github.com/ggsuite/kidney_core/compare/2.0.1...2.1.0
[2.0.1]: https://github.com/ggsuite/kidney_core/compare/2.0.0...2.0.1
[2.0.0]: https://github.com/ggsuite/kidney_core/compare/1.1.0...2.0.0
[1.1.0]: https://github.com/ggsuite/kidney_core/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/ggsuite/kidney_core/tag/%tag
