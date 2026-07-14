#!/bin/bash
# BerryShot Diagnostic Script
# Run this on the machine where the app doesn't start

echo "=== BerryShot Diagnostic ==="
echo ""

# Check if app exists
APP_PATH="/Applications/BerryShot.app"
if [ ! -d "$APP_PATH" ]; then
    # Try to find in DMG
    DMG_PATH=$(find ~/Downloads -name "BerryShot*.dmg" 2>/dev/null | head -1)
    if [ -n "$DMG_PATH" ]; then
        echo "Found DMG: $DMG_PATH"
        echo "Please drag BerryShot.app to /Applications first, then run this script again."
        exit 1
    else
        echo "❌ BerryShot.app not found in /Applications or ~/Downloads"
        exit 1
    fi
fi

echo "✅ Found BerryShot.app at $APP_PATH"

# Check code signature
echo ""
echo "=== Code Signature Check ==="
codesign -vvv "$APP_PATH" 2>&1 || echo "❌ Code signature verification failed"

# Check Gatekeeper status
echo ""
echo "=== Gatekeeper Check ==="
spctl --assess --type execute --verbose=2 "$APP_PATH" 2>&1 || echo "❌ Gatekeeper assessment failed"

# Check notarization
echo ""
echo "=== Notarization Check ==="
xcrun stapler validate "$APP_PATH" 2>&1 || echo "❌ Stapler validation failed"

# Check app info
echo ""
echo "=== App Info ==="
defaults read "$APP_PATH/Contents/Info" CFBundleIdentifier 2>/dev/null || echo "❌ Cannot read Info.plist"
defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "❌ Cannot read version"

# Check if app can be launched
echo ""
echo "=== Launch Test ==="
echo "Attempting to launch app..."
open "$APP_PATH" 2>&1
sleep 2

# Check if process is running
if pgrep -x "BerryShot" > /dev/null; then
    echo "✅ BerryShot is running!"
    echo "Check the menu bar (top right) for the BerryShot icon."
else
    echo "❌ BerryShot is not running"
    echo ""
    echo "=== Recent Crash Logs ==="
    find ~/Library/Logs/DiagnosticReports -name "BerryShot*" -mtime -1 2>/dev/null | while read f; do
        echo "Crash log: $f"
        tail -20 "$f"
        echo "---"
    done
fi

echo ""
echo "=== System Info ==="
sw_vers
echo ""
echo "=== Diagnostic Complete ==="
