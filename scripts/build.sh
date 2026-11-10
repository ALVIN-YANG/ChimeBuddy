#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app=".build/ChimeBuddy.app"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources"
cp Assets/codex-companion-atlas.png "$app/Contents/Resources/codex-companion-atlas.png"
cp Assets/codex-companion.png "$app/Contents/Resources/codex-companion.png"
cp Assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
swiftc -swift-version 5 -target arm64-apple-macos14.0 Sources/*.swift -o "$app/Contents/MacOS/ChimeBuddy" -framework AppKit
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.chimebuddy.prototype</string>
<key>CFBundleName</key><string>ChimeBuddy</string>
<key>CFBundleExecutable</key><string>ChimeBuddy</string>
<key>CFBundleShortVersionString</key><string>0.2.1</string>
<key>CFBundleVersion</key><string>5</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
