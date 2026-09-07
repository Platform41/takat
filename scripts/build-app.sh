#!/usr/bin/env bash
set -euo pipefail

if [ -f ".signing.local" ]; then
    # shellcheck disable=SC1091
    source .signing.local
fi

VERSION="$(cat VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
CONFIG="${1:-release}"
SIGN_ID="${TAKAT_SIGN_ID:-}"

swift build -c "$CONFIG" --product Takat
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Takat"

APP="dist/Takat.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Takat"
if [ -f "App/Takat.icns" ]; then
    cp "App/Takat.icns" "$APP/Contents/Resources/Takat.icns"
fi
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" App/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"

if [ -n "$SIGN_ID" ]; then
    codesign --force --options runtime --timestamp \
        --entitlements App/Takat.entitlements \
        --sign "$SIGN_ID" "$APP/Contents/MacOS/Takat"
    codesign --force --options runtime --timestamp \
        --entitlements App/Takat.entitlements \
        --sign "$SIGN_ID" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
else
    codesign --force --sign - "$APP"
    echo "⚠ ad-hoc signed (set TAKAT_SIGN_ID to Developer-ID sign)"
fi

echo "Built $APP ($VERSION build $BUILD)"
