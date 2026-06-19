#!/bin/bash
set -e

# Load .env file
if [ -f .env ]; then
    source .env
    echo "✅ Loaded .env file"
fi

# Verify APP_SPEC_PASSWORD is available (without showing the value)
if [ -n "$APP_SPEC_PASSWORD" ]; then
    echo "✅ APP_SPEC_PASSWORD is set (length: ${#APP_SPEC_PASSWORD})"
else
    echo "⚠️  APP_SPEC_PASSWORD is not set"
fi

if [ -z "$1" ]; then
  echo "Usage: ./release.sh <new_version>"
  echo "Example: ./release.sh 1.0.2"
  exit 1
fi

NEW_VERSION=$1
# Remove 'v' prefix if user accidentally includes it
NEW_VERSION=${NEW_VERSION#v}

# Find the old version from AboutSettingsView.swift
OLD_VERSION=$(grep -oE 'Text\("Version [v]?[0-9]+\.[0-9]+\.[0-9]+"\)' Sources/App/Settings/AboutSettingsView.swift | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
OLD_VERSION=${OLD_VERSION#v}

if [ -z "$OLD_VERSION" ]; then
  echo "Error: Could not determine old version from AboutSettingsView.swift"
  exit 1
fi

echo "====================================="
# Escape dots for sed
OLD_VERSION_ESCAPED=$(echo "$OLD_VERSION" | sed 's/\./\\./g')

echo "🚀 Bumping version: $OLD_VERSION -> $NEW_VERSION"

# Update version in Swift UI Settings View
sed -i '' "s/Text(\"Version $OLD_VERSION\")/Text(\"Version $NEW_VERSION\")/g" Sources/App/Settings/AboutSettingsView.swift
echo "✅ Updated Sources/App/Settings/AboutSettingsView.swift"

# Update version in build_app.sh Info.plist generation
# Info.plist has `<string>1.0.2</string>`
sed -i '' "s/<string>$OLD_VERSION<\/string>/<string>$NEW_VERSION<\/string>/g" build_app.sh
echo "✅ Updated build_app.sh"

# Update version in landing page download links
sed -i '' "s/v=${OLD_VERSION_ESCAPED}/v=${NEW_VERSION}/g" landingpage/index.html
sed -i '' "s/Release: ${OLD_VERSION_ESCAPED}/Release: ${NEW_VERSION}/g" landingpage/index.html
sed -i '' "s/Version ${OLD_VERSION_ESCAPED}/Version ${NEW_VERSION}/g" landingpage/index.html
sed -i '' "s/\"softwareVersion\": \"${OLD_VERSION_ESCAPED}\"/\"softwareVersion\": \"${NEW_VERSION}\"/g" landingpage/index.html
echo "✅ Updated landingpage/index.html"

echo ""
echo "Running build_app.sh to generate DMG and ZIP..."
echo ""

./build_app.sh

echo "====================================="
echo "🎉 Release $NEW_VERSION built successfully!"
echo "Files are available in landingpage/assets/"
echo "====================================="
