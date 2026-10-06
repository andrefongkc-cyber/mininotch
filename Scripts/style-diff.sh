#!/bin/bash
# Captures the notch in a fixed set of states with two builds and compares them pixel for pixel.
#
#   Scripts/style-diff.sh <baseline MiniNotch.app> [candidate MiniNotch.app] [--keep <dir>]
#
# Exists for the Notch Style system: Minimal Dark must draw exactly what the app drew before
# styles existed. Save a build from before a change (copy the .app somewhere), then run this
# against the current Debug build. Every case is still: playback paused, sample data, the glow
# off. A case that differs prints how many pixels and where, and leaves a red-marked image beside
# the two captures. The glow is not here: even paused it settles for longer than a capture waits,
# so two runs of one build differ by up to 20 levels across it. Review it by eye.
#
# Both builds run back to back with the same real settings, so anything a capture reads from this
# Mac (the volume a HUD shows, the outputs list) is the same for both.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE_APP="${1:?usage: style-diff.sh <baseline .app> [candidate .app] [--keep dir]}"
shift
CAND_APP="$HOME/Library/Developer/Xcode/DerivedData/MinNotch-avnshenachkfkhfqnbkrwwgicfxl/Build/Products/Debug/MiniNotch.app"
OUT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --keep) OUT="$2"; shift 2 ;;
        *) CAND_APP="$1"; shift ;;
    esac
done
[ -n "$OUT" ] || OUT="$(mktemp -d)/style-diff"
mkdir -p "$OUT/base" "$OUT/cand"

# The comparer is compiled once and kept beside the captures' parent folder.
DIFF_TOOL="${TMPDIR:-/tmp}/mininotch-png-diff"
if [ ! -x "$DIFF_TOOL" ] || [ "$ROOT/Scripts/png-diff.swift" -nt "$DIFF_TOOL" ]; then
    swiftc -O "$ROOT/Scripts/png-diff.swift" -o "$DIFF_TOOL" || exit 2
fi

binary() { echo "$1/Contents/MacOS/$(defaults read "$1/Contents/Info" CFBundleExecutable)"; }
BASE_BIN="$(binary "$BASE_APP")"
CAND_BIN="$(binary "$CAND_APP")"

# name | arguments after --capture-notch <file>
CASES=(
    "media-classic|--tab media --paused --glow off"
    "media-compact|--tab media --paused --glow off --card compact"
    "media-full|--tab media --paused --glow off --card fullArtwork"
    "media-lyrics|--tab media --paused --glow off --lyrics-sheet"
    "media-shadow|--tab media --paused --glow off --shadow"
    "calendar|--tab calendar --sample-calendar --paused --glow off"
    "system|--tab system --sample-stats --sample-power --paused --glow off"
    "shelf|--tab shelf --sample-shelf --paused --glow off"
    "clipboard|--tab clipboard --paused --glow off"
    "clipboard-blur|--tab clipboard --blur-clipboard --paused --glow off"
    "timer|--tab timer --paused --glow off"
    "weather|--tab weather --sample-weather --paused --glow off"
    "notes|--tab notes --sample-notes --paused --glow off"
    "keep-open|--tab media --paused --glow off --keep-open"
    "closed-playing|--collapsed --extended --paused --glow off"
    "closed-empty|--collapsed --extended --no-media --glow off"
    "closed-weather|--collapsed --extended --sample-weather --paused --glow off"
    "peek|--collapsed --extended --peek --paused --glow off"
    "hud-inline|--collapsed --hud-style notchInline --paused --glow off"
    "hud-ring|--collapsed --hud-style progressRing --paused --glow off"
    "hud-pill|--collapsed --hud-style floatingPill --paused --glow off"
    "virtual-closed|--virtual --collapsed --extended --paused --glow off"
    "virtual-open|--virtual --tab media --paused --glow off"
)

failures=0
compare() {
    local name="$1"
    local result
    result="$("$DIFF_TOOL" "$OUT/base/$name.png" "$OUT/cand/$name.png" "$OUT/$name-diff.png")"
    if [ $? -eq 0 ]; then
        printf "ok    %-16s identical\n" "$name"
    else
        printf "DIFF  %-16s %s\n" "$name" "$result"
        failures=$((failures + 1))
    fi
}

for entry in "${CASES[@]}"; do
    name="${entry%%|*}"
    args="${entry#*|}"
    # shellcheck disable=SC2086
    "$BASE_BIN" --capture-notch "$OUT/base/$name.png" --builtin $args >/dev/null 2>&1
    # shellcheck disable=SC2086
    "$CAND_BIN" --capture-notch "$OUT/cand/$name.png" --builtin $args >/dev/null 2>&1
    compare "$name"
done

# The lock screen window, and the Settings > Layout miniatures, draw the same components.
for variant in "lock-hud|--hud" "lock-media|"; do
    name="${variant%%|*}"; args="${variant#*|}"
    # shellcheck disable=SC2086
    "$BASE_BIN" --capture-lock-screen "$OUT/base/$name.png" $args >/dev/null 2>&1
    # shellcheck disable=SC2086
    "$CAND_BIN" --capture-lock-screen "$OUT/cand/$name.png" $args >/dev/null 2>&1
    compare "$name"
done
"$BASE_BIN" --capture-layout "$OUT/base/layout" >/dev/null 2>&1
"$CAND_BIN" --capture-layout "$OUT/cand/layout" >/dev/null 2>&1
for file in "$OUT/base/layout"/*.png; do
    name="layout/$(basename "$file" .png)"
    mkdir -p "$OUT/layout"
    compare "$name"
done

echo
echo "captures in $OUT"
if [ "$failures" -eq 0 ]; then echo "ok    every case identical"; else echo "DIFF  $failures cases differ"; fi
exit $((failures > 0))
