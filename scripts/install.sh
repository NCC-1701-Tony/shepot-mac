#!/bin/zsh
# Builds Release and installs Dictate into /Applications.
# A fixed location + the "Dictate Local" certificate keep macOS permissions and login item stable.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Сборка Release…"
xcodebuild -project Dictate.xcodeproj -scheme Dictate -configuration Release -derivedDataPath build build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

# Quit any running copy (Xcode run or an older install).
pkill -x Dictate 2>/dev/null || true
sleep 1

rm -rf /Applications/Dictate.app
cp -R build/Build/Products/Release/Dictate.app /Applications/
echo "Установлено в /Applications/Dictate.app"
open /Applications/Dictate.app
