#!/usr/bin/env bash
set -euo pipefail

if [ -f ".signing.local" ]; then
    # shellcheck disable=SC1091
    source .signing.local
fi

: "${TAKAT_SIGN_ID:?set TAKAT_SIGN_ID to a Developer ID Application identity}"
NOTARY_PROFILE="${TAKAT_NOTARY_PROFILE:-takat-notary}"
VERSION="$(cat VERSION)"

./scripts/build-app.sh release

APP="dist/Takat.app"
ZIP="dist/Takat-$VERSION.zip"

ditto -c -k --keepParent "$APP" "$ZIP"

xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -vvv -t install "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "Release artifact: $ZIP"
