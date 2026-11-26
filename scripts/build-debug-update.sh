#!/bin/bash
# Build a local v0.1.4 development-signed test package for the debug update switch.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.1.4"
BUILD="105"
OUT_DIR="$HOME/Library/Application Support/MiaoRight/DebugUpdate"
WORK="$(mktemp -d /tmp/MiaoRightDebugUpdate.XXXXXX)"
BACKUP="$WORK/plists"
mkdir -p "$BACKUP" "$OUT_DIR"
cp Packaging/Info-App.plist Packaging/Info-FinderSync.plist Packaging/Info-ArchivePreview.plist "$BACKUP/"

restore() {
  cp "$BACKUP/Info-App.plist" Packaging/Info-App.plist
  cp "$BACKUP/Info-FinderSync.plist" Packaging/Info-FinderSync.plist
  cp "$BACKUP/Info-ArchivePreview.plist" Packaging/Info-ArchivePreview.plist
  rm -rf "$WORK"
}
trap restore EXIT

for plist in Packaging/Info-App.plist Packaging/Info-FinderSync.plist Packaging/Info-ArchivePreview.plist; do
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$plist"
  plutil -replace CFBundleVersion -string "$BUILD" "$plist"
done

MIAORIGHT_SIGNING_IDENTITY="MiaoRight dev" \
MIAORIGHT_REQUIRE_STABLE_SIGNING=1 \
MIAORIGHT_APP_OUTPUT="$WORK/MiaoRight.app" \
MIAORIGHT_ICON_OUTPUT="$WORK/icons" \
./scripts/build-app.sh release

APP="$WORK/MiaoRight.app"
test "$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")" = "$VERSION"
codesign --verify --deep --strict "$APP"
codesign -dv --verbose=4 "$APP" > "$WORK/codesign.txt" 2>&1
authority="$(awk -F= '/^Authority=/{print $2; exit}' "$WORK/codesign.txt")"
if [[ "$authority" != "MiaoRight dev" ]]; then
  echo "Expected MiaoRight dev signing, got: $authority" >&2
  exit 1
fi

ARCH="$(uname -m)"
ZIP="$OUT_DIR/MiaoRight-v$VERSION-$ARCH.zip"
(cd "$WORK" && "$APP/Contents/Helpers/7zz" a -tzip -mm=Deflate -snl -bd -y "$ZIP" MiaoRight.app >/dev/null)
"$APP/Contents/Helpers/7zz" t "$ZIP" >/dev/null
echo "Debug update package: $ZIP"
ls -lh "$ZIP"
