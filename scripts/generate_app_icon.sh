#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT_DIR/Resources"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

swift - << 'EOF'
import SwiftUI
import AppKit

let view = ZStack {
    RoundedRectangle(cornerRadius: 185, style: .continuous)
        .fill(
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.98, blue: 1.0),
                    Color(red: 0.90, green: 0.91, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .stroke(Color.white.opacity(0.8), lineWidth: 4)
        )
        .shadow(color: Color.black.opacity(0.20), radius: 28, x: 0, y: 16)
        .frame(width: 824, height: 824)

    Image(systemName: "shippingbox.fill")
        .font(.system(size: 430))
        .foregroundStyle(
            LinearGradient(
                colors: [
                    Color(red: 0.22, green: 0.74, blue: 0.97),
                    Color(red: 0.05, green: 0.48, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .shadow(color: Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.35), radius: 24, x: 0, y: 12)
}
.frame(width: 1024, height: 1024)

let hosting = NSHostingView(rootView: view)
hosting.frame = NSRect(x: 0, y: 0, width: 1024, height: 1024)
let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
hosting.cacheDisplay(in: hosting.bounds, to: rep)
let pngData = rep.representation(using: .png, properties: [:])!
try! pngData.write(to: URL(fileURLWithPath: "/tmp/purezip_1024.png"))
EOF

mkdir -p "$TMP_DIR/AppIcon.iconset"
sips -z 16 16     /tmp/purezip_1024.png --out "$TMP_DIR/AppIcon.iconset/icon_16x16.png" >/dev/null
sips -z 32 32     /tmp/purezip_1024.png --out "$TMP_DIR/AppIcon.iconset/icon_16x16@2x.png" >/dev/null
sips -z 32 32     /tmp/purezip_1024.png --out "$TMP_DIR/AppIcon.iconset/icon_32x32.png" >/dev/null
sips -z 64 64     /tmp/purezip_1024.png --out "$TMP_DIR/AppIcon.iconset/icon_32x32@2x.png" >/dev/null
sips -z 128 128   /tmp/purezip_1024.png --out "$TMP_DIR/AppIcon.iconset/icon_128x128.png" >/dev/null
sips -z 256 256   /tmp/purezip_1024.png --out "$TMP_DIR/AppIcon.iconset/icon_128x128@2x.png" >/dev/null
sips -z 256 256   /tmp/purezip_1024.png --out "$TMP_DIR/AppIcon.iconset/icon_256x256.png" >/dev/null
sips -z 512 512   /tmp/purezip_1024.png --out "$TMP_DIR/AppIcon.iconset/icon_256x256@2x.png" >/dev/null
sips -z 512 512   /tmp/purezip_1024.png --out "$TMP_DIR/AppIcon.iconset/icon_512x512.png" >/dev/null
cp /tmp/purezip_1024.png "$TMP_DIR/AppIcon.iconset/icon_512x512@2x.png"

iconutil -c icns "$TMP_DIR/AppIcon.iconset" -o "$ROOT_DIR/Resources/AppIcon.icns"
echo "Generated $ROOT_DIR/Resources/AppIcon.icns"
