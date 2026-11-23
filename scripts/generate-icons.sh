#!/bin/bash
# Reproducible app/Finder/menu-bar artwork from the shared CoreGraphics vector source.
set -euo pipefail
cd "$(dirname "$0")/.."
ICON_OUTPUT="${1:-Resources/Icons}"
mkdir -p "$ICON_OUTPUT"
swift Packaging/Icons/GenerateIcons.swift "$ICON_OUTPUT"
for ICON_NAME in AppIcon FinderIcon; do
  iconutil -c icns "$ICON_OUTPUT/$ICON_NAME.iconset" -o "$ICON_OUTPUT/$ICON_NAME.icns"
done
