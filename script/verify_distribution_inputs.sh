#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor/mediaremote-adapter"
MANIFEST="$VENDOR_DIR/SHA256SUMS"

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

# These files are part of the shipped Now Playing feature. Keep this check in
# the bundle path rather than changing raw `swift build`, which remains useful
# for package-only local development.
required_paths=(
  "Sources/XeneonEdgeWidgets/Services/NowPlayingService.swift"
  "Sources/XeneonEdgeWidgets/Views/Widgets/MediaWidgetView.swift"
  "Vendor/mediaremote-adapter/SHA256SUMS"
  "Vendor/mediaremote-adapter/LICENSE"
  "Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl"
  "Vendor/mediaremote-adapter/include/MediaRemoteAdapter.h"
  "Vendor/mediaremote-adapter/src/adapter/now_playing.m"
  "Vendor/mediaremote-adapter/src/adapter/stream.m"
  "Vendor/mediaremote-adapter/src/private/MediaRemote.h"
  "Vendor/mediaremote-adapter/src/private/MediaRemote.m"
  "Vendor/mediaremote-adapter/src/utility/helpers.m"
)

missing_paths=()
for relative_path in "${required_paths[@]}"; do
  if [[ ! -f "$ROOT_DIR/$relative_path" ]]; then
    missing_paths+=("$relative_path")
  fi
done

if (( ${#missing_paths[@]} > 0 )); then
  printf 'error: required Now Playing distribution inputs are missing:\n' >&2
  printf '  - %s\n' "${missing_paths[@]}" >&2
  fail "Restore the Now Playing source and vendored mediaremote-adapter artifacts before assembling an app bundle."
fi

command -v shasum >/dev/null 2>&1 \
  || fail "shasum is required to verify Vendor/mediaremote-adapter/SHA256SUMS."

if ! (cd "$VENDOR_DIR" && shasum -a 256 -c "$(basename "$MANIFEST")"); then
  fail "Vendored mediaremote-adapter checksums do not match SHA256SUMS."
fi

printf 'Distribution inputs verified: Now Playing sources and mediaremote-adapter vendor tree.\n'
