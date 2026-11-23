# Bundled 7-Zip

- Upstream: Igor Pavlov, [7-Zip](https://www.7-zip.org/).
- Version: **26.06**, released 2026-11-06, macOS **arm64**.
- Official binary archive: <https://github.com/ip7z/7zip/releases/download/26.06/7z2606-mac.tar.xz>
- Matching source: <https://github.com/ip7z/7zip/releases/download/26.06/7z2606-src.tar.xz>
- Official downloads: <https://www.7-zip.org/download.html>
- Binary archive SHA-256: `b6f17920b4240940461dac8ef4009891881ac44d2a5ead625ede2ec8472185dd`.

`7zz` is the unmodified official standalone executable. It uses macOS system libraries and requires no Homebrew, Python or separate installation. The App build copies it to `Contents/Helpers/7zz` and applies the App's code signing identity. The original executable and source checksums are recorded in `SHA256SUMS` and checked before every App build. Signing the copied executable changes its checksum; the original remains unchanged.

`License.txt`, `COPYING.LGPL.txt` and `readme.txt` retain the upstream license, LGPL text, copyright and third-party notices. The complete corresponding source archive `7z2606-src.tar.xz` is included in this directory and in the built App under `Contents/Resources/ThirdParty/7zip/`, together with these notices. No 7-Zip source was modified. Source compilation instructions are in the archive's `DOC` directory. The 7-Zip component's license is independent of MiaoRight's license.

MiaoRight invokes this separate executable through a shared backend for ZIP, 7Z and TAR.GZ compression/extraction, legacy composed actions, and Excel/PowerPoint ZIP container creation. ZIP uses Deflate. TAR.GZ is processed in two stages (TAR and gzip), with the intermediate stream confined to a private temporary directory. No system zip, ditto or tar executable is used at runtime.

The generic extraction entry also handles RAR, TAR, gzip, bzip2, xz and their supported TAR wrappers. Common numbered ZIP/7Z and RAR volumes are normalized to the first volume; all parts must be available beside it. This does not imply every possible archive/volume variant was tested.

Passwords for ZIP/7Z compression and encrypted extraction are passed through stdin, never persisted or placed in command-line arguments. Compression uses AES-256 for encrypted ZIP and header encryption for 7Z; ZIP passwords must be ASCII, while 7Z supports Unicode. TAR.GZ compression does not offer encryption. All extraction actions use a new adjacent folder, with a unique name if necessary; failed attempts remain in a private temporary folder until cleaned up. Successful earlier results in a batch are retained and identified if a later archive fails. ZIP, TAR.GZ and TGZ interoperability with macOS system tools is covered by the archive regression tests.

To update: download both matching archives from the official release, verify the version and architecture, replace `7zz`, the source archive and upstream notices, update this document and `scripts/build-app.sh`'s source filename, regenerate `SHA256SUMS`, and run the archive regression tests and final App build/signature verification. Do not silently download a moving “latest” binary during normal builds.
