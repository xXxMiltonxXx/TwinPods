#!/usr/bin/env bash
# Builds the TwinPods menu bar app and the twinpods CLI. Requires Xcode command line tools.
set -euo pipefail
cd "$(dirname "$0")"

APP=TwinPods.app
rm -rf "$APP" twinpods dist && mkdir -p "$APP/Contents/MacOS" dist

swiftc -O Core.swift cli/main.swift -o twinpods
swiftc -O Core.swift menubar/main.swift -o "$APP/Contents/MacOS/TwinPods"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

ditto -c -k --keepParent "$APP" dist/TwinPods.app.zip
cp twinpods dist/twinpods
echo "Built: $APP, twinpods, dist/"
