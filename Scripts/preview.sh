#!/bin/bash
# Render the notch views to PNGs for design review, then open the folder.
#
# The notch is a borderless overlay panel, so it cannot be captured with the usual
# screenshot tooling without granting Screen Recording. This renders the same views
# offscreen instead, in both light and dark appearance, using fixed sample data.
set -o pipefail
cd "$(dirname "$0")/.." || exit 1

OUT="${1:-Previews}"
"$(dirname "$0")/build.sh" Debug || exit 1

BIN="$(xcodebuild -project MinNotch.xcodeproj -scheme MinNotch -configuration Debug \
        -showBuildSettings 2>/dev/null \
        | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}' | head -1)/MinNotch.app/Contents/MacOS/MinNotch"

rm -rf "$OUT"
"$BIN" --render-previews "$OUT" || exit 1
ls -1 "$OUT"
