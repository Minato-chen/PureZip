#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

echo "==> [1/4] Compiling Swift targets (PureZipApp, PureZipArchiveService, PureZipFinderSync, PureZipQuickLook, purezip-cli)..."
swift build

BIN_DIR="$(swift build --show-bin-path)"
APP_BUNDLE="$ROOT_DIR/dist/PureZip.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
XPC_BUNDLE="$CONTENTS/XPCServices/com.minato.purezip.ArchiveService.xpc"
FINDER_APPEX="$CONTENTS/PlugIns/PureZipFinderSync.appex"
QL_APPEX="$CONTENTS/PlugIns/PureZipQuickLook.appex"

echo "==> [2/4] Assembling bundle hierarchy at $APP_BUNDLE ..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" \
         "$XPC_BUNDLE/Contents/MacOS" \
         "$FINDER_APPEX/Contents/MacOS" \
         "$QL_APPEX/Contents/MacOS"

# Copy binaries
cp "$BIN_DIR/PureZipApp" "$MACOS_DIR/PureZip"
cp "$BIN_DIR/purezip-cli" "$MACOS_DIR/purezip-cli"
cp "$BIN_DIR/PureZipArchiveService" "$XPC_BUNDLE/Contents/MacOS/PureZipArchiveService"
cp "$BIN_DIR/PureZipFinderSync" "$FINDER_APPEX/Contents/MacOS/PureZipFinderSync"
cp "$BIN_DIR/PureZipQuickLook" "$QL_APPEX/Contents/MacOS/PureZipQuickLook"

# Copy AppIcon.icns
if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
    cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Copy 3D Model Viewer script for GLB / GLTF offline preview
if [[ -f "$ROOT_DIR/Resources/model-viewer.min.js" ]]; then
    cp "$ROOT_DIR/Resources/model-viewer.min.js" "$RESOURCES_DIR/model-viewer.min.js"
fi

# Optional: copy bundled 7zz if available
if [[ -f "$ROOT_DIR/Resources/7zz" ]]; then
    cp "$ROOT_DIR/Resources/7zz" "$RESOURCES_DIR/7zz"
elif [[ -x "/opt/homebrew/bin/7zz" ]]; then
    cp "/opt/homebrew/bin/7zz" "$RESOURCES_DIR/7zz"
elif [[ -x "/usr/local/bin/7zz" ]]; then
    cp "/usr/local/bin/7zz" "$RESOURCES_DIR/7zz"
fi

# 1. Main App Info.plist
cp "$ROOT_DIR/Support/PureZip-Info.plist" "$CONTENTS/Info.plist"
sed -i '' 's/\$(EXECUTABLE_NAME)/PureZip/g' "$CONTENTS/Info.plist"
sed -i '' 's/\$(PRODUCT_NAME)/PureZip/g' "$CONTENTS/Info.plist"
sed -i '' 's/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.minato.purezip/g' "$CONTENTS/Info.plist"
sed -i '' 's/\$(DEVELOPMENT_LANGUAGE)/zh_CN/g' "$CONTENTS/Info.plist"

# 2. XPC Worker Service Info.plist
cat > "$XPC_BUNDLE/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>PureZipArchiveService</string>
    <key>CFBundleExecutable</key>
    <string>PureZipArchiveService</string>
    <key>CFBundleIdentifier</key>
    <string>com.minato.purezip.ArchiveService</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>PureZipArchiveService</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.2</string>
    <key>CFBundleVersion</key>
    <string>257</string>
    <key>XPCService</key>
    <dict>
        <key>ServiceType</key>
        <string>Application</string>
    </dict>
</dict>
</plist>
EOF

# 3. FinderSync Extension Info.plist
cat > "$FINDER_APPEX/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>PureZipFinderSync</string>
    <key>CFBundleExecutable</key>
    <string>PureZipFinderSync</string>
    <key>CFBundleIdentifier</key>
    <string>com.minato.purezip.FinderSync</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>PureZipFinderSync</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.2</string>
    <key>CFBundleVersion</key>
    <string>257</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.FinderSync</string>
        <key>NSExtensionPrincipalClass</key>
        <string>FinderSync</string>
    </dict>
</dict>
</plist>
EOF

# 4. QuickLook Extension Info.plist
cat > "$QL_APPEX/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>PureZipQuickLook</string>
    <key>CFBundleExecutable</key>
    <string>PureZipQuickLook</string>
    <key>CFBundleIdentifier</key>
    <string>com.minato.purezip.QuickLook</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>PureZipQuickLook</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.2</string>
    <key>CFBundleVersion</key>
    <string>257</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionAttributes</key>
        <dict>
            <key>QLSupportedContentTypes</key>
            <array>
                <string>public.zip-archive</string>
                <string>org.7-zip.7-zip-archive</string>
                <string>public.tar-archive</string>
            </array>
        </dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.quicklook.preview</string>
        <key>NSExtensionPrincipalClass</key>
        <string>PreviewViewController</string>
    </dict>
</dict>
</plist>
EOF

echo "==> [3/4] Ad-hoc code-signing nested XPC service, App Extensions (.appex), and main .app bundle..."
if [[ -f "$RESOURCES_DIR/7zz" ]]; then
    codesign --force --sign - "$RESOURCES_DIR/7zz"
fi
codesign --force --sign - "$XPC_BUNDLE"
codesign --force --sign - --entitlements "$ROOT_DIR/Support/AppExtension.entitlements" "$FINDER_APPEX"
codesign --force --sign - --entitlements "$ROOT_DIR/Support/AppExtension.entitlements" "$QL_APPEX"
codesign --force --sign - "$MACOS_DIR/purezip-cli"
codesign --force --sign - "$APP_BUNDLE"

echo "==> [4/4] Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
echo "SUCCESS: Built and signed macOS app bundle at: $APP_BUNDLE"

# Automatically install to /Applications and re-register LaunchServices so Finder double-click always uses the newest build
echo "==> [5/5] Installing to /Applications/PureZip.app and updating LaunchServices..."
rm -rf "/Applications/PureZip.app"
cp -R "$APP_BUNDLE" "/Applications/PureZip.app"
touch "/Applications/PureZip.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted "/Applications/PureZip.app"

if [[ "${1:-}" == "--run" ]]; then
    echo "==> Launching /Applications/PureZip.app ..."
    open "/Applications/PureZip.app"
fi
