#!/bin/bash
set -e

# ---------------------------------------------------------------------------
# BerryShot — public build script
#
# Compiles BerryShot and assembles an UNSIGNED `BerryShot.app` bundle into
# ./dist. This is all an open-source contributor needs to build and run the
# app locally.
#
# Code signing, notarization, DMG/ZIP packaging and release/upload are
# maintainer-only steps and live outside this repository (in the gitignored
# `deploy/` directory). See deploy/package-release.sh and deploy/release.sh.
# ---------------------------------------------------------------------------

APP_NAME="BerryShot"
HELPER_NAME="BerryShotMCP"
DIST_DIR="dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
HELPERS_DIR="$CONTENTS_DIR/Helpers"

# Version — single source of truth is AboutSettingsView.swift.
VERSION=$(grep -oE 'Text\("Version [v]?[0-9]+\.[0-9]+\.[0-9]+"\)' \
    Sources/App/Settings/AboutSettingsView.swift | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
VERSION=${VERSION:-0.0.0}

echo "Building $APP_NAME v$VERSION in release mode..."
# `swift build -c release` (no --product) builds every product in
# Package.swift, i.e. both the `BerryShot` GUI and the `BerryShotMCP` MCP
# stdio helper, from one invocation.
swift build -c release

echo "Assembling app bundle at $APP_DIR ..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$HELPERS_DIR"

echo "Copying executable..."
cp ".build/release/$APP_NAME" "$MACOS_DIR/"

# `02-target-architecture.md` section 6 locks this bundle-relative path:
# `BerryShot.app/Contents/Helpers/BerryShotMCP`. MCP clients (Codex, Claude
# Code) spawn this helper directly by absolute path — see the "Agent
# Integration (MCP)" section of README.md. The helper must be included in
# nested code-signing (helper signed *before* the outer app bundle) and
# notarization by maintainer release tooling; see deploy/ (gitignored).
echo "Copying MCP helper..."
cp ".build/release/$HELPER_NAME" "$HELPERS_DIR/"
chmod 0755 "$HELPERS_DIR/$HELPER_NAME"

echo "Copying resources bundle..."
if [ -d ".build/release/BerryShot_BerryShot.bundle" ]; then
    cp -R ".build/release/BerryShot_BerryShot.bundle" "$RESOURCES_DIR/"
fi

echo "Copying MenuBarIcon to Resources..."
if [ -f "Sources/Resources/MenuBarIcon.png" ]; then
    cp "Sources/Resources/MenuBarIcon.png" "$RESOURCES_DIR/"
fi

# LSMinimumSystemVersion must match Package.swift's `platforms: [.macOS(.v14)]`
# (`09-test-release-github-runbook.md` release gate #3: "Generated Info.plist
# minimum OS matches Package.swift"). Both the `BerryShot` and `BerryShotMCP`
# products build from the one package-wide platforms declaration, so they
# always share this minimum OS already; this only keeps the *bundle metadata*
# Gatekeeper/launchd read in sync with the actual compiled requirement.
echo "Generating Info.plist..."
cat << PLIST > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.tan.berryshot</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>BerryShot needs screen capture access to take screenshots and record your screen.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>BerryShot needs microphone access to record audio along with your screen recordings.</string>
    <key>NSCameraUsageDescription</key>
    <string>BerryShot needs camera access for future video recording features.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>BerryShot uses speech recognition to transcribe meeting audio in real-time for Live Meeting Notes.</string>
</dict>
</plist>
PLIST

echo "Generating AppIcon.icns..."
ICON_IMAGE="Sources/Resources/AppIcon.png"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
sips -s format png -z 16 16     "$ICON_IMAGE" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null
sips -s format png -z 32 32     "$ICON_IMAGE" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
sips -s format png -z 32 32     "$ICON_IMAGE" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null
sips -s format png -z 64 64     "$ICON_IMAGE" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
sips -s format png -z 128 128   "$ICON_IMAGE" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null
sips -s format png -z 256 256   "$ICON_IMAGE" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
sips -s format png -z 256 256   "$ICON_IMAGE" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null
sips -s format png -z 512 512   "$ICON_IMAGE" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
sips -s format png -z 512 512   "$ICON_IMAGE" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null
sips -s format png -z 1024 1024 "$ICON_IMAGE" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

# Force Finder to refresh the app icon
touch "$APP_DIR"

echo ""
echo "✅ Built unsigned bundle: $APP_DIR"
echo "   MCP helper:   $HELPERS_DIR/$HELPER_NAME"
echo "   Run it with:  open \"$APP_DIR\""
echo "   Note: this build is UNSIGNED — Gatekeeper will block it on other Macs."
echo "   Signed/notarized release builds (helper signed before the app bundle,"
echo "   then packaged/notarized) are produced by maintainers via deploy/."
