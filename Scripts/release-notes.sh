#!/bin/bash
# Print the current release notes as Markdown, for a GitHub release description.
#
# Reads the same `ReleaseNotes.latest` the app shows in its What's New window, so the page
# people read on GitHub and the window they see on first launch cannot drift apart.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

python3 - MinNotch/Features/WhatsNew/ReleaseNotes.swift <<'PY'
import re, sys

source = open(sys.argv[1]).read()
block = source[source.index("static let latest"):]
version = re.search(r'version:\s*"([^"]*)"', block).group(1)

def field(entry, name):
    match = re.search(name + r':\s*"((?:[^"\\]|\\.)*)"', entry)
    if not match:
        return None
    return match.group(1).replace('\\"', '"').replace("\\u{201C}", "“").replace("\\u{201D}", "”")

print(f"# MinNotch {version}\n")
for key, heading in [("added", "New"), ("improved", "Improved"), ("removed", "Removed")]:
    section = re.search(key + r":\s*\[(.*?)\n\s*\],?\n", block, re.S)
    if not section:
        continue
    entries = re.findall(r"ReleaseNote\((.*?)\n\s*\)", section.group(1), re.S)
    if not entries:
        continue
    print(f"## {heading}\n")
    for entry in entries:
        title, detail, how = field(entry, "title"), field(entry, "detail"), field(entry, "howTo")
        line = f"- **{title}** — {detail}"
        if how:
            line += f" _{how}_"
        print(line)
    print()

print("Download the DMG below. It is not notarised, so the first time you open it, allow it")
print("under System Settings > Privacy & Security > Open Anyway.")
PY
