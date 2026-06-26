#!/bin/bash
set -e

# Load .env file
if [ -f .env ]; then
    set -a
    source .env
    set +a
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

echo "🔄 Checking out main and pulling latest code..."
git checkout main
git pull --rebase --autostash origin main
echo "✅ Code is up to date"

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

# Update version in landing page download links (match any old version)
sed -i '' "s/v=[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/v=${NEW_VERSION}/g" landingpage/index.html
sed -i '' "s/\(Release: \)[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/\1${NEW_VERSION}/g" landingpage/index.html
sed -i '' "s/\(Version \)[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/\1${NEW_VERSION}/g" landingpage/index.html
sed -i '' "s/\(\"softwareVersion\": \"\)[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/\1${NEW_VERSION}/g" landingpage/index.html
echo "✅ Updated landingpage/index.html"

echo ""
echo "Running build_app.sh to generate DMG and ZIP..."
echo ""

./build_app.sh

# Update DMG hash in landing page
DMG_HASH_FILE="landingpage/assets/BerryShot.dmg.sha256"
if [ -f "$DMG_HASH_FILE" ]; then
    DMG_HASH=$(cat "$DMG_HASH_FILE")
    # Update hash in HTML (replace existing hash or add new one)
    sed -i '' "s/data-hash=\"[a-f0-9]*\"/data-hash=\"$DMG_HASH\"/g" landingpage/index.html
    sed -i '' "s/SHA256: [a-f0-9]\{64\}/SHA256: $DMG_HASH/g" landingpage/index.html
    echo "✅ Updated DMG hash in landing page: $DMG_HASH"
fi

# Generate version.json for the app to check updates
cat <<EOF > landingpage/assets/version.json
{
  "version": "$NEW_VERSION",
  "url": "https://notex.work/assets/BerryShot.dmg",
  "releaseNotes": "A new version of BerryShot is available!"
}
EOF
echo "✅ Generated landingpage/assets/version.json"

echo ""
echo "📦 Committing and pushing to git..."
git add .
git commit -m "chore: release v$NEW_VERSION"
git tag -a "v$NEW_VERSION" -m "Release v$NEW_VERSION"
git push origin HEAD
git push origin "v$NEW_VERSION"
echo "✅ Git push and tag completed"

echo "====================================="
echo "🎉 Release $NEW_VERSION built successfully!"
echo "Files are available in landingpage/assets/"
echo "====================================="
