# MinNotch

A macOS utility that lives in the notch. Closed, it is a thin black pill showing battery and
what is playing. Hover or click and it expands into a panel with Now Playing, a mini
calendar, and system information.

Requires macOS 14 or later. Works on Macs without a physical notch, which get a virtual one
in the same place.

## Building

Open `MinNotch.xcodeproj` in Xcode 16 or later and run, or from the terminal:

```bash
Scripts/run.sh
```

Building re-signs the app, and because it is currently signed ad-hoc rather than with a real
identity, that resets every permission you have granted it. To relaunch the existing build
without losing them:

```bash
Scripts/run.sh --no-build
```

The app has no Dock icon. It appears as a pill at the top of the screen and, unless you turn
it off, as a menu bar icon. Press ⌃⌥N to open or close it.

The first launch opens a short welcome tour. It explains how to use the notch, lets you pick
which features to switch on from a list with a recommended starting point, and says what each
permission is for before anything asks. Skip it whenever you like; it is available again from
Settings › Advanced › Show Welcome Again.

## What it does today

- **Now Playing** for Apple Music, Spotify, and a system-wide fallback that covers other
  apps. Album art, a scrubber you can drag to seek, transport controls, and optional lyrics.
- **Calendar** showing the current week or month with your upcoming events, from the system
  Calendar, with per-calendar visibility.
- **Battery** in the pill and in more detail when expanded, with a low-battery alert.
- **System stats** for CPU, GPU, memory, and network, sampled only while you are looking at
  them, plus the charge of connected AirPods and other accessories.
- **Reminders** mixed into the upcoming list, tickable from the notch, with a quick-add field
  for new events and reminders.
- **Shelf** to park files on the notch and drag them out somewhere else.
- **HUDs** showing volume, brightness, and keyboard backlight at the notch.
- **Ambient lighting** around the notch, the panel, or the album art, in five styles, with
  colours taken from the cover. It follows the beat when the system audio permission can be
  granted, and animates on its own when it cannot.
- **Clipboard history** for text, links, colours, and images, with pinning. Kept in memory
  only, never written to disk, and it skips anything an app marks as private.
- **Timer and Pomodoro** with four rhythms, quick countdowns, and a custom length. A running
  timer shows in the closed pill.
- **Floating Now Playing window**, for an external display with no notch to look at.
- **Two-finger swipes** to change tab or open and close, with optional haptics.
- **Drag-to-arrange layouts** for the transport controls, the closed pill's two sides, and
  the panel's top strip.
- **Settings** in a separate window laid out like macOS System Settings, with search: press
  ⌘F and type, and choosing a result takes you straight to the setting.

Some panes contain controls marked "Coming soon". Those settings are saved and will apply
once the feature ships. See `WORKPLAN.md`.

## Permissions

MinNotch asks for nothing at launch. It requests access the first time a feature needs it:

- **Calendar and Reminders** to show your events.
- **Automation** to read and control Music and Spotify.
- **Notifications** for the low-battery alert and timer completion.
- **System audio recording** only if you switch the ambient lighting's audio-reactive option
  on. The sound becomes a handful of numbers and is discarded; nothing is recorded or stored.

Everything stays on your Mac with one exception, and it is off by default. Setting
**Media → Lyrics Source** to look up online sends the current track's title, artist, album,
and length to `lrclib.net` to fetch synced lyrics. Nothing else leaves the machine, there are
no accounts, no analytics, and no telemetry. Clipboard history is held in memory only.

## Repository layout

`CLAUDE.md` documents the architecture and the pitfalls worth knowing before changing
anything. `WORKPLAN.md` tracks what is built and what comes next.

There is no test target yet, and no licence has been chosen, so all rights are reserved by
default until one is added.

## A note on signing

This project has no code signing identity, so builds are ad-hoc signed. That has three
consequences worth knowing before you file a bug: the system audio permission cannot be
granted at all, every rebuild resets every other permission you have granted, and the app
cannot be notarised or distributed. A free Apple ID is enough to fix the first two.
