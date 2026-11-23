#!/bin/bash
# 妙右开发循环:重建 → 组装 → 重启(一条命令)
# 用法: scripts/dev.sh [release|debug]
set -euo pipefail
CONFIG="${1:-release}"
cd "$(dirname "$0")/.."

pkill -9 -f "MacOS/MiaoRight$" 2>/dev/null || true
./scripts/build-app.sh "$CONFIG" >/dev/null
open build/MiaoRight.app
sleep 2

if pgrep -f "MacOS/MiaoRight$" >/dev/null; then
  echo "✅ MiaoRight 已重建并启动"
else
  echo "⚠️ 进程未启动,可能有授权弹窗待处理"
fi
