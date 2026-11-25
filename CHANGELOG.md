# Changelog

All notable changes to MiaoRight are documented in this file.

The format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/). 简体中文版见 [CHANGELOG.zh-CN.md](CHANGELOG.zh-CN.md)。

## [Unreleased]

### Changed

- The repository is now public and distributed under the MIT License.
- Public releases support automatic update checks and in-place installation without GitHub authentication.

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

[Unreleased]: https://github.com/legjs/MiaoRight/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/legjs/MiaoRight/releases/tag/v0.1.2
