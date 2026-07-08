#!/usr/bin/env bash
set -euo pipefail

# Release pipeline: build a hardened-runtime bundle, notarize + staple the app,
# wrap it in a signed + notarized + stapled DMG, and verify Gatekeeper accepts
# both. Produces dist/"Kira Edge <version>.dmg" ready to distribute.
#
# One-time setup (stores an App Store Connect / Apple ID credential in the
# keychain so this script can run unattended):
#
#   xcrun notarytool store-credentials xeneon-notary \
#       --apple-id "you@example.com" \
#       --team-id YOURTEAMID \
#       --password "app-specific-password"
#
# (Create the app-specific password at https://account.apple.com → Sign-In &
# Security → App-Specific Passwords.)
#
# Then just:  script/notarize_and_package.sh
#
# Override the version:  XENEON_VERSION=1.0.1 script/notarize_and_package.sh
# Override the profile:  XENEON_NOTARY_PROFILE=my-profile script/notarize_and_package.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="XeneonEdgeWidgets"
DISPLAY_NAME="Kira Edge"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/$APP_NAME-notarize.zip"
STAGE_DIR="$DIST_DIR/dmg-stage"
KEYCHAIN_PROFILE="${XENEON_NOTARY_PROFILE:-xeneon-notary}"
VERSION="${XENEON_VERSION:-1.0.0}"
DMG_PATH="$DIST_DIR/$DISPLAY_NAME $VERSION.dmg"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$1" >&2; exit 1; }

# Confirm the notary credential exists before spending time on the build.
if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1; then
  fail "No notary credential '$KEYCHAIN_PROFILE'. Run the store-credentials command in this script's header first."
fi

step "Building release bundle (hardened runtime + timestamp), version $VERSION"
XENEON_RELEASE=1 XENEON_VERSION="$VERSION" "$ROOT_DIR/script/build_and_run.sh" bundle

step "Resolving Developer ID signing identity"
SIGN_IDENTITY="${XENEON_CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
fi
[[ -n "$SIGN_IDENTITY" ]] || fail "No 'Developer ID Application' identity found for signing."
echo "identity: $SIGN_IDENTITY"

step "Verifying app signature"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
codesign -d --verbose=2 "$APP_BUNDLE" 2>&1 | grep -q "flags=.*runtime" \
  || fail "App is not signed with the hardened runtime."

step "Zipping app for notarization"
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

step "Submitting app to Apple notary service (this can take a few minutes)"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait \
  || fail "App notarization failed. Run: xcrun notarytool log <submission-id> --keychain-profile $KEYCHAIN_PROFILE"

step "Stapling notarization ticket to app"
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

step "Confirming Gatekeeper accepts the app"
spctl -a -vvv --type exec "$APP_BUNDLE"

step "Building DMG"
rm -rf "$STAGE_DIR"; mkdir -p "$STAGE_DIR"
cp -R "$APP_BUNDLE" "$STAGE_DIR/"
rm -f "$DMG_PATH"
# create-dmg can exit non-zero even on success (e.g. when it can't set a custom
# volume icon), so tolerate that and assert the artifact exists instead.
create-dmg \
  --volname "$DISPLAY_NAME" \
  --window-size 540 380 \
  --icon-size 110 \
  --icon "$APP_NAME.app" 140 190 \
  --app-drop-link 400 190 \
  --hide-extension "$APP_NAME.app" \
  "$DMG_PATH" \
  "$STAGE_DIR" || true
[[ -f "$DMG_PATH" ]] || fail "create-dmg did not produce $DMG_PATH"

step "Signing the DMG"
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"

step "Notarizing + stapling the DMG"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait \
  || fail "DMG notarization failed."
xcrun stapler staple "$DMG_PATH"
spctl -a -vvv --type install "$DMG_PATH" 2>&1 || true

rm -f "$ZIP_PATH"
rm -rf "$STAGE_DIR"

printf '\n\033[1;32m✓ Shipped: %s\033[0m\n' "$DMG_PATH"
echo "Hand this DMG to your testers. Each tester must also be added as a Google"
echo "OAuth test user for calendar sync to connect (see SHIPPING.md)."
