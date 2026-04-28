# Changelog

## \[Unreleased\]

### Changed

- Upgrade gg\_localize\_refs version

### Removed

- remove unlocalize step from do review command and tests

## [3.0.3] - 2026-04-28

### Fixed

- Refactor \_prepareMasterRepositoryForCopy and fix git tag deletion on macOS

## [3.0.2] - 2026-04-28

### Changed

- check in kidney\_core can review, dass kein repo im main branch ist
- Execute dart pub get after changing of pubspec.yaml in kidney\_core do publish

## [3.0.1] - 2026-04-24

## [3.0.0] - 2026-04-23

### Changed

- Change Confirm dialogs to Select dialogs

### Removed

- Remove --force option in do publish

## [2.8.1] - 2026-04-15

## [2.8.0] - 2026-04-14

### Added

- Add command do claude

## [2.7.2] - 2026-04-13

## [2.7.1] - 2026-04-08

### Changed

- Run do push before can publish in DoPublishCommand workflow

## [2.7.0] - 2026-04-08

### Added

- Add test for quiet taskLog behavior when verbose is false

### Changed

- kidney: changed references to local
- Run merge main into feat for all repos in ticket during publish
- Swap order of can merge and do push in can publish flow

## [2.6.0] - 2026-04-07

### Added

- Add gg merge main into feat step to can publish command

## [2.5.0] - 2026-04-01

## [2.4.2] - 2026-03-31

## [2.4.1] - 2026-03-30

## [2.4.0] - 2026-03-30

## [2.3.1] - 2026-03-30

## [2.3.0] - 2026-03-30

## [2.2.9] - 2026-03-30

## [2.2.8] - 2026-03-30

## [2.2.7] - 2026-03-30

## [2.2.6] - 2026-03-29

## [2.2.5] - 2026-03-29

## [2.2.4] - 2026-03-29

## [2.2.3] - 2026-03-29

## [2.2.2] - 2026-03-27

### Changed

- new gg version

## [2.2.1] - 2026-03-27

### Changed

- increase gg version

## [2.2.0] - 2026-03-27

### Changed

- Run git and dart commands in shell for add command and tests
- Kidney: changed references to pub.dev
- Upgrade gg\_localize\_refs version
- Run git commands always in shell

### Removed

- remove unlocalize step from do review command and tests

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

[3.0.3]: https://github.com/ggsuite/kidney_core/compare/3.0.2...3.0.3
[3.0.2]: https://github.com/ggsuite/kidney_core/compare/3.0.1...3.0.2
[3.0.1]: https://github.com/ggsuite/kidney_core/compare/3.0.0...3.0.1
[3.0.0]: https://github.com/ggsuite/kidney_core/compare/2.8.1...3.0.0
[2.8.1]: https://github.com/ggsuite/kidney_core/compare/2.8.0...2.8.1
[2.8.0]: https://github.com/ggsuite/kidney_core/compare/2.7.2...2.8.0
[2.7.2]: https://github.com/ggsuite/kidney_core/compare/2.7.1...2.7.2
[2.7.1]: https://github.com/ggsuite/kidney_core/compare/2.7.0...2.7.1
[2.7.0]: https://github.com/ggsuite/kidney_core/compare/2.6.0...2.7.0
[2.6.0]: https://github.com/ggsuite/kidney_core/compare/2.5.0...2.6.0
[2.5.0]: https://github.com/ggsuite/kidney_core/compare/2.4.2...2.5.0
[2.4.2]: https://github.com/ggsuite/kidney_core/compare/2.4.1...2.4.2
[2.4.1]: https://github.com/ggsuite/kidney_core/compare/2.4.0...2.4.1
[2.4.0]: https://github.com/ggsuite/kidney_core/compare/2.3.1...2.4.0
[2.3.1]: https://github.com/ggsuite/kidney_core/compare/2.3.0...2.3.1
[2.3.0]: https://github.com/ggsuite/kidney_core/compare/2.2.9...2.3.0
[2.2.9]: https://github.com/ggsuite/kidney_core/compare/2.2.8...2.2.9
[2.2.8]: https://github.com/ggsuite/kidney_core/compare/2.2.7...2.2.8
[2.2.7]: https://github.com/ggsuite/kidney_core/compare/2.2.6...2.2.7
[2.2.6]: https://github.com/ggsuite/kidney_core/compare/2.2.5...2.2.6
[2.2.5]: https://github.com/ggsuite/kidney_core/compare/2.2.4...2.2.5
[2.2.4]: https://github.com/ggsuite/kidney_core/compare/2.2.3...2.2.4
[2.2.3]: https://github.com/ggsuite/kidney_core/compare/2.2.2...2.2.3
[2.2.2]: https://github.com/ggsuite/kidney_core/compare/2.2.1...2.2.2
[2.2.1]: https://github.com/ggsuite/kidney_core/compare/2.2.0...2.2.1
[2.2.0]: https://github.com/ggsuite/kidney_core/compare/2.1.0...2.2.0
[2.1.0]: https://github.com/ggsuite/kidney_core/compare/2.0.1...2.1.0
[2.0.1]: https://github.com/ggsuite/kidney_core/compare/2.0.0...2.0.1
[2.0.0]: https://github.com/ggsuite/kidney_core/compare/1.1.0...2.0.0
[1.1.0]: https://github.com/ggsuite/kidney_core/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/ggsuite/kidney_core/tag/%tag
