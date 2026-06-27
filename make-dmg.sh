#!/bin/bash
# 构建 release 版并打包成 SkillManager.dmg(含 Applications 拖拽链接,方便安装)。
# 开发期请用 ./run.sh(debug + 启动);本脚本用于分发。
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

# 暂存目录:.app + 指向 /Applications 的软链 → 用户拖拽即装
STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "SkillManager" -srcfolder "$STAGING" -ov -format UDZO SkillManager.dmg
rm -rf "$STAGING"
echo "created SkillManager.dmg"
