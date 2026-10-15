#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if ! xcrun --find xcodebuild >/dev/null 2>&1; then
    echo "Xcode mit iOS-SDK fehlt. Der Simulator-Test wurde nicht ausgeführt." >&2
    exit 1
fi
if [ "$#" -ne 1 ]; then
    echo "Aufruf: $0 <iPhone-Simulator-UUID>" >&2
    echo "Verfügbare Geräte: xcrun simctl list devices available" >&2
    exit 2
fi
case "$1" in *[!A-Fa-f0-9-]*|'') echo "Ungültige Simulator-UUID." >&2; exit 2;; esac
RESULT_DIR="$ROOT_DIR/TestResults/Simulator-$(date +%Y%m%d-%H%M%S)-$$.xcresult"
mkdir -p "$ROOT_DIR/TestResults"
xcodebuild -project "$ROOT_DIR/WerkstattApp.xcodeproj" -scheme Werkstatt \
    -destination "platform=iOS Simulator,id=$1" \
    -derivedDataPath "$ROOT_DIR/DerivedData" -resultBundlePath "$RESULT_DIR" \
    -only-testing:WerkstattUITests CODE_SIGNING_ALLOWED=NO test
