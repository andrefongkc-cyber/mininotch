#!/bin/bash
# Add a release's DMG to appcast.xml, the feed Sparkle reads to find updates.
#
#   Scripts/appcast.sh dist/MiniNotch-0.7.0.dmg
#   Scripts/appcast.sh <dmg> --url <where it will be downloaded> --feed <feed file>   # for testing
#
# Signs the DMG with the update key in this Mac's keychain (Sparkle's `sign_update`, account
# "mininotch") and writes an entry for it at the top of the feed, replacing any entry for the same
# version. The download URL defaults to the DMG on that version's GitHub release, so publish the
# release first, then commit and push the feed: the feed must never point at a file that is not
# there yet. Release.sh runs this for you.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

DMG=${1:?usage: Scripts/appcast.sh <dmg> [--url URL] [--feed FILE]}
shift
FEED="appcast.xml"
URL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --url) URL=$2; shift 2 ;;
    --feed) FEED=$2; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

NAME=$(basename "$DMG")
VERSION=${NAME#MiniNotch-}
VERSION=${VERSION%.dmg}
[ -n "$URL" ] || URL="https://github.com/andrefongkc-cyber/mininotch/releases/download/v$VERSION/$NAME"

# Sparkle's tools come with its package, wherever the last build resolved it.
SIGN=$(ls -1 build/release/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update \
  ~/Library/Developer/Xcode/DerivedData/MinNotch-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update 2>/dev/null | head -1 || true)
[ -n "$SIGN" ] || { echo "Sparkle's sign_update was not found: build the project once so the package resolves."; exit 1; }

SIGNATURE=$("$SIGN" --account mininotch "$DMG")
NOTES=$(Scripts/release-notes.sh --html)

python3 - "$FEED" "$VERSION" "$URL" "$SIGNATURE" "$NOTES" <<'PY'
import email.utils, os, re, sys

feed, version, url, signature, notes = sys.argv[1:6]
item = f"""    <item>
      <title>MiniNotch {version}</title>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{version}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.4</sparkle:minimumSystemVersion>
      <description><![CDATA[{notes}]]></description>
      <enclosure url="{url}" {signature} type="application/x-apple-diskimage"/>
    </item>
"""

if os.path.exists(feed):
    text = open(feed).read()
else:
    text = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>MiniNotch</title>
    <link>https://github.com/andrefongkc-cyber/mininotch</link>
    <description>MiniNotch updates</description>
    <language>en</language>
  </channel>
</rss>
"""

# One entry per version: publishing the same version again replaces it.
text = re.sub(r"    <item>\n(?:(?!</item>).)*?<sparkle:version>" + re.escape(version) + r"</sparkle:version>.*?</item>\n",
              "", text, flags=re.S)
marker = "    <language>en</language>\n"
assert marker in text, "The feed has no <language> line to put entries after"
text = text.replace(marker, marker + item, 1)
open(feed, "w").write(text)
print(f"{feed}: MiniNotch {version} -> {url}")
PY
