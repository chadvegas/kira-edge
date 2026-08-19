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
KEYCHAIN_PROFILE="${XENEON_NOTARY_PROFILE:-xeneon-notary}"
VERSION="${XENEON_VERSION:-1.0.1}"
DMG_PATH="$DIST_DIR/$DISPLAY_NAME $VERSION.dmg"
mkdir -p "$DIST_DIR"
STAGE_DIR="$(mktemp -d "$DIST_DIR/.kira-edge-dmg-stage.XXXXXX")"
ZIP_PATH="$DIST_DIR/.$APP_NAME-notarize.$$.zip"
DMG_WORK_PATH="$DIST_DIR/.$DISPLAY_NAME $VERSION.$$.dmg"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$1" >&2; exit 1; }

cleanup_release_stage() {
  rm -f "$ZIP_PATH" "$DMG_WORK_PATH"
  rm -rf "$STAGE_DIR"
}

trap cleanup_release_stage EXIT

"$ROOT_DIR/script/verify_distribution_inputs.sh"

# Confirm the notary credential exists before spending time on the build.
if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1; then
  fail "No notary credential '$KEYCHAIN_PROFILE'. Run the store-credentials command in this script's header first."
fi

step "Resolving Developer ID signing identity"
SIGN_IDENTITY="${XENEON_CODESIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
fi
[[ -n "$SIGN_IDENTITY" ]] || fail "No 'Developer ID Application' identity found for signing."
echo "identity: $SIGN_IDENTITY"
security find-identity -p codesigning -v 2>/dev/null \
  | grep -F 'Developer ID Application' \
  | grep -F "$SIGN_IDENTITY" \
  >/dev/null \
  || fail "Signing identity is not a valid Developer ID Application certificate: $SIGN_IDENTITY"

step "Building release bundle (hardened runtime + timestamp), version $VERSION"
XENEON_RELEASE=1 XENEON_VERSION="$VERSION" XENEON_CODESIGN_IDENTITY="$SIGN_IDENTITY" \
  "$ROOT_DIR/script/build_and_run.sh" bundle

step "Verifying app signature"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
# Capture before grepping: `codesign | grep -q` under pipefail races — grep
# quits at the first match, codesign takes SIGPIPE (141), and the pipeline
# "fails" even though the runtime flag is present.
SIGNATURE_INFO="$(codesign -d --verbose=2 "$APP_BUNDLE" 2>&1)"
grep -q "flags=.*runtime" <<<"$SIGNATURE_INFO" \
  || fail "App is not signed with the hardened runtime."
KIRA_REQUIRE_NESTED_SIGNATURE=1 "$ROOT_DIR/script/verify_bundle.sh" "$APP_BUNDLE"

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
/usr/bin/ditto "$APP_BUNDLE" "$STAGE_DIR/$APP_NAME.app"
# create-dmg can exit non-zero even on success (e.g. when it can't set a custom
# volume icon), so retain the artifact check and fail if no usable image exists.
if ! create-dmg \
  --volname "$DISPLAY_NAME" \
  --window-size 540 380 \
  --icon-size 110 \
  --icon "$APP_NAME.app" 140 190 \
  --app-drop-link 400 190 \
  --hide-extension "$APP_NAME.app" \
  "$DMG_WORK_PATH" \
  "$STAGE_DIR"; then
  echo "warning: create-dmg returned non-zero; validating the generated image" >&2
fi
[[ -f "$DMG_WORK_PATH" ]] || fail "create-dmg did not produce $DMG_WORK_PATH"
hdiutil verify "$DMG_WORK_PATH" >/dev/null \
  || fail "DMG verification failed before signing: $DMG_WORK_PATH"

step "Signing the DMG"
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_WORK_PATH"
codesign --verify --strict --verbose=2 "$DMG_WORK_PATH"

step "Notarizing + stapling the DMG"
xcrun notarytool submit "$DMG_WORK_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait \
  || fail "DMG notarization failed."
xcrun stapler staple "$DMG_WORK_PATH"
xcrun stapler validate "$DMG_WORK_PATH" \
  || fail "DMG notarization ticket validation failed: $DMG_WORK_PATH"
hdiutil verify "$DMG_WORK_PATH" >/dev/null \
  || fail "DMG verification failed after stapling: $DMG_WORK_PATH"
spctl -a -vvv --type install "$DMG_WORK_PATH" \
  || fail "Gatekeeper rejected the packaged DMG: $DMG_WORK_PATH"

# Keep any previous release if a later step fails; promote only the fully
# notarized, stapled, Gatekeeper-accepted image.
mv -f "$DMG_WORK_PATH" "$DMG_PATH"

printf '\n\033[1;32m✓ Shipped: %s\033[0m\n' "$DMG_PATH"
echo "Hand this DMG to your testers. Each tester must also be added as a Google"
echo "OAuth test user for calendar sync to connect (see SHIPPING.md)."
