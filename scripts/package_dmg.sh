#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

VERSION="1.0.1"
APP_NAME="PureZip"
DMG_NAME="${APP_NAME}-${VERSION}-arm64.dmg"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
DMG_PATH="$DIST_DIR/${DMG_NAME}"
TEMP_DMG_DIR="$DIST_DIR/dmg_staging"

echo "==> [1/3] Building clean release app bundle..."
"$ROOT_DIR/scripts/build_app.sh"

echo "==> [2/3] Preparing staging directory for DMG..."
rm -rf "$TEMP_DMG_DIR" "$DMG_PATH"
mkdir -p "$TEMP_DMG_DIR"

# Copy App bundle to staging
cp -R "$APP_BUNDLE" "$TEMP_DMG_DIR/"

# Create /Applications symlink
ln -s /Applications "$TEMP_DMG_DIR/Applications"

echo "==> [3/3] Creating compressed DMG with hdiutil..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$TEMP_DMG_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$TEMP_DMG_DIR"

echo "==> SUCCESS: Created DMG package at: $DMG_PATH"
ls -lh "$DMG_PATH"
