#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

if [[ $# -ne 1 ]]; then
  printf 'usage: %s /path/to/XeneonEdgeWidgets.app\n' "$0" >&2
  exit 2
fi

APP_BUNDLE="$1"
APP_CONTENTS="$APP_BUNDLE/Contents"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_BINARY="$APP_CONTENTS/MacOS/XeneonEdgeWidgets"
HELPERS_DIR="$APP_CONTENTS/Resources/Helpers"
HELPER_SCRIPT="$HELPERS_DIR/mediaremote-adapter.pl"
ADAPTER_FRAMEWORK="$HELPERS_DIR/MediaRemoteAdapter.framework"
ADAPTER_BINARY="$ADAPTER_FRAMEWORK/Versions/A/MediaRemoteAdapter"

[[ -d "$APP_BUNDLE" ]] || fail "App bundle does not exist: $APP_BUNDLE"
[[ -f "$INFO_PLIST" ]] || fail "App Info.plist is missing: $INFO_PLIST"
[[ -x "$APP_BINARY" ]] || fail "App executable is missing or not executable: $APP_BINARY"
[[ -x "$HELPER_SCRIPT" ]] || fail "Now Playing adapter script is missing or not executable: $HELPER_SCRIPT"
[[ -d "$ADAPTER_FRAMEWORK/Versions/A" ]] \
  || fail "Now Playing adapter framework is missing: $ADAPTER_FRAMEWORK"
[[ -f "$ADAPTER_BINARY" ]] || fail "Now Playing adapter binary is missing: $ADAPTER_BINARY"

command -v codesign >/dev/null 2>&1 || fail "codesign is required for bundle verification."
command -v lipo >/dev/null 2>&1 || fail "lipo is required for helper architecture verification."
command -v plutil >/dev/null 2>&1 || fail "plutil is required for Info.plist verification."
command -v perl >/dev/null 2>&1 || fail "perl is required for adapter script verification."

plutil -lint "$INFO_PLIST" >/dev/null \
  || fail "App Info.plist is invalid: $INFO_PLIST"
perl -c "$HELPER_SCRIPT" >/dev/null 2>&1 \
  || fail "Now Playing adapter script failed Perl syntax validation: $HELPER_SCRIPT"

codesign --verify --deep --strict "$APP_BUNDLE" \
  || fail "App signature verification failed: $APP_BUNDLE"
# Local development may leave the framework wrapper unsigned because it lives
# under Resources. Release signing signs the wrapper explicitly; require that
# stronger nested signature only when the release pipeline opts in.
if [[ "${KIRA_REQUIRE_NESTED_SIGNATURE:-0}" == "1" ]]; then
  codesign --verify --strict "$ADAPTER_FRAMEWORK" \
    || fail "Now Playing adapter framework signature verification failed: $ADAPTER_FRAMEWORK"
fi

APP_ARCH_INFO="$(lipo -info "$APP_BINARY" 2>&1)" \
  || fail "Could not inspect app architecture: $APP_BINARY"
HELPER_ARCH_INFO="$(lipo -info "$ADAPTER_BINARY" 2>&1)" \
  || fail "Could not inspect Now Playing helper architecture: $ADAPTER_BINARY"
HOST_ARCH="$(uname -m)"

case "$HOST_ARCH" in
  arm64|x86_64)
    case "$APP_ARCH_INFO" in
      *"$HOST_ARCH"*) ;;
      *) fail "App architecture does not match the CI/build host ($HOST_ARCH): $APP_ARCH_INFO" ;;
    esac
    ;;
  *)
    fail "Unsupported build host architecture: $HOST_ARCH"
    ;;
esac

case "$HELPER_ARCH_INFO" in
  *arm64*) ;;
  *) fail "Now Playing helper is missing arm64: $HELPER_ARCH_INFO" ;;
esac
case "$HELPER_ARCH_INFO" in
  *x86_64*) ;;
  *) fail "Now Playing helper is missing x86_64: $HELPER_ARCH_INFO" ;;
esac

printf 'Bundle verified: %s\n' "$APP_BUNDLE"
printf '  app architecture: %s\n' "$APP_ARCH_INFO"
printf '  helper architecture: %s\n' "$HELPER_ARCH_INFO"
