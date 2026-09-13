#!/bin/bash
# Build MinNotch and print only warnings/errors plus the final status.
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
CONFIG="${1:-Debug}"
xcodebuild -project MinNotch.xcodeproj -scheme MinNotch -configuration "$CONFIG" build 2>&1 \
  | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)" \
  | sort -u
