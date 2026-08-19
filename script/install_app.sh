#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="XeneonEdgeWidgets"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME.app"
TARGET_APP="/Applications/Kira Edge.app"
# Pre-rename install location; removed on install so two copies never coexist.
LEGACY_APP="/Applications/XENEON Edge Widgets.app"

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

XENEON_PRESERVE_RUNNING_APP=1 "$ROOT_DIR/script/build_and_run.sh" bundle
"$ROOT_DIR/script/verify_bundle.sh" "$SOURCE_APP"

INSTALL_STAGE_ROOT="$(mktemp -d "/Applications/.kira-edge-install.XXXXXX")" \
  || fail "Could not create an install staging directory under /Applications."
STAGED_APP="$INSTALL_STAGE_ROOT/$APP_NAME.app"
ROLLBACK_DIR="$INSTALL_STAGE_ROOT/rollback"
INSTALL_COMPLETE=0

cleanup_install_stage() {
  if [[ "$INSTALL_COMPLETE" != 1 ]]; then
    if [[ ! -e "$TARGET_APP" && -e "$ROLLBACK_DIR/target.app" ]]; then
      mv "$ROLLBACK_DIR/target.app" "$TARGET_APP" || true
    fi
    if [[ ! -e "$LEGACY_APP" && -e "$ROLLBACK_DIR/legacy.app" ]]; then
      mv "$ROLLBACK_DIR/legacy.app" "$LEGACY_APP" || true
    fi
  fi
  if [[ -d "$INSTALL_STAGE_ROOT" ]]; then
    rm -rf "$INSTALL_STAGE_ROOT"
  fi
}

trap cleanup_install_stage EXIT

mkdir -p "$ROLLBACK_DIR"
/usr/bin/ditto "$SOURCE_APP" "$STAGED_APP" \
  || fail "Could not stage the verified app for installation."
"$ROOT_DIR/script/verify_bundle.sh" "$STAGED_APP"

# Stop the old app only after the replacement has been built and verified.
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
# pkill of the app can orphan its Now Playing adapter (a /usr/bin/perl child);
# scope cleanup to the known bundle locations so other adapters are untouched.
pkill -f "$ROOT_DIR/dist/.*mediaremote-adapter" >/dev/null 2>&1 || true
pkill -f "/Applications/Kira Edge.app/.*mediaremote-adapter" >/dev/null 2>&1 || true
pkill -f "/Applications/XENEON Edge Widgets.app/.*mediaremote-adapter" >/dev/null 2>&1 || true

if [[ -e "$TARGET_APP" ]]; then
  mv "$TARGET_APP" "$ROLLBACK_DIR/target.app" \
    || fail "Could not stage the existing installation for rollback: $TARGET_APP"
fi
if [[ -e "$LEGACY_APP" ]]; then
  mv "$LEGACY_APP" "$ROLLBACK_DIR/legacy.app" \
    || fail "Could not stage the legacy installation for rollback: $LEGACY_APP"
fi

mv "$STAGED_APP" "$TARGET_APP" \
  || fail "Could not promote the staged app to $TARGET_APP"

INSTALL_COMPLETE=1
rm -rf "$ROLLBACK_DIR"
open "$TARGET_APP"

echo "Installed $TARGET_APP"
