#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: ./release.sh <version> [notes]}"
NOTES="${2:-Release $VERSION}"
NOTARY_PROFILE="${NOTARY_PROFILE:-openauth-notary}"
DEV_ID="${DEV_ID:-Developer ID Application: Aayushman Choudhary (CRH6P5D9K2)}"
TEAM_ID="CRH6P5D9K2"

# Build release (uses Apple Development / automatic signing to satisfy Xcode)
./build.sh Release

# Locate the built app
BUILT_DIR=$(xcodebuild -project OpenAuthenticator.xcodeproj \
  -scheme OpenAuthenticator \
  -configuration Release \
  -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $3}')
APP="$BUILT_DIR/OpenAuthenticator.app"

# Remove the Xcode-embedded Development provisioning profile. It is
# device-locked to registered Macs; leaving it in makes the app refuse to
# launch ("can't be opened") on every other machine, even once notarized.
rm -f "$APP/Contents/embedded.provisionprofile"

# Re-sign with Developer ID + hardened runtime for public distribution.
# No entitlements: the app is non-sandboxed and uses the default keychain
# access group, so keychain-access-groups is unnecessary. Shipping it
# WITHOUT a provisioning profile to authorize it makes AMFI SIGKILL the app
# on launch ("can't be opened") on every machine.

# Sign nested code (frameworks/dylibs) first, then the app bundle.
find "$APP/Contents/Frameworks" -type f \( -name "*.dylib" -o -name "*.framework" \) 2>/dev/null \
  -exec codesign --force --options runtime --timestamp --sign "$DEV_ID" {} \; || true
find "$APP/Contents/Frameworks" -maxdepth 1 -type d -name "*.framework" 2>/dev/null \
  -exec codesign --force --options runtime --timestamp --sign "$DEV_ID" {} \; || true

codesign --force --options runtime --timestamp \
  --sign "$DEV_ID" "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"

# Notarize: zip the app, submit to Apple, wait for the result
NOTARIZE_ZIP=$(mktemp -d)/OpenAuthenticator-notarize.zip
ditto -c -k --keepParent "$APP" "$NOTARIZE_ZIP"
echo "Submitting to Apple notary service..."
xcrun notarytool submit "$NOTARIZE_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

# Staple the notarization ticket onto the app
xcrun stapler staple "$APP"

# Verify Gatekeeper accepts it
spctl -a -vvv -t exec "$APP"

# Package as a DMG with an /Applications shortcut. Shipping a bare .zip made
# users launch the app straight from ~/Downloads, where macOS App
# Translocation runs it from a random read-only path and it fails to open.
# A DMG guides users to drag the app into /Applications, which avoids
# translocation entirely, so it launches cleanly on first double-click.
STAGE="$(mktemp -d)/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG=/tmp/OpenAuthenticator.dmg
rm -f "$DMG"
hdiutil create -volname "OpenAuthenticator" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

# Sign, notarize, and staple the DMG itself.
codesign --force --sign "$DEV_ID" --timestamp "$DMG"
echo "Notarizing DMG..."
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl -a -vvv -t open --context context:primary-signature "$DMG"

# Create GitHub release with the DMG
gh release create "v$VERSION" "$DMG" \
  --title "OpenAuthenticator v$VERSION" \
  --notes "$NOTES"
