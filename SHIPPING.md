# Shipping Kira Edge

Direct-distribution release: a **notarized, stapled Developer ID DMG**. (The
Mac App Store isn't targeted; direct distribution keeps the app dependency-free
and instant to update.)

The current release bundle is arm64 for Apple silicon. The Now Playing helper
is built as arm64 + x86_64, but that does not make the containing app an Intel
release.

## One-time setup (≈2 min)

Requires an Apple Developer Program membership (for a "Developer ID
Application" certificate).

The release machine also needs macOS 14+, Xcode's Swift/Clang toolchain,
`create-dmg`, and the checked-in `Vendor/mediaremote-adapter/SHA256SUMS`
manifest. The release scripts fail before assembly if the Now Playing sources
or any pinned vendor file is missing or modified.

1. Create an **app-specific password** at
   <https://account.apple.com> → Sign-In & Security → App-Specific Passwords.

2. Store a notary credential in your keychain so the release script runs
   unattended (substitute your Apple ID and Team ID):

   ```sh
   xcrun notarytool store-credentials xeneon-notary \
       --apple-id "you@example.com" \
       --team-id YOURTEAMID \
       --password "the-app-specific-password"
   ```

## Cut a release (one command)

```sh
XENEON_VERSION=1.0.1 script/notarize_and_package.sh
```

This builds a hardened-runtime bundle, notarizes + staples the app, wraps it in
a signed + notarized + stapled DMG, and verifies Gatekeeper accepts both.
Output: `dist/Kira Edge 1.0.1.dmg`. Bump `XENEON_VERSION` each release, then
attach the DMG to a GitHub Release.

The script stages the app and DMG in temporary paths, keeps an existing final
DMG until the new one passes `hdiutil verify`, stapler validation, and fatal
Gatekeeper assessment, then promotes it into `dist/`. A passing release should
open without an unidentified-developer warning.

## Notes

- Re-notarize on **every** build you distribute — a stapled ticket is tied to
  that exact build.
- If notarization is rejected, read why with:
  `xcrun notarytool log <submission-id> --keychain-profile xeneon-notary`
- The release path requires a valid `Developer ID Application` identity and
  auto-discovers it; override with `XENEON_CODESIGN_IDENTITY`.
- Google Calendar in your build: either have users paste their own OAuth client
  ID (default), or hardcode your project's client ID in
  `GoogleAuthService.bundledClientID` and add users to your consent screen's
  Test users while it's in Testing mode.
