#!/bin/bash
# Build and (re)launch MinNotch, replacing any running copy.
set -o pipefail
cd "$(dirname "$0")/.." || exit 1

CONFIG="${1:-Debug}"

# Building re-signs the app, and an ad-hoc signature changes with the binary, so every build
# voids the app's granted permissions. Pass --no-build to relaunch the existing build and
# keep Calendar and Automation access.
if [ "$1" = "--no-build" ] || [ "$2" = "--no-build" ]; then
  CONFIG="Debug"
else
  "$(dirname "$0")/build.sh" "$CONFIG" || exit 1
fi

pkill -x MinNotch 2>/dev/null
sleep 0.5

APP="$(xcodebuild -project MinNotch.xcodeproj -scheme MinNotch -configuration "$CONFIG" \
        -showBuildSettings 2>/dev/null \
        | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}' | head -1)/MinNotch.app"
open "$APP" && echo "Launched $APP"
