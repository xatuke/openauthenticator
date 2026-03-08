#!/bin/bash
set -euo pipefail

xcodebuild -project OpenAuthenticator.xcodeproj \
  -scheme OpenAuthenticator \
  -configuration "${1:-Debug}" \
  -destination 'platform=macOS' \
  -allowProvisioningUpdates \
  build

APP=$(xcodebuild -project OpenAuthenticator.xcodeproj \
  -scheme OpenAuthenticator \
  -configuration "${1:-Debug}" \
  -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $3}')

echo ""
echo "Run with: open \"$APP/OpenAuthenticator.app\""
