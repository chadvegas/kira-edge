#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="XeneonEdgeWidgets"
BUNDLE_ID="com.chadvegas.XeneonEdgeWidgets"
MIN_SYSTEM_VERSION="14.0"
# Marketing version + build number. Override per-release via env; the build
# number defaults to a timestamp so every packaged build is monotonic.
APP_VERSION="${XENEON_VERSION:-1.0.0}"
APP_BUILD="${XENEON_BUILD:-$(date +%Y%m%d%H%M)}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_HELPERS="$APP_RESOURCES/Helpers"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Resources/XeneonEdgeWidgets.entitlements"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_HELPERS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

RESOURCE_BUNDLE="$(swift build --show-bin-path)/XeneonEdgeWidgets_XeneonEdgeWidgets.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/"
fi

if [[ -d "$ROOT_DIR/Sources/XeneonEdgeWidgets/Resources/Fonts" ]]; then
  mkdir -p "$APP_RESOURCES/Fonts"
  cp "$ROOT_DIR"/Sources/XeneonEdgeWidgets/Resources/Fonts/* "$APP_RESOURCES/Fonts/"
fi

if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
fi

WATCH_HELPER_SOURCE="$ROOT_DIR/Helpers/xeneon-watch-battery.c"
WATCH_HELPER_BINARY="$APP_HELPERS/xeneon-watch-battery"
if [[ -f "$WATCH_HELPER_SOURCE" ]] && command -v clang >/dev/null 2>&1 && command -v pkg-config >/dev/null 2>&1 \
  && pkg-config --exists libimobiledevice-1.0 libplist-2.0; then
  clang "$WATCH_HELPER_SOURCE" $(pkg-config --cflags --libs libimobiledevice-1.0 libplist-2.0) -o "$WATCH_HELPER_BINARY"
  chmod +x "$WATCH_HELPER_BINARY"
else
  echo "warning: skipping Apple Watch helper; install Homebrew libimobiledevice and pkg-config to enable it" >&2
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>Kira Edge</string>
  <key>CFBundleDisplayName</key>
  <string>Kira Edge</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>com.chadvegas.XeneonEdgeWidgets.url</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>xeneonedge</string>
      </array>
    </dict>
  </array>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>Kira Edge scans nearby Bluetooth battery services so connected accessories can appear in the System widget.</string>
  <key>ATSApplicationFontsPath</key>
  <string>Fonts</string>
  <key>UIAppFonts</key>
  <array>
    <string>Baloo2-Variable.ttf</string>
    <string>Nunito-Variable.ttf</string>
  </array>
</dict>
</plist>
PLIST

SIGN_IDENTITY="${XENEON_CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null \
    | awk -F'\"' '/Developer ID Application/ {print $2; exit}')"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null \
    | awk -F'\"' '/Apple Development/ {print $2; exit}')"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
fi

if [[ "${XENEON_RELEASE:-0}" == "1" ]]; then
  # Release signing for notarization: hardened runtime + secure timestamp,
  # signed inside-out (nested Mach-O first, app last) instead of the
  # Apple-discouraged --deep. Requires network for the timestamp server.
  # The SwiftPM resource bundle carries no Mach-O, so it needs no signature of
  # its own — the app's signature seals its files as resources.
  RELEASE_SIGN=(--force --options runtime --timestamp --sign "$SIGN_IDENTITY")
  if [[ -f "$WATCH_HELPER_BINARY" ]]; then
    /usr/bin/codesign "${RELEASE_SIGN[@]}" "$WATCH_HELPER_BINARY"
  fi
  /usr/bin/codesign "${RELEASE_SIGN[@]}" --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
  /usr/bin/codesign --verify --strict "$APP_BUNDLE"
else
  # Fast local-dev signing: ad-hoc/Developer ID, no hardened runtime or
  # timestamp so the inner dev loop stays offline-friendly and quick.
  /usr/bin/codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
  /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  bundle)
    # Assemble + sign only; never launch. Used by the release/notarize pipeline.
    echo "Built $APP_BUNDLE ($APP_VERSION build $APP_BUILD)"
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|bundle|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
