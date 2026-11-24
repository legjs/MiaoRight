#!/bin/bash
# 妙右开发循环:正常退出旧实例 → 重建 → 组装 → 重启(一条命令)
# 用法: scripts/dev.sh [release|debug]
set -euo pipefail
CONFIG="${1:-release}"
SOURCE_APP="build/MiaoRight.app"
APP="${MIAORIGHT_DEV_APP_PATH:-/Applications/MiaoRight.app}"
PROCESS_PATTERN="MacOS/MiaoRight$"
cd "$(dirname "$0")/.."

is_running() {
  pgrep -f "$PROCESS_PATTERN" >/dev/null 2>&1
}

wait_until_stopped() {
  local attempts="$1"
  local delay="$2"
  local i
  for ((i = 0; i < attempts; i++)); do
    is_running || return 0
    sleep "$delay"
  done
  ! is_running
}

if is_running; then
  echo "Stopping the running MiaoRight instance…"
  # A normal quit lets the app lock the vault and flush its state.
  osascript -e 'tell application id "com.miaoright.app" to quit' >/dev/null 2>&1 || true

  if ! wait_until_stopped 20 0.25; then
    echo "Graceful quit timed out; sending SIGTERM." >&2
    pkill -TERM -f "$PROCESS_PATTERN" >/dev/null 2>&1 || true
    wait_until_stopped 12 0.25 || true
  fi

  if is_running; then
    echo "MiaoRight did not stop; sending SIGKILL." >&2
    pkill -KILL -f "$PROCESS_PATTERN" >/dev/null 2>&1 || true
    wait_until_stopped 12 0.25 || true
  fi
fi

if is_running; then
  echo "Could not stop the existing MiaoRight process." >&2
  exit 1
fi

./scripts/build-app.sh "$CONFIG"

# macOS 26 is unreliable about loading Finder Sync extensions from a build
# directory. Install the development bundle before opening it so Finder uses
# the refreshed extension and its existing approvals.
if [[ "$APP" != "$SOURCE_APP" ]]; then
  rm -rf "$APP"
  ditto "$SOURCE_APP" "$APP"
fi

LSREGISTER='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
"$LSREGISTER" -f "$APP"
pluginkit -r "$APP/Contents/PlugIns/MiaoRightFinder.appex" >/dev/null 2>&1 || true
pluginkit -a "$APP/Contents/PlugIns/MiaoRightFinder.appex"
pluginkit -e use -i com.miaoright.app.FinderSync
open "$APP"

for _ in {1..20}; do
  if is_running; then
    echo "✅ MiaoRight 已重建并启动"
    exit 0
  fi
  sleep 0.25
done

echo "⚠️ 进程未启动，可能有授权弹窗或扩展注册问题待处理" >&2
exit 1
