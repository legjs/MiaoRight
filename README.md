# MiaoRight

English · [简体中文](README.zh-CN.md) · [Website](https://legjs.github.io/MiaoRight/)

MiaoRight is a lightweight Finder and clipboard utility for Apple silicon and Intel Macs running macOS 14 or later. Use Finder’s context menu to open, move, and organize files, and use the clipboard panel to find, paste, or save items you copied earlier.

The app uses SwiftUI and AppKit with native Finder Sync and Quick Look extensions. It supports English and Simplified Chinese and can follow the system language. Appearance can follow the system or use Light or Dark mode.

## Build and get started

Use the Xcode Command Line Tools with Swift 6.3 to build and launch the app.

```bash
./scripts/build-app.sh release
open build/MiaoRight.app
```

For the fastest local test loop, run `./scripts/dev.sh release`. It quits the running app normally, rebuilds the Release bundle, updates the development-signed test app in `/Applications/MiaoRight.app`, refreshes its Finder Sync registration, and opens it again. On macOS 26, launching from the build directory can register the Finder extension without actually loading it.

The script builds and signs the app, the Finder Sync and Quick Look extensions, and the bundled 7-Zip helper. It uses the local `MiaoRight dev` signing identity when available and falls back to ad-hoc signing. Launch the app with `open` so LaunchServices registers its extensions. See the [development signing guide](MACOS_DEV_SIGNING.md) for setup.

The build defaults to your Mac’s architecture. For a release, choose the `arm64` DMG for Apple silicon or the `x86_64` DMG for Intel. GitHub Actions also publishes ZIP packages for in-app updates, signs both architectures with the stable `MiaoRight Release` identity, and includes a SHA-256 checksum file. The release workflow requires the signing identity through Actions Secrets and fails instead of publishing an ad-hoc build. [Release workflow guide](docs/GitHub-更新发布.md)

- **Finder actions.** In System Settings, enable MiaoRight under **Login Items & Extensions → Finder Extensions**. MiaoRight’s main window offers an **Open System Settings** shortcut when the extension is disabled.
- **Clipboard history.** On first use, turn on **Clipboard → Record Clipboard History**. Copy an item and press `⇧⌘V` to open the panel.
- **Preferences.** The four tabs in the main window are **Context Menu**, **Clipboard**, **Vault**, and **General**. In General you can change the interface language and appearance, choose where Finder actions appear, and configure **Launch at Login**.

## Clipboard history

| Action | How to use it |
| --- | --- |
| Find a record | Open the panel with `⇧⌘V`. Search copied text or the displayed file name, or type a word you remember seeing in a screenshot. The app recognizes text in recorded images on your Mac. |
| Save a record | Choose **… → Save…** on any record. Text and links become UTF-8 TXT files, images become PNGs, and files and folders are copied to a folder you choose. Original files must still be accessible. Name conflicts during file copies get a numbered suffix. |
| Paste the second-most-recent item | Press `⌃⇧⌘V` by default. For example, copy a title and then a link. Use the shortcut to paste the title, then use `⌘V` to paste the link. Both global shortcuts can be changed in Clipboard settings. |
| Keep useful items | Mark a record as a favorite or save frequently used text in Clipboard settings. Favorites survive expiration, item limits, and **Clear Unfavorited History**. |

The panel supports keyboard navigation, number shortcuts, multiple selection, filtering, and pinning. Automatic pasting, including the shortcut for the second-most-recent item, needs Accessibility permission. The panel can also copy a selected item for you to paste with `⌘V`.

History stays on your Mac. In Clipboard settings you can pause recording, choose a retention period, and set an item limit. Closing the panel leaves recording active. The current recorder caps text at 10,000 characters per item and skips images larger than 5 MB.

## Finder actions

- **Copy File Path** copies the full path of a selected file or folder.
- **Open with App** uses apps you choose in the Context Menu tab. You can also drag apps into the list. **Open in Terminal** uses an installed terminal and opens the enclosing folder when you select a file.
- **Cut** marks files for a move. Use **Paste Here** in the destination folder. If the move cannot finish, any pending items stay available to retry.
- **Favorite Folders** lets you open, copy to, or move to your usual folders. **File Templates** stores a snapshot that you can use to create a new file in the destination folder.
- Open **Context Menu → Add Action** for optional tools such as **Batch Rename…**, image conversion, PDF operations, and checksums. Batch Rename previews the new names and checks for conflicts before applying them.

The result view can reveal output files in Finder. During the current app session, eligible moves and renames can be undone if their original paths are free and the items still match the recorded file information.

## Archives

- **Preview an archive in Finder.** Select an archive in Finder and press Space or choose View → Show Preview (⇧⌘P). MiaoRight’s read-only Quick Look preview extension shows a directory tree, sizes, available modification dates, and totals in Finder’s system preview. There is no archive preview command or hotkey inside the MiaoRight app. Supported formats include ZIP, 7Z, RAR, TAR, common compressed TAR formats, GZ, BZ2, XZ, and CPIO. Large or encrypted archives may show partial or unavailable contents; use Extract Archive to enter a password for encrypted directories. If another previewer handles the file, check Quick Look extensions in System Settings.
- **Create an archive.** Enable **Compress…** under **Context Menu → Add Action → Compression and Extraction**. Choose ZIP, 7Z, or TAR.GZ. ZIP and 7Z support encryption. Use 7Z for passwords containing non-ASCII characters.
- **Extract an archive.** Enable **Extract Archive** in the same group. It recognizes ZIP, 7Z, RAR, TAR, GZ, BZ2, XZ, compressed TAR archives, and common multipart archives. Put all parts in the same folder and select the first part. Output goes to a new folder beside the archive. Use this action if an encrypted directory cannot be previewed.

Compression and extraction use the bundled 7-Zip helper for the app’s architecture and keep passwords in memory for the current operation. The Quick Look preview uses the system libarchive to read metadata. [Bundled 7-Zip](ThirdParty/7zip/README.md)

## Encrypted Vault

Open **Vault** to create a local AES-256 encrypted disk image. Add files from the Vault tab, or enable **Add to Vault** in **Context Menu → Add Action** and use it in Finder after creating the vault. Adding files moves them into the vault. **Extract…** copies an item out.

The vault locks when the Mac sleeps, when you quit MiaoRight, or after the configured idle period, which defaults to 15 minutes. You can opt to remember the password in the login Keychain. Keep the password somewhere safe. It is required to recover the vault contents.

## Development and verification

- Running XCTest requires full Xcode. See the [isolated test setup](AGENTS.md), [product context](PRODUCT.md), and [design system](DESIGN.md).
- Release history follows Keep a Changelog and Semantic Versioning in [CHANGELOG.md](CHANGELOG.md). The Simplified Chinese edition is [CHANGELOG.zh-CN.md](CHANGELOG.zh-CN.md).
- Development-signed builds expose **Debug: Simulate an Available Update** in **General → Software Update**. It treats the latest published release as available so you can test menu states, direct installation, and release notes without tagging a new version. Production-signed builds hide and clear the switch.
- **General → Software Update** checks public stable GitHub Releases once a day by default, or on demand. Automatic checks can be turned off, and the result is kept across launches. A copy at `/Applications/MiaoRight.app` can download the matching ZIP, verify its bundle ID, version, architecture, nested extensions, and fixed release certificate, then quit, replace that app in place, and relaunch. The menu bar icon also shows the live update state, installs an available release directly, and links to its release notes. See the [update-check setup](docs/GitHub-更新发布.md).
- The latest feature verification covered the Release build, deep signature validation, and 58 targeted offscreen tests for clipboard, archive, and menu behavior. The live Save dialog, Finder and Quick Look workflows, VoiceOver, and physical multi-display setups still need end-to-end verification. See the [earlier implementation notes](docs/日常功能补齐-执行记录.md) for historical test results.

## Credits and license

The Finder action catalog takes inspiration from iRightMouse.

Copyright © 2026 legjs and MiaoRight contributors. Released under the [MIT License](LICENSE). Third-party components retain their respective licenses.
