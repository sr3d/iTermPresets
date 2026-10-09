#!/bin/bash
# Builds iTermPresets.app (release) into ./build. Usage: ./build-app.sh [--install]
#   --install  also copies the app into /Applications
# Environment:
#   VERSION=1.2.0  version shown in About (default 1.0)
#   BUILD=42       build number (default 1)
#   UNIVERSAL=1    build for Apple silicon and Intel (needs Xcode, not just the Command Line Tools)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0}"
BUILD="${BUILD:-1}"
ARCH_FLAGS=()
if [[ "${UNIVERSAL:-}" == "1" ]]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/iTermPresets"
APP=build/iTermPresets.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/iTermPresets"
cp Icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>iTerm Presets</string>
    <key>CFBundleDisplayName</key><string>iTerm Presets</string>
    <key>CFBundleIdentifier</key><string>com.sr3d.iTermPresets</string>
    <key>CFBundleExecutable</key><string>iTermPresets</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>iTerm Presets asks iTerm to run your preset scripts. It never closes iTerm windows.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/iTermPresets.app"
    cp -R "$APP" /Applications/
    echo "Installed /Applications/iTermPresets.app"
fi
