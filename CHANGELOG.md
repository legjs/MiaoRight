# Changelog

All notable changes to MiaoRight are documented in this file.

The format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/). 简体中文版见 [CHANGELOG.zh-CN.md](CHANGELOG.zh-CN.md)。

## [Unreleased]

### Fixed

- Fixed the settings window opening automatically right after an in-place update relaunch; the app now restarts silently into the menu bar.

## [0.1.6] - 2026-11-27

### Fixed

- Fixed the settings window opening automatically right after an in-place update relaunch; the app now restarts silently into the menu bar.

## [0.1.5] - 2026-11-27

### Added

- The update dialog shows live download progress with a percentage and a progress bar, mirrored in the menu bar item.
- The update dialog can switch release notes between Chinese and English.

### Changed

- Later cancels an ongoing update download; once the package is ready, closing the dialog explains the update continues and MiaoRight relaunches automatically.

## [0.1.4] - 2026-11-27

### Added

- Added a live update status to the menu bar icon menu for checking, up-to-date, failure, and available-update states.
- The menu bar can install an available release directly and offers a separate release-notes shortcut.

### Changed

- Manual update checks now show a dedicated dialog with release notes and an update button; checks with no update show an up-to-date alert.
- The app now launches silently without opening the settings window; the settings window appears only when explicitly requested from the menu bar or Dock.
- The menu bar update action opens the update dialog directly instead of the settings window, and release notes appear only in the dialog.

### Removed

- Removed manual ZIP selection from the app update page. Updates always download the matching release asset.
- Removed the development-only update simulation switch and the local debug update package helper.

## [0.1.3] - 2026-11-25

### Added

- MiaoRight is now distributed as an open-source project under the MIT License.
- Public GitHub Releases support one-click update checks and in-place installation without GitHub authentication.
- Added a three-step installation guide and an in-app first-run checklist.

### Changed

- Updates can replace `/Applications/MiaoRight.app` from either a downloaded or user-selected ZIP after version, architecture, nested-extension, and certificate validation.
- The release pipeline builds arm64 natively and cross-compiles x86_64 on one Apple silicon runner.
- Added the MIT copyright notice to the app's General page, README files, and website footer.
- MIT copyright information now includes MiaoRight contributors and appears in the app and on the website.

### Fixed

- Fixed unreadable release-note text in dark mode.
- Improved Finder extension status feedback and removed duplicate settings-window creation.
- Added an Atom release-feed fallback so update checks continue when the GitHub API is rate-limited.
- Ensured the main window is created after cold launch and after update relaunch.

### Security

- Update packages must be signed by the stable MiaoRight Release identity before replacement.

## [0.1.2] - 2026-11-25

### Added

- Added DMG installers for Apple silicon and Intel Macs, including an Applications shortcut and installation instructions.
- Added a three-step installation guide and a first-run checklist in General settings.
- Added production update installation from a matching ZIP or a user-selected ZIP.

### Changed

- Production builds now replace `/Applications/MiaoRight.app` in place after validating the version, architecture, nested extensions, and release certificate.
- Finder extension checks now report ready, waiting to load, and disabled states clearly.
- Development and production distributions now use separate stable signing identities.
- The first switch from a development-signed build to the production release identity requires confirming system permissions and the login item again.

### Fixed

- Fixed the settings action potentially opening duplicate settings windows.
- Corrected the local macOS 26 workflow for Finder extensions that do not load when launched from a build directory.

[Unreleased]: https://github.com/legjs/MiaoRight/compare/v0.1.3...HEAD
[0.1.3]: https://github.com/legjs/MiaoRight/releases/tag/v0.1.3
[0.1.2]: https://github.com/legjs/MiaoRight/releases/tag/v0.1.2
