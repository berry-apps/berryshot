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
DIST_DIR="dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Version — single source of truth is AboutSettingsView.swift.
VERSION=$(grep -oE 'Text\("Version [v]?[0-9]+\.[0-9]+\.[0-9]+"\)' \
    Sources/App/Settings/AboutSettingsView.swift | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
VERSION=${VERSION:-0.0.0}

echo "Building $APP_NAME v$VERSION in release mode..."
swift build -c release

echo "Assembling app bundle at $APP_DIR ..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "Copying executable..."
cp ".build/release/$APP_NAME" "$MACOS_DIR/"

echo "Copying resources bundle..."
if [ -d ".build/release/BerryShot_BerryShot.bundle" ]; then
    cp -R ".build/release/BerryShot_BerryShot.bundle" "$RESOURCES_DIR/"
fi

echo "Copying MenuBarIcon to Resources..."
if [ -f "Sources/Resources/MenuBarIcon.png" ]; then
    cp "Sources/Resources/MenuBarIcon.png" "$RESOURCES_DIR/"
fi

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
    <string>13.0</string>
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
echo "   Run it with:  open \"$APP_DIR\""
echo "   Note: this build is UNSIGNED — Gatekeeper will block it on other Macs."
echo "   Signed/notarized release builds are produced by maintainers via deploy/."
