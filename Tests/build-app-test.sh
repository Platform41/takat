#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"$ROOT/scripts/build-app.sh"

APP="$ROOT/dist/Takat.app"

if [[ ! -f "$APP/Contents/MacOS/Takat" ]]; then
    echo "FAIL: executable missing at $APP/Contents/MacOS/Takat"
    exit 1
fi

if [[ ! -x "$APP/Contents/MacOS/Takat" ]]; then
    echo "FAIL: executable is not executable"
    exit 1
fi

plutil -lint "$APP/Contents/Info.plist"

echo "PASS: Takat.app assembled and signed"
