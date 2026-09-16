#!/bin/bash
# Build a Release copy of MinNotch and wrap it in a DMG people can download.
#
#   Scripts/release.sh              # signed with this machine's team, from Config/Local.xcconfig
#   Scripts/release.sh --anonymous  # re-signed ad-hoc, so the DMG carries no team or Apple ID
#
# The DMG lands in dist/ and the script prints the command that publishes it as a GitHub
# release. Nothing is uploaded or pushed here.
#
# --anonymous exists because a signature made with a personal Apple team carries the Apple ID
# it was issued to: `codesign -dvvv` on the app shows it to anyone who downloads the DMG.
# Stripping it costs the people who install it two things, so it is not the default: the system
# audio permission cannot be granted to an ad-hoc build at all, so Follow the Beat is dead for
# them, and every permission they grant resets on the next version they install.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

ANONYMOUS=0
for argument in "$@"; do
  case "$argument" in
    --anonymous) ANONYMOUS=1 ;;
    *) echo "Unknown option: $argument"; exit 1 ;;
  esac
done

VERSION=$(xcodebuild -project MinNotch.xcodeproj -showBuildSettings -configuration Release 2>/dev/null \
  | awk -F' = ' '/ MARKETING_VERSION =/ {print $2; exit}')
[ -n "$VERSION" ] || { echo "Could not read MARKETING_VERSION"; exit 1; }

NOTES_ID=$(grep -m1 'id: "' MinNotch/Features/WhatsNew/ReleaseNotes.swift | sed 's/.*id: "\([^"]*\)".*/\1/')
if [ "$NOTES_ID" != "$VERSION" ]; then
  echo "Warning: ReleaseNotes.latest.id is \"$NOTES_ID\" but the version is \"$VERSION\"."
  echo "         Nobody updating from an older build will see the What's New window."
  echo
fi

BUILD_DIR="build/release"
STAGE="build/dmg/MinNotch"
DMG="dist/MinNotch-$VERSION.dmg"

echo "Building MinNotch ${VERSION} (Release)..."
rm -rf "$BUILD_DIR" "build/dmg"
xcodebuild -project MinNotch.xcodeproj -scheme MinNotch -configuration Release \
  -derivedDataPath "$BUILD_DIR" build 2>&1 \
  | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)" | sort -u

APP="$BUILD_DIR/Build/Products/Release/MinNotch.app"
[ -d "$APP" ] || { echo "No app was built"; exit 1; }

mkdir -p "$STAGE" dist
cp -R "$APP" "$STAGE/MinNotch.app"
# The usual drag-to-install layout: the app beside a shortcut to Applications.
ln -s /Applications "$STAGE/Applications"

if [ "$ANONYMOUS" = "1" ]; then
  echo "Re-signing ad-hoc, keeping the entitlements the build produced..."
  ENTITLEMENTS="build/dmg/entitlements.plist"
  codesign -d --entitlements "$ENTITLEMENTS" --xml "$STAGE/MinNotch.app" 2>/dev/null
  codesign --force --sign - --options runtime --entitlements "$ENTITLEMENTS" "$STAGE/MinNotch.app"
fi

echo "Packing ${DMG}..."
rm -f "$DMG"
hdiutil create -volname "MinNotch" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
hdiutil verify "$DMG" >/dev/null && echo "DMG verified"

echo
echo "Signed as:"
codesign -dvvv "$STAGE/MinNotch.app" 2>&1 | grep -E "^Authority=Apple Development|^Signature=adhoc|^TeamIdentifier" || true
echo
echo "$DMG  ($(du -h "$DMG" | cut -f1))"
echo "sha256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo
echo "To publish it, with the release notes as the description:"
echo
echo "  gh release create v$VERSION \"$DMG\" --title \"MinNotch ${VERSION}\" --notes-file <(Scripts/release-notes.sh)"
echo
echo "Downloads are not notarised, so tell people to open it once from"
echo "System Settings > Privacy & Security > Open Anyway."
