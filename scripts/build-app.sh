#!/bin/bash
# Build MiaoRight.app from SwiftPM targets and assemble the bundle.
# Usage: scripts/build-app.sh [debug|release]
# Set MIAORIGHT_BUILD_ARCH to build for a different Mac architecture.
set -euo pipefail

CONFIG="${1:-release}"
case "$CONFIG" in
  debug|release) ;;
  *) echo "Unknown config: $CONFIG (use debug|release)" >&2; exit 1 ;;
esac

cd "$(dirname "$0")/.."

ARCH="${MIAORIGHT_BUILD_ARCH:-$(uname -m)}"
case "$ARCH" in
  arm64) SEVEN_ZIP="ThirdParty/7zip/7zz" ;;
  x86_64) SEVEN_ZIP="ThirdParty/7zip/7zz-x86_64" ;;
  *) echo "Unsupported macOS architecture: $ARCH" >&2; exit 1 ;;
esac

# Verify the pinned 7-Zip binaries and notices before building.
(cd ThirdParty/7zip && shasum -a 256 -c SHA256SUMS)

SWIFT_BUILD_ARGS=(-c "$CONFIG" --triple "$ARCH-apple-macosx14.0")
if [[ -n "${MIAORIGHT_BUILD_JOBS:-}" ]]; then
  [[ "$MIAORIGHT_BUILD_JOBS" =~ ^[1-9][0-9]*$ ]] || { echo "Build jobs must be a positive integer" >&2; exit 1; }
  SWIFT_BUILD_ARGS+=(--jobs "$MIAORIGHT_BUILD_JOBS")
fi
if [[ -n "${MIAORIGHT_SWIFT_BUILD_PATH:-}" ]]; then
  SWIFT_BUILD_ARGS+=(--scratch-path "$MIAORIGHT_SWIFT_BUILD_PATH")
fi
swift build "${SWIFT_BUILD_ARGS[@]}"
BUILD_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"

for binary in "$BUILD_DIR"/{MiaoRightApp,MiaoRightFinder,MiaoRightArchivePreview} "$SEVEN_ZIP"; do
  if [[ "$(xcrun lipo -archs "$binary")" != "$ARCH" ]]; then
    echo "Expected a $ARCH binary: $binary" >&2
    exit 1
  fi
done

APP="${MIAORIGHT_APP_OUTPUT:-build/MiaoRight.app}"
case "$APP" in
  */*.app) ;;
  *) echo "App output must be a named .app inside a directory" >&2; exit 1 ;;
esac
APPEX="$APP/Contents/PlugIns/MiaoRightFinder.appex"
PREVIEW_APPEX="$APP/Contents/PlugIns/MiaoRightArchivePreview.appex"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"
mkdir -p "$APP/Contents/Helpers" "$APP/Contents/Resources/ThirdParty/7zip"
mkdir -p "$PREVIEW_APPEX/Contents/MacOS"
cp "$BUILD_DIR/MiaoRightArchivePreview" "$PREVIEW_APPEX/Contents/MacOS/"
cp Packaging/Info-ArchivePreview.plist "$PREVIEW_APPEX/Contents/Info.plist"
cp "$SEVEN_ZIP" "$APP/Contents/Helpers/7zz"
chmod 755 "$APP/Contents/Helpers/7zz"
cp ThirdParty/7zip/{License.txt,COPYING.LGPL.txt,readme.txt,README.md,SHA256SUMS,7z2606-src.tar.xz} "$APP/Contents/Resources/ThirdParty/7zip/"

# 每次构建自动导出标准 ICNS 与菜单栏 1x/2x 模板，避免只在本机手工设置图标。
ICON_OUTPUT="${MIAORIGHT_ICON_OUTPUT:-Resources/Icons}"
./scripts/generate-icons.sh "$ICON_OUTPUT"
cp "$ICON_OUTPUT/AppIcon.icns" "$ICON_OUTPUT"/MenuBarTemplate*.png "$APP/Contents/Resources/"
cp "$ICON_OUTPUT/FinderIcon.icns" "$APPEX/Contents/Resources/"

cp "$BUILD_DIR/MiaoRightApp" "$APP/Contents/MacOS/MiaoRight"
cp "$BUILD_DIR/MiaoRightFinder" "$APPEX/Contents/MacOS/MiaoRightFinder"

# SPM resource bundles ship inside Contents/Resources.
cp -R "$BUILD_DIR"/*.bundle "$APP/Contents/Resources/" 2>/dev/null || true

printf 'APPL????' > "$APP/Contents/PkgInfo"
printf 'BNDL????' > "$APPEX/Contents/PkgInfo"

# 本地化目录:让系统按 AppleLanguages 渲染菜单栏语言(空目录即可)
mkdir -p "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/zh-Hans.lproj"

cp Packaging/Info-FinderSync.plist "$APPEX/Contents/Info.plist"
cp Packaging/Info-App.plist "$APP/Contents/Info.plist"

# 稳定签名:本机存在「MiaoRight dev」自签证书时使用(DR 稳定,
# 重编译后 TCC 授权持久有效);否则回退 ad-hoc(每次重建需重新授权)
IDENTITY="${MIAORIGHT_SIGNING_IDENTITY:-MiaoRight dev}"
IDENTITY_KEYCHAINS=()
if [[ -n "${MIAORIGHT_SIGNING_KEYCHAIN:-}" ]]; then
  IDENTITY_KEYCHAINS=("$MIAORIGHT_SIGNING_KEYCHAIN")
fi
AVAILABLE_IDENTITIES="$(security find-identity -v -p codesigning "${IDENTITY_KEYCHAINS[@]}" 2>/dev/null || true)"
if [[ "$AVAILABLE_IDENTITIES" != *"\"$IDENTITY\""* ]]; then IDENTITY="-"; fi
if [[ "${MIAORIGHT_REQUIRE_STABLE_SIGNING:-0}" == "1" && "$IDENTITY" == "-" ]]; then
  echo "A stable signing identity is required but was not found." >&2
  exit 1
fi

# 先签嵌套工具再签外层 App；源码及许可同时随包提供。
codesign --force --identifier com.miaoright.app.7zip --sign "$IDENTITY" "$APP/Contents/Helpers/7zz"

codesign --force --identifier com.miaoright.app.FinderSync --sign "$IDENTITY" \
  --entitlements Packaging/FinderSync.entitlements \
  "$APPEX"

codesign --force --identifier com.miaoright.app.ArchivePreview --sign "$IDENTITY" \
  --entitlements Packaging/ArchivePreview.entitlements "$PREVIEW_APPEX"

codesign --force --identifier com.miaoright.app --sign "$IDENTITY" \
  --entitlements Packaging/App.entitlements \
  "$APP"

codesign --verify --deep --strict "$APP"
if [[ "$IDENTITY" == "-" ]]; then
  echo "Warning: $APP uses an ad-hoc signature and TCC permissions may reset after rebuilds." >&2
else
  SIGNATURE_AUTHORITY="$(codesign -d --verbose=4 "$APP" 2>&1 | awk -F= '/^Authority=/{authority=$2} END{print authority}')"
  echo "Signed $APP with ${SIGNATURE_AUTHORITY:-$IDENTITY}"
fi

echo "Built $APP"
