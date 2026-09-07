#!/usr/bin/env bash
set -euo pipefail

VERSION="$(cat VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
CONFIG="${1:-release}"

swift build -c "$CONFIG" --product Takat
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Takat"

APP="dist/Takat.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Takat"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" App/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"

# Ad-hoc sign so Gatekeeper is less hostile locally and SMAppService behaves.
codesign --force --deep --sign - "$APP"

echo "Built $APP ($VERSION build $BUILD)"
