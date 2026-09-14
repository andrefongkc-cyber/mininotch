#!/bin/bash
# Reports Settings rows that search cannot find, and index entries that no longer exist.
#
# The search index is a flat list, because SwiftUI cannot be asked which rows a pane
# contains. That means it can drift: add or rename a SettingsRow and forget the index, and
# search silently cannot find it. Run this after adding, renaming, or removing a row.
cd "$(dirname "$0")/.." || exit 1

python3 - <<'PY'
import re, glob, sys

def row_titles(src):
    # Row titles only: `title:` as its own label, never the tail of `subtitle:`.
    return {m.group(1) for m in re.finditer(r'SettingsRow\(\s*title:\s*"((?:[^"\\]|\\.)*)"', src)
            if '\\(' not in m.group(1)}

rows = set()
for path in glob.glob('MinNotch/UI/Settings/**/*.swift', recursive=True):
    if path.endswith('SettingsSearchIndex.swift'):
        continue
    rows |= row_titles(open(path).read())

index = open('MinNotch/UI/Settings/SettingsSearchIndex.swift').read()
indexed = set(re.findall(r'(?<![A-Za-z])title: "((?:[^"\\]|\\.)*)"', index))

missing, stale = sorted(rows - indexed), sorted(indexed - rows)
print(f"rows in panes: {len(rows)}   in index: {len(indexed)}")
if not missing and not stale:
    print("search index matches the panes")
    sys.exit(0)
if missing:
    print("not searchable, add to SettingsSearchIndex:")
    for t in missing: print("  " + t)
if stale:
    print("in the index but gone from the panes:")
    for t in stale: print("  " + t)
sys.exit(1)
PY
