#!/bin/zsh
# Builds Release and packs it into dist/Dictate-<version>.dmg for sharing:
# the app, an Applications shortcut to drag onto, and a short install guide.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Сборка Release…"
xcodebuild -project Dictate.xcodeproj -scheme Dictate -configuration Release -derivedDataPath build build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

APP=build/Build/Products/Release/Dictate.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="dist/Dictate-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Программы"
cp scripts/dmg-readme.txt "$STAGE/Как установить.txt"

# Volume icon = app icon.
cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
SetFile -a C "$STAGE" 2>/dev/null || true

mkdir -p dist
rm -f "$DMG"
hdiutil create -volname "Dictate" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "Готово: $DMG ($(du -h "$DMG" | cut -f1))"
