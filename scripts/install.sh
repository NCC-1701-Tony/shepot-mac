#!/bin/zsh
# Builds Release and installs Shepot into /Applications.
# A fixed location + the "Dictate Local" certificate keep macOS permissions and login item stable.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Сборка Release…"
xcodebuild -project Shepot.xcodeproj -scheme Shepot -configuration Release -derivedDataPath build build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

# Quit any running copy (Xcode run, an older install, or the app under its old name Dictate).
pkill -x Shepot 2>/dev/null || true
pkill -x Dictate 2>/dev/null || true
sleep 1

rm -rf /Applications/Shepot.app /Applications/Dictate.app
cp -R build/Build/Products/Release/Shepot.app /Applications/
echo "Установлено в /Applications/Shepot.app"
open /Applications/Shepot.app
