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

echo "Copying resources bundle..."
if [ -d ".build/release/BerryShot_BerryShot.bundle" ]; then
    cp -R ".build/release/BerryShot_BerryShot.bundle" "$RESOURCES_DIR/"
fi

echo "Copying MenuBarIcon to app bundle root Resources..."
if [ -f "Sources/Resources/MenuBarIcon.png" ]; then
    cp "Sources/Resources/MenuBarIcon.png" "$RESOURCES_DIR/"
fi

echo "Copying AppIcon.icns to app bundle root Resources..."
if [ -f "Sources/Resources/AppIcon.icns" ]; then
    cp "Sources/Resources/AppIcon.icns" "$RESOURCES_DIR/"
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
    <string>1.1.4</string>
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

echo "Generating Entitlements for Hardened Runtime..."
cat << ENTITLEMENTS > BerryShot.entitlements
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.device.camera</key>
    <true/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

echo "Signing the app bundle..."
SIGNING_IDENTITY="Developer ID Application: Vu Dong (WZ2Z528AM6)"

# Sign nested bundles first
if [ -d "$RESOURCES_DIR/BerryShot_BerryShot.bundle" ]; then
    codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$RESOURCES_DIR/BerryShot_BerryShot.bundle"
fi

# Sign main app bundle
codesign --force --options runtime --entitlements BerryShot.entitlements --sign "$SIGNING_IDENTITY" "$APP_DIR"
rm BerryShot.entitlements

# Verify signature
echo "Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "Creating Zip archive..."
rm -f landingpage/assets/BerryShot.zip
/usr/bin/ditto -c -k --keepParent "$APP_DIR" landingpage/assets/BerryShot.zip

echo "Creating DMG package..."
rm -f landingpage/assets/BerryShot.dmg
DMG_STAGING_DIR="dmg_staging"
rm -rf "$DMG_STAGING_DIR"
mkdir -p "$DMG_STAGING_DIR"
cp -R "$APP_DIR" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

hdiutil create -volname "BerryShot" -srcfolder "$DMG_STAGING_DIR" -ov -format UDZO landingpage/assets/BerryShot.dmg > /dev/null
rm -rf "$DMG_STAGING_DIR"

echo "Signing the DMG..."
codesign --force --sign "$SIGNING_IDENTITY" landingpage/assets/BerryShot.dmg

echo "Cleaning up temporary build files..."
rm -rf "$APP_DIR"

if [ -n "$APP_SPEC_PASSWORD" ]; then
    echo "Submitting DMG to Apple Notary Service..."
    xcrun notarytool submit landingpage/assets/BerryShot.dmg \
        --apple-id "vdong1804@gmail.com" \
        --password "$APP_SPEC_PASSWORD" \
        --team-id "WZ2Z528AM6" \
        --wait

    echo "Stapling ticket to DMG..."
    xcrun stapler staple landingpage/assets/BerryShot.dmg
    
    # Verify notarization
    echo "Verifying notarization..."
    xcrun stapler validate landingpage/assets/BerryShot.dmg
    
    echo "✅ Notarization complete!"
else
    echo "--------------------------------------------------------"
    echo "⚠️  APP_SPEC_PASSWORD is not set. Skipping Notarization."
    echo "To auto-notarize, run this command in Terminal once before building:"
    echo "export APP_SPEC_PASSWORD='your-app-specific-password'"
    echo ""
    echo "Generate App-Specific Password at: https://appleid.apple.com/account/manage"
    echo "Section: Sign-In and Security > App-Specific Passwords"
    echo "--------------------------------------------------------"
    echo ""
    echo "⚠️  Without notarization, the app will be BLOCKED by Gatekeeper on other machines!"
fi

# Generate SHA256 hash of DMG (after notarization/stapling if applicable)
echo "Generating SHA256 hash..."
DMG_HASH=$(shasum -a 256 landingpage/assets/BerryShot.dmg | awk '{print $1}')
echo "DMG SHA256: $DMG_HASH"
# Save hash to file for release.sh to use
echo "$DMG_HASH" > landingpage/assets/BerryShot.dmg.sha256

echo "App bundle packaged successfully and saved to landingpage/assets/"
