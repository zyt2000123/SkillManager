#!/bin/bash
# Build + package as .app + launch. Must run as .app (not `swift run`) so the
# macOS Translation framework gets a bundle identity — bare binaries fail with internalError.
set -e
cd "$(dirname "$0")"
swift build
APP="SkillManager.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/debug/SkillManager "$APP/Contents/MacOS/SkillManager"
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

# 移除隔离属性，避免"软件已损坏"提示
xattr -cr "$APP"

pkill -9 -f SkillManager 2>/dev/null || true
sleep 1
open "$APP"
echo "launched"
