#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: ./release.sh <version> [notes]}"
NOTES="${2:-Release $VERSION}"

# Build release
./build.sh Release

# Zip
APP=$(xcodebuild -project OpenAuthenticator.xcodeproj \
  -scheme OpenAuthenticator \
  -configuration Release \
  -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $3}')

ditto -c -k --keepParent "$APP/OpenAuthenticator.app" /tmp/OpenAuthenticator.zip

# Create GitHub release
gh release create "v$VERSION" /tmp/OpenAuthenticator.zip \
  --title "OpenAuthenticator v$VERSION" \
  --notes "$NOTES"
