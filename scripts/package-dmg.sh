#!/bin/bash
# Build and verify a drag-to-Applications DMG for one signed app bundle.
# Usage: scripts/package-dmg.sh <MiaoRight.app> <tag> <arch> <output.dmg>
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <MiaoRight.app> <tag> <arm64|x86_64> <output.dmg>" >&2
  exit 1
fi

APP="$1"
TAG="$2"
ARCH="$3"
OUTPUT="$4"

case "$ARCH" in
  arm64|x86_64) ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

[[ -d "$APP" ]] || { echo "App bundle not found: $APP" >&2; exit 1; }
[[ "$OUTPUT" == *.dmg ]] || { echo "Output must end in .dmg" >&2; exit 1; }

cd "$(dirname "$0")/.."

executable="$APP/Contents/MacOS/MiaoRight"
[[ -x "$executable" ]] || { echo "Missing executable: $executable" >&2; exit 1; }
[[ "$(xcrun lipo -archs "$executable")" == "$ARCH" ]] || {
  echo "Expected a $ARCH executable: $executable" >&2
  exit 1
}
codesign --verify --deep --strict "$APP"

work="$(mktemp -d "${TMPDIR:-/tmp}/miaoright-dmg.XXXXXX")"
staging="$work/staging"
mount_point="$work/mount"
mounted=false

cleanup() {
  if [[ "$mounted" == true ]]; then
    hdiutil detach "$mount_point" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

mkdir -p "$staging" "$(dirname "$OUTPUT")"
ditto "$APP" "$staging/MiaoRight.app"
ln -s /Applications "$staging/Applications"
cat > "$staging/安装说明.txt" <<'EOF'
妙右安装说明

1. 将 MiaoRight.app 拖到右侧的 Applications（应用程序）文件夹。
2. 从“应用程序”中双击打开妙右，不要直接从 DMG 或“下载”目录运行。
3. 首次打开若被 macOS 拦截，请到“系统设置 > 隐私与安全性”选择“仍要打开”。
4. 在“系统设置 > 通用 > 登录项与扩展 > 扩展 > 访达”中启用“妙右 Finder 扩展”。
5. 打开妙右，在“剪贴板”页开启剪贴板历史；需要直接粘贴时，再到“隐私与安全性 > 辅助功能”授权妙右。
6. 完成后如右键菜单仍未出现，先重启 Finder；详细步骤见妙右网站的安装引导页。

Apple 芯片请使用 arm64 安装包，Intel 芯片请使用 x86_64 安装包。
EOF

hdiutil create \
  -volname "MiaoRight" \
  -srcfolder "$staging" \
  -fs HFS+ \
  -format UDZO \
  -quiet \
  -ov \
  "$OUTPUT"

mkdir -p "$mount_point"
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$mount_point" "$OUTPUT" >/dev/null
mounted=true

[[ -d "$mount_point/MiaoRight.app" ]] || { echo "DMG is missing MiaoRight.app" >&2; exit 1; }
[[ "$(readlink "$mount_point/Applications")" == "/Applications" ]] || {
  echo "DMG is missing the Applications shortcut" >&2
  exit 1
}
codesign --verify --deep --strict "$mount_point/MiaoRight.app"

hdiutil detach "$mount_point" >/dev/null
mounted=false
hdiutil verify "$OUTPUT" >/dev/null

echo "Built $OUTPUT"
