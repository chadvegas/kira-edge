#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="XeneonEdgeWidgets"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME.app"
TARGET_APP="/Applications/Kira Edge.app"
# Pre-rename install location; removed on install so two copies never coexist.
LEGACY_APP="/Applications/XENEON Edge Widgets.app"

"$ROOT_DIR/script/build_and_run.sh" --verify
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
rm -rf "$TARGET_APP" "$LEGACY_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"
open "$TARGET_APP"

echo "Installed $TARGET_APP"
