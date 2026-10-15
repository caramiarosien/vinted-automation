#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if ! xcrun --find xcodebuild >/dev/null 2>&1; then
    echo "Xcode mit iOS-SDK fehlt. Bitte Xcode installieren und einmal öffnen; Command Line Tools allein genügen nicht." >&2
    exit 1
fi
xcodebuild -project "$ROOT_DIR/WerkstattApp.xcodeproj" -scheme Werkstatt \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$ROOT_DIR/DerivedData" CODE_SIGNING_ALLOWED=NO build
