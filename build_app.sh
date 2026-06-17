#!/bin/bash
set -e

APP_NAME="BerryShot"
APP_DIR="$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Building $APP_NAME in release mode..."
swift build -c release

echo "Creating app bundle structure..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "Copying executable..."
cp .build/release/$APP_NAME "$MACOS_DIR/"

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
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "Generating AppIcon.icns..."
ICON_IMAGE="Sources/Resources/AppIcon.png"
ICONSET_DIR="AppIcon.iconset"
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
iconutil -c icns "$ICONSET_DIR"
cp AppIcon.icns "$RESOURCES_DIR/"
rm -rf "$ICONSET_DIR"
rm AppIcon.icns

# Force Finder to refresh the app icon
touch "$APP_DIR"

echo "Signing the app bundle with an ad-hoc signature to prevent repeated permission prompts..."
codesign --force --deep --sign - "$APP_DIR"

echo "Creating Zip archive..."
rm -f BerryShot.zip
zip -r BerryShot.zip "$APP_DIR" > /dev/null
cp BerryShot.zip landingpage/assets/

echo "Creating DMG package..."
rm -f BerryShot.dmg
hdiutil create -volname "BerryShot" -srcfolder "$APP_DIR" -ov -format UDZO BerryShot.dmg > /dev/null
cp BerryShot.dmg landingpage/assets/

echo "App bundle created at $APP_DIR, synced to landingpage/assets/"
