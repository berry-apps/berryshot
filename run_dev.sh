#!/bin/bash
set -e

APP_NAME="BerryShot"
DEV_APP="$APP_NAME-Dev.app"

echo "Building debug build..."
swift build

echo "Creating dev app bundle..."
rm -rf "$DEV_APP"
mkdir -p "$DEV_APP/Contents/MacOS"
mkdir -p "$DEV_APP/Contents/Resources"

cp .build/debug/$APP_NAME "$DEV_APP/Contents/MacOS/"

if [ -d ".build/debug/BerryShot_BerryShot.bundle" ]; then
    cp -R ".build/debug/BerryShot_BerryShot.bundle" "$DEV_APP/Contents/Resources/"
fi

# Info.plist với đầy đủ permission keys
cat << PLIST > "$DEV_APP/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.tan.berryshot.dev</string>
    <key>CFBundleName</key>
    <string>$APP_NAME Dev</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>dev</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>BerryShot needs screen capture access to take screenshots and record your screen.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>BerryShot needs microphone access to record audio along with your screen recordings.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>BerryShot uses speech recognition to transcribe meeting audio in real-time for Live Meeting Notes.</string>
</dict>
</plist>
PLIST

# Kill existing instance so fresh launch triggers permission dialog
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5

echo "Launching $DEV_APP..."
open "$DEV_APP"
echo ""
echo "App launched."
echo "Lần đầu chạy: dialog 'Speech Recognition' sẽ hiện ngay — ACCEPT để bật live transcription."
echo "Nếu dialog không hiện, chạy lệnh này để reset permission:"
echo "  tccutil reset SpeechRecognition com.tan.berryshot.dev"
