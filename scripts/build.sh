#!/usr/bin/env bash
# Builds VideoWallpaper.app (universal: Apple silicon + Intel) and packages it as a DMG.
#
#   ./scripts/build.sh            # Release build → build/VideoWallpaper.dmg
#   ./scripts/build.sh --install  # …and copy the app to /Applications
#
# Requires Xcode 16 or later. The app is ad-hoc signed ("Sign to Run Locally").
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD_DIR="$ROOT/build"
DERIVED="$BUILD_DIR/DerivedData"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="VideoWallpaper"

rm -rf "$BUILD_DIR/$APP_NAME.app" "$BUILD_DIR/dmg" "$BUILD_DIR/$APP_NAME.dmg"
mkdir -p "$BUILD_DIR"

echo "▸ Building $APP_NAME ($CONFIGURATION)…"
xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  OTHER_SWIFT_FLAGS="\$(inherited) ${EXTRA_SWIFT_FLAGS:-}" \
  build | { command -v xcpretty >/dev/null && xcpretty || cat; }

APP="$DERIVED/Build/Products/$CONFIGURATION/$APP_NAME.app"
if [[ ! -d "$APP" ]]; then
  echo "✗ Build product not found at $APP" >&2
  exit 1
fi

cp -R "$APP" "$BUILD_DIR/"
codesign --force --deep --sign - "$BUILD_DIR/$APP_NAME.app"
codesign --verify --verbose=2 "$BUILD_DIR/$APP_NAME.app"

echo "▸ Packaging DMG…"
mkdir -p "$BUILD_DIR/dmg"
cp -R "$BUILD_DIR/$APP_NAME.app" "$BUILD_DIR/dmg/"
ln -s /Applications "$BUILD_DIR/dmg/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$BUILD_DIR/dmg" -ov -format UDZO "$BUILD_DIR/$APP_NAME.dmg" >/dev/null
rm -rf "$BUILD_DIR/dmg"

echo "✓ Built $BUILD_DIR/$APP_NAME.app"
echo "✓ Packaged $BUILD_DIR/$APP_NAME.dmg"

if [[ "${1:-}" == "--install" ]]; then
  echo "▸ Installing to /Applications…"
  pkill -x "$APP_NAME" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$BUILD_DIR/$APP_NAME.app" /Applications/
  echo "✓ Installed /Applications/$APP_NAME.app"
  open "/Applications/$APP_NAME.app"
fi
