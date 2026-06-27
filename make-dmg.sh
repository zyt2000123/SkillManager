#!/bin/bash
# Build the release binary and package SkillManager.dmg with an Applications shortcut.
# Use ./run.sh for development builds and launching; use this script for distribution.
set -e
cd "$(dirname "$0")"

swift build -c release

APP="SkillManager.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SkillManager "$APP/Contents/MacOS/SkillManager"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SkillManager</string>
<key>CFBundleIdentifier</key><string>com.skillmanager.app</string>
<key>CFBundleName</key><string>SkillManager</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
</dict></plist>
PLIST

# Stage the app with an /Applications symlink for drag-and-drop installation.
STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "SkillManager" -srcfolder "$STAGING" -ov -format UDZO SkillManager.dmg
rm -rf "$STAGING"
echo "created SkillManager.dmg"
