#!/bin/bash
set -e

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
echo "🚀 Bumping version: $OLD_VERSION -> $NEW_VERSION"
echo "====================================="

# Update AboutSettingsView.swift
sed -i '' "s/Text(\"Version $OLD_VERSION\")/Text(\"Version $NEW_VERSION\")/g" Sources/App/Settings/AboutSettingsView.swift
echo "✅ Updated Sources/App/Settings/AboutSettingsView.swift"

# Update build_app.sh
sed -i '' "s/<string>$OLD_VERSION<\/string>/<string>$NEW_VERSION<\/string>/g" build_app.sh
echo "✅ Updated build_app.sh"

# Update landingpage/index.html
sed -i '' "s/$OLD_VERSION/$NEW_VERSION/g" landingpage/index.html
echo "✅ Updated landingpage/index.html"

echo ""
echo "Running build_app.sh to generate DMG and ZIP..."
echo ""

./build_app.sh

echo "====================================="
echo "🎉 Release $NEW_VERSION built successfully!"
echo "Files are available in landingpage/assets/"
echo "====================================="
