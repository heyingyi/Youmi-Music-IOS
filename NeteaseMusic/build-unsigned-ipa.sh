#!/bin/bash
set -euo pipefail

# Build an unsigned IPA for Sideloadly / 全能签.
# Requires macOS + Xcode.

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

xcodebuild \
  -project NeteaseMusic.xcodeproj \
  -scheme NeteaseMusic \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  DEVELOPMENT_TEAM="" \
  build

APP="build/Build/Products/Release-iphoneos/NeteaseMusic.app"
if [ ! -d "$APP" ]; then
  echo "Build succeeded but NeteaseMusic.app was not found"
  exit 1
fi

rm -rf Payload
mkdir -p Payload
cp -R "$APP" Payload/
ditto -c -k --sequesterRsrc --keepParent Payload Youmi-Music-unsigned.ipa
echo "IPA: $ROOT/Youmi-Music-unsigned.ipa"
