# MinNotch workplan

Status: 0.4.0 released 2026-09-24 (GitHub v0.4.0); next: the user tries 0.4 by hand (see "Do these next" 0), then the macOS 13 decision.

Living document. Update the checkboxes as work lands. `CLAUDE.md` holds the architecture
rules and the traps; this file holds the sequence.

Status key: `[x]` done, `[~]` partially done, `[ ]` not started.

---

## Where things stand

The app is well past V1. Everything originally scoped as V1 is built, and most of what was
scoped as V2 is too: HUDs, the shelf, reminders, gestures, haptics, system stats, Bluetooth
accessory charge, ambient lighting, clipboard history, a timer, a first-launch tutorial,
Settings search, a link shelf, release notes, and as of 2026-09-22 the whole "gaps in what is
built" list below. 133 Swift files in Swift 6 language mode, building with no warnings.
Published at github.com/andrefongkc-cyber/mininotch.

**The blocker is gone.** The app is signed with a free personal team as of 2026-09-15, so
permissions should stop resetting on every build and the system audio permission is reachable
at last. Notarisation still needs a paid membership nobody is buying.

**Do these next, in this order:**

0. 0.4.0 shipped on 2026-09-24 at the user's request ("just release") before this was done. Watch
   for reports, and the user tries 0.4 by hand: dragging in Settings > Layout, closed lyrics with a real song,
   the shelf's multi-file drag and AirDrop, switching outputs with a second one connected, the
   lock screen media controls (do they clear the lock screen clock?), the weather location
   prompt, and a real meeting's countdown and Join.
1. Answer the user on macOS 13 (Platforms below). They were asked and have not decided.
2. A test target. Nothing is verified automatically across more than a hundred files, and the
   Swift 6 migration is exactly the kind of change one would have caught.
3. Confirm a granted permission survives a rebuild (listed under Blocking below).
4. Watch for reports against 0.3.0, released 2026-09-23. It shipped at the user's request
   without these being tried by hand, so they are the first place to look: the drag-and-drop
   in Settings > Layout, the calendar against a real calendar, repeat and favourite against a
   playing track, downloads, a device connecting, and the album-art bars with real music.

---

## 0.4 additions (2026-09-24)

Picked by the user from a list of ideas. Focus was dropped: macOS has no API to switch it, and
its state file needs Full Disk Access, so the only way was Shortcuts the user builds by hand.
Sparkle was asked about and deferred ("not now"); it is free (MIT) and needs no paid account.

- [x] Next meeting countdown in the pill, with Join for Zoom, Meet, Teams, Webex, FaceTime links.
- [x] Shelf: select and drag several files at once; AirDrop from the shelf. Dragging and the AirDrop picker need trying by hand.
- [x] Audio output switcher and volume on the Now Playing card. Switching needs trying with a second output connected.
- [x] Media controls on the lock screen, beside the HUD that is already there. Needs a locked Mac to see: check it clears the lock screen clock.
- [x] Weather: location or a typed city, Open-Meteo, a tab and a pill indicator. The location prompt needs trying by hand.

## 0.3 feedback (2026-09-23)

The user's first round on 0.3, with screenshots. In the order they are being done.

- [x] Panel Shadow splits the panel on open: the conditional `.shadow` swaps the surface's view
      identity, so the content is re-inserted at its final size mid-spring.
- [x] Closed glow is thinner at the sides than the bottom on the real screen: the pill's body is
      inset by the shoulder radius, so with the pill at the notch's width the glow's sides sit
      9 pt inside the camera housing. Trace the housing instead while the pill is notch-sized.
- [x] Up Next off for now (`FeatureFlag.upNext`): Music's `shuffle enabled` does not match what
      is playing, so it claimed a playlist was shuffling when it was not.
- [x] Glow Tempo defaults to From the Song.
- [x] "Match to the Audio" (now "Fix Timing Automatically") reads like Follow the Beat. Rename it so it says it is about lyrics.
- [x] Sneak peek length is a setting (Media > Display > Sneak Peek Length).
- [x] Closed pill: the song as its own indicator, title or artist (default title), instead of the
      artist riding in the Live Activity slot and widening both flanks; artwork shows while
      paused; the playing indicator no longer disappears whenever there is artwork.
- [x] Layout editor: dropping anywhere left of an icon now lands before it (a drop off an icon
      always appended, so moving left needed a pixel-perfect hit), with a marker where it will
      land. The closed pill's miniature shows what the pill is really showing.
- [x] Lyrics with the notch closed, a strip the size of the sneak peek.
- [x] "New" badges in Settings for rows added in the current release.
- [x] Tutorial lists every permission, with Allow Now for Accessibility and system audio too.
- [x] HUDs on the lock screen, through a SkyLight space above it (private API). Confirmed working
      on a locked Mac by the user on 2026-09-24.
- [x] A Show Lyrics When Closed button on the lyric strip, left of the expand button.
- [x] Then update the GitHub page (README) for all of the above, and push. Asked for 2026-09-23.
      Features not in a download yet are marked _(0.4)_ in the README.
- [x] 0.4.0 release notes written and `MARKETING_VERSION` bumped, because the "New" badges key
      on the release. No DMG built: the user has not tried this batch yet.

## Blocking

- [x] **Real signing.** Done 2026-09-15 with a free personal team: `CODE_SIGN_STYLE = Automatic`
      plus `ENABLE_RESOURCE_ACCESS_AUDIO_INPUT = YES`, and the team itself in the gitignored
      `Config/Local.xcconfig` (see `Config/Local.xcconfig.example`) rather than in the
      repository. The built app signs with the hardened runtime (`flags=0x10000(runtime)`), a
      real team identifier, and `com.apple.security.device.audio-input`.

      What that leaves open:

      - [ ] Confirm a TCC grant actually survives a rebuild now, instead of assuming it.
      - [x] The audio tap works. Signing alone was not enough: the request also has to be made
            from the foreground, since macOS shows the prompt only to the active app and
            `AudioHardwareCreateProcessTap` blocks rather than refusing. `ForegroundPrompt` now
            wraps it, and `--check-audio` received audio on 8 of 8 checks against a real sound.
      - [ ] Notarisation and a double-click install for others still need a paid Developer ID,
            which the user is not buying, so shared builds stay a DMG that needs
            Privacy & Security > Open Anyway. Anyone else building the repo must set their own
            team or signing fails.

## Built and working

### Notch surface
- [x] Borderless non-activating `NSPanel` above the menu bar, on every Space
- [x] `NotchShape` with concave shoulders and a rounded bottom
- [x] Collapsed pill, expanded panel, spring transition, hover intent with dwell delay
- [x] Closed pill matches the hardware notch exactly by default, with an opt-in extended
      mode that shows battery and playback either side of the cutout
- [x] Open and close is one spring on one geometry value, with content clipped to the shape
      and nothing about the fill depending on state, so the box only ever grows and shrinks
- [x] Click to open, close on pointer exit, tab strip
- [x] Geometry from the real hardware notch (`safeAreaInsets` + auxiliary menu bar areas)
- [x] Virtual notch on displays without one, sized from Settings > Advanced
- [x] Multi-display: follow the pointer, built-in only, or all displays
- [x] A display with no physical notch opens on its own tab, `advanced.nonNotchDefaultTab`,
      defaulting to Timer. A real notch hides behind the camera housing so an idle pill there
      costs nothing; a virtual one on an external monitor has nothing to blend into. Virtual
      surfaces also no longer write `general.lastTab`, which two instances used to clobber.
- [x] `peek()` state for the V2 sneak-peek animation

### Now Playing
- [x] Apple Music and Spotify through Apple Events, including seek
- [x] System-wide source through MediaRemote, with an honest availability report
- [x] Automatic source selection with stickiness to the last active player
- [x] Push updates via distributed notifications, slow poll for position only
- [x] Artwork, colour palette extraction, scrubber with drag-to-seek, timecodes
- [x] Transport controls driven by `MediaSettings.controlOrder`
- [x] Lyrics: local LRC from the player, plus an opt-in LRCLIB lookup that returns real
      synced lyrics. Empty states explain themselves rather than rendering nothing.
- [x] Word-level highlighting, from enhanced LRC stamps where available and estimated from
      line length otherwise
- [x] Lyric timing corrected at three points: the capture timestamp, a user offset, and the
      output device's reported buffering
- [x] LRCLIB results matched on track duration, so a remix or live cut cannot supply timings
- [x] Artwork refetched on a retry schedule, which is what makes autoplay tracks show a cover
- [x] Floating window: the same card in a small movable panel above other apps, for external
      displays that have no notch to look at. Settings > Media > Display > Floating Window.
      Sized from `NowPlayingCardView.preferredHeight`, so switching lyrics on does not clip
      the strip, and its position is remembered between launches.
- [x] Visualizer bars readable on any cover. They were drawn in the cover's own dominant
      colours with a black outline, so on a dark sleeve they vanished. Now lifted colours with a
      light rim and a soft glow, over a dark scrim that fades up from the artwork's bottom edge.
      Checked on dark, near-white, and mid-tone covers, before and after.
- [x] Pop-out button on the Now Playing card, beside the effects button, that opens and closes
      the floating window. Same stored setting as Settings, so they cannot disagree; the card
      inside the floating window shows it in its open state, which puts the window away.

### Calendar
- [x] EventKit with full-access request and a denied-state path into System Settings
- [x] Week and month grid, event dots, today highlight, localised weekday order
- [x] Upcoming list with in-progress badge, per-calendar show/hide grouped by account
- [x] Refreshes on `EKEventStoreChanged` plus a slow timer for the moving "now"

### Battery
- [x] IOKit power sources with run-loop notifications, no polling
- [x] Pill readout with percentage toggle, expanded detail with time remaining
- [x] Low-battery notification with threshold, re-armed on charge
- [x] Power adapter connect/disconnect notification

### Settings
- [x] Panel top strip: tabs, settings button, and battery arranged either side of the
      cutout, with all readable content below it
- [x] `NavigationSplitView` window with all twelve panes and System Settings styling
- [x] General, Appearance, Media, Calendar, Battery fully wired
- [x] HUDs, Shelf: real persisted controls, disabled and badged
- [x] Shortcuts: click-to-record with conflict detection
- [x] Advanced: display targeting, sizing, export/import/reset, diagnostics
- [x] About: version, system summary, quit

### Platform and build
- [x] Carbon global hotkeys, ⌃⌥N bound to toggle by default, no Accessibility prompt
- [x] Launch at login via `SMAppService`, reconciled against System Settings at launch
- [x] Optional menu bar item
- [x] Settings export/import as one file, lenient decoding, migration hook
- [x] Feature flags with no free/paid assumption baked in
- [x] Offscreen preview renderer plus a real AppKit layer capture for design review
- [x] A real `Config/Info.plist` instead of `GENERATE_INFOPLIST_FILE`, after the latter
      silently dropped `NSAudioCaptureUsageDescription`
- [x] Deployment target raised to macOS 14.4 for Core Audio process taps
- [x] Debug tools backed by a throwaway settings store, after a preview run was found to be
      overwriting the user's real configuration

---

## Immediate follow-ups

Known gaps in what is already built, after the signing blocker above.

- [x] **Calendar: pick a day, move between weeks and months.** A tester reported they could not
      change days: the grid's cells were not clickable and there was no way off the current
      week or month. Now arrows step a week or a month, clicking a day lists that day (again,
      or Today, goes back), another week lists all of that week, dots cover every day a
      multi-day event spans, and Quick Add puts a new item on the picked day at 9 AM. Checked
      with `--capture-notch --tab calendar --sample-calendar --calendar-pick 1` and
      `--calendar-step 1`; not yet against a real calendar, since the Debug build has no
      Calendar grant.
- [x] **One Layout pane, drawn as the notch.** The three arrangement editors (closed pill, top
      bar, media controls) were text chips in dashed lanes, spread over three panes. The user
      asked for icons, like TheBoringNotch's slot editor. Settings > Layout now has one
      `IconLayoutEditor` per surface, a miniature with the camera cutout in it and a tray of
      icons (drag or click to place, drag back or × to remove), plus widget tiles that switch
      each tab's feature on and off. Rendered with `--capture-layout` in both appearances; the
      drag and drop itself has not been tried by hand yet.
- [x] **App icon.** Done 2026-09-21 from the user's artwork (a dark tile with the notch pill).
      `swift Scripts/make-icon.swift <artwork.png>` redraws it in Apple's grid (824 tile on a
      1024 canvas, continuous corners, transparent surround, drop shadow) and writes every size
      plus `Contents.json`, because the artwork itself filled the canvas edge to edge on opaque
      black. macOS 26 shows it as a normal icon, not inside a grey tile. Mention it in the next
      release's notes.
- [x] **First-launch tutorial.** Five pages: welcome, a checklist of fourteen features
      starting from a Recommended preset (with Everything and Minimal), how to get around,
      what will be asked for with optional "Allow Now" buttons, and done. Skippable from any
      page; closing the window counts as skipping. Every checkbox reads and writes the real
      setting it stands for. Rerun from Advanced > Show Welcome Again, which starts the
      checklist from the current settings instead of the preset. Verify with
      `--capture-onboarding`.
- [x] **Settings search.** A search field at the top of the sidebar, ⌘F to focus. Matches
      panes by name and synonyms, and rows by title, card header, and subtitle, ranked.
      Choosing a row opens its pane, scrolls to it, and flashes it. Check ranking with
      `--check-settings-search`, and index coverage with `Scripts/audit-search.sh`.
- [ ] **Tests.** No test target exists. The first ones worth writing, in order:
      `LRCParser`, `SettingsSnapshot` lenient decoding and migration, `NotchGeometry` for
      notched and non-notched displays, `CalendarService.days(for:)` across month boundaries
      and week-start settings.
- [x] **Swift 6 language mode.** Done 2026-09-22: 278 complete-checking warnings to zero, then
      `SWIFT_VERSION = 6.0`, no warnings, Debug and Release. Services and windows are
      `@MainActor`; off-main framework callbacks are explicitly `@Sendable` (see CLAUDE.md for
      why that is a crash, not a style point); timers go through `Timer.onMain`. Three real
      races fixed on the way. Every check and capture tool runs clean, and the audio tap
      received sound on 6 of 6 checks. Not yet run as the user's everyday copy.
- [x] **Source app badge on the artwork.** The playing app's icon sits on the artwork's corner
      (Settings > Media > Show Which App Is Playing, on by default). The scriptable players
      know their bundle identifier; the system source now asks MediaRemote for the owning
      process (`MRMediaRemoteGetNowPlayingApplicationPID`) instead of guessing from the
      frontmost app, and shows no badge rather than a wrong one when it cannot tell.
- [x] **Panel height on tab change.** Checked every tab with `--capture-notch` on 2026-09-21,
      including the new card styles and the lyrics list: nothing clipped and nothing drifting.
      Clipboard and Links keep room under a short list because the list area is a fixed
      scrolling height, not because the constant is wrong. No measuring needed; revisit only
      if a capture shows a mismatch.
- [x] **Lyrics scrolling view.** The strip has an expand button that swaps it for every line
      (`LyricsSheetView`, 176 pt): the current line stays centred and highlighted word by word,
      sung lines stay readable, and clicking a synced line seeks there through
      `seek(toLyricsTime:)`, which undoes the offset and audio correction so the click lands
      on the line. The choice is on `NowPlayingController` so the floating window sizes for it
      too. Captured with `--capture-notch --tab media --lyrics-sheet`.
- [x] **Stats history.** The last 30 readings of CPU, GPU, memory and network sit behind each
      cell as a faint sparkline (`SparklineShape`, a `Shape` so a capture can see it), newest
      on the right. Kept only while the tab is on screen, since sampling stops when it is not;
      the baseline read of each delta stays out. Network is scaled to its own peak with a
      64 KB/s floor. Captured with `--capture-notch --tab system --sample-stats`.
- [x] **Lyrics caching.** `LyricsCache`: raw LRC text on disk in Caches, keyed by a hash of
      artist, title, album, and rounded length, kept 180 days. A successful search that finds
      nothing is remembered for 3 days; a network failure is never cached. Deleted when the
      online lookup is switched off. Replay went from 675 ms to 8 ms in `--check-lyrics`.

---

## Settings audit

Every persisted setting is now read by something. Previously 21 were saved and wired to
nothing.

- [x] Artwork tint, debug layout overlay, haptics, two-finger gestures and sensitivity
- [x] Bluetooth accessory charge, read from the IO registry
- [x] Reminders, hide-completed, and quick add, including ticking a reminder off from the notch
- [x] Shelf: drop, persist as bookmarks, drag out with a real copy or move operation, item
      limit, clear on quit, and open-on-drag
- [x] HUDs for volume, brightness, and keyboard backlight, with three indicator styles
- [x] Visualizer, including a custom animated image
- [x] Ambient glow around the notch edge, on the same pulse as the bars, cycled from one
      button on the Now Playing card
- [x] Lyric timing offset, and the capture-time fix behind it
- [x] Reversible swipe direction
- [x] Hiding the system volume and brightness overlay
- [x] Haptic strength, since macOS offers patterns rather than an amplitude
- [x] `showOnLockScreen` deleted on the belief macOS has no lock screen surface for third-party
      apps; wrong, and back in 0.4 through a private SkyLight space (see 0.3 feedback)

## Ambient lighting

- [x] Five styles behind one `AmbientGlowStyle` protocol: Pulse, Wave, Bars, Chase, Rainbow
- [x] Three placements, multi-select: album art, closed notch, open panel
- [x] Colour modes, intensity, speed, and glow radius shared across every style
- [x] Live preview in Settings > Appearance, with every control in one card
- [x] Output latency compensation for lyric timing, read from the active output device
- [x] Beat sources beyond live audio. Settings > Appearance > Ambient Lighting > Tempo: the Speed
      slider (as before), Set by Hand (a BPM slider and a Tap button; the median of recent taps
      sets the tempo and the last tap sets where beats fall), or From the Song (Music's `bpm`
      tag, laid on the song's own position so a seek moves the beats with it; Spotify shares
      none, so it falls back to Speed). Used only while the glow is not following live audio.
      `--check-glow --source tempo` confirms hits land on the grid from its origin.
- [x] Style switching from the notch itself: option-click or right-click the effects button
- [x] Placement switching from the notch itself, in the same menu, so "no light on the closed
      pill but light on the open panel" does not mean opening the Settings window
- [x] Non-audio fallback animation for every style, so it works with no permission. Emits
      impulses through the same shaping chain as real audio, so it is a stand-in for the
      signal rather than a separate animation, and the motion can be judged without the
      permission this machine cannot be granted.
- [x] Attack and decay envelope, rolling auto-gain, a hand-stepped spring, and onset
      detection in `GlowDynamics`, so a hit rises within a frame, overshoots, and settles
      instead of the level sliding around. Verify with `--check-glow`.
- [x] Decibel band weighting with a per-band tilt in the analyser, replacing a per-buffer
      normalisation that pinned some band to full scale on every frame
- [x] Level drives geometry, not only brightness: stroke width, Bars' arc length, Wave and
      Chase length, and the blur radius all ride the shaped level
- [x] Timeline at the display's own rate while playing. Measured as free: the panel's cost
      does not change with the frame cap.
- [x] **"Anything animating costs a core" was a measurement artefact, not a bug.** The capture
      tool held the panel by turning `RunLoop.main` by hand, which makes SwiftUI's animation
      driver spin. Under a real `NSApp.run()`: closed notch idle 0%, closed with glow 16%, open
      media card 12%, open card with glow 21%, hidden glow 0%. The tool now holds inside the real
      run loop. Capping the glow at 30 fps would bring it to 10%; left at full rate on purpose.
- [x] Audio-reactive layer via a Core Audio process tap and a vDSP FFT, with band energy and
      onset detection. Replaced an earlier ScreenCaptureKit implementation, which asked for
      screen recording in order to read sound. **Partly verified**: the tap is created, the
      aggregate device is built, the IO proc fires, and buffers arrive. They are silent,
      because macOS would not raise the system audio permission prompt for the ad-hoc signed
      build it was written against, so the FFT, banding, and onset threshold remain unexercised
      against real signal until 2026-09-15, when signing plus `ForegroundPrompt` made the tap
      run: `--check-audio` saw energy 0.59 and live bands on a real sound. What the effect
      looks like driven by real audio, rather than by the fallback, is still unreviewed.
- [x] Cross-fade the glow between the closed and open outlines. When it is on for only one of
      the two states it now fades in and out on the surface's own spring, instead of popping.
- [x] **The glow outline grows with the box.** The cause was not `GeometryReader`, whatever
      the earlier note said: with the glow off for the closed notch and on for the open panel,
      the glow view was *inserted* when the notch opened, and an inserted view takes its final
      layout at once. Now it stays in place and is hidden with `isVisible`, which also pauses
      its timeline, so hidden costs 0% CPU and leaves no pixels. Measured with `--midway` and
      `--placements open`: 494 px of fill against 1,092 px of glow before; overhang within the
      glow's normal spread at every point after.
- **Tidal cannot be added.** The macOS app is Electron and ships no scripting dictionary, so
  there is no Apple Events channel to put a source on. A Tidal source would be a source that
  never returns anything, which is the inert-control problem in a different costume.
- **Spotify has no queue.** Its dictionary exposes the current track, the position, and the
  player state, and nothing else. An Up Next row would be permanently empty for Spotify.
- **Music can approximate a queue** by reading `current playlist` and locating the current
  track in it. That is playlist context, not Music's real Up Next, and it costs an
  AppleScript round trip of ~100 ms per read on the shared serial queue.
- **VLC does ship a dictionary** and is a genuine candidate. It was not installed on the
  development machine, so nothing has been written against it yet.

- [x] VLC as a named `AppleScriptMediaSource`, in the automatic order after Music and Spotify
      and before the system source, because it can seek and the system source cannot. VLC
      knows only the file, so "Artist - Title.mp3" is split into the two (checked by
      `--check-media`); it has no shuffle, repeat, favourite or artwork, and those controls
      are left off the card for it. Its `play` toggles, so play and pause check `playing`
      first. Not compiled against VLC's dictionary, since VLC is not installed here.
- [x] Up Next, Apple Music only. Read once per track (and again after shuffle flips) from
      `current playlist` and the current track's index, since Music exposes no real queue.
      With shuffle on, or when playing from somewhere with no playlist, the row says why
      instead of guessing. Setting: Media > Display > Show Up Next. Scripts compile against
      Music's dictionary (`--check-media --scripts`); a live read needs the Automation grant.

---

## V2 — media

- [x] **Sneak peek on track change.** A small drop below the pill with the cover, title, and
      artist for 2.6 s, not the full panel the first version opened. Only for a track that is
      playing, never over an open panel, and a HUD outranks it. Any source, not only Music.
      Review with `--capture-notch --collapsed --peek`.
- [x] **Match lyrics to the audio.** `LyricsSyncCalibrator` measures how far a lyric file sits
      from the music by watching for a voice entering after a five second gap in the lyrics,
      takes the median across at least three of them, and refuses when they disagree. Settings >
      Media > Match to the Audio, with the current correction shown in the row.
      `--check-lyric-sync` recovers a known offset to 0.01 s and refuses an instrumental.
- [x] **The glow stands still when nothing is playing.** The fallback used to breathe when
      paused, which read as the effect following music badly and made the real thing unprovable.
      Settings > Appearance > Ambient Lighting now also shows a live meter of what the tap hears.
- [x] **Feed the artwork visualizer from the audio analyser.** While the tap runs, the analyser's
      bands are averaged into the five bars and shaped by their own `GlowDynamics`, so they
      strike like the glow does; otherwise they run on the pulse as before. Builds; not yet
      watched against real music.
- [x] **Card styles.** Compact is one row (56 pt cover, title, controls) over a full-width
      scrubber with the timecodes either side; Full Artwork puts the cover large on the left
      over a blurred, darkened copy of itself that fills the card. The blur is an overlay on a
      plain colour, because a filled image as a ZStack child sized the background to itself
      and spread over the whole panel. Captured with `--capture-notch --tab media --card
      compact` and `--card fullArtwork`.
- [x] **Draggable control layout.** (Superseded by Settings > Layout, see above.) One `SlotLayoutEditor` component, used three times: the
      media transport row (Settings > Media), the closed pill's two flanks (General), and the
      open panel's trailing top strip (Appearance). Drag to reorder, drag between sides, drag
      out to remove.
- [x] **Up Next under shuffle.** Confirmed live by the user's screenshot (the row read Music).
      With shuffle on, the next song genuinely cannot be read: no queue in Music's dictionary,
      and its saved `PlaybackSessions` archive holds only the current item. The row now names
      what is shuffling instead: "Shuffling “Playlist”. Music doesn't share the order."
- [x] Shuffle on Apple Music and Spotify: state read into every snapshot, the button shows it,
      flips instantly and is confirmed by the read-back. Added to existing arrangements once by
      the version 2 settings migration, since it could not be chosen before.
- [x] Real commands for repeat and favourite. The scripts existed; what was missing was reading
      the state back. The snapshot now reads `song repeat` / `repeating` and `favorited` (with
      `loved` as a fallback for older Music), the buttons show the accent when on and
      `repeat.1` for one song, and change at once before the read-back confirms. Spotify has
      no like or save in its dictionary, so favourite is Music only and left off the card for
      Spotify rather than drawn dead. All scripts compile (`--check-media --scripts`); not yet
      read live, since neither player was running.
- [x] **Custom visualizer image.** Shipped as an animated image rather than Lottie, since
      `NSImageView` plays GIF and APNG with no third-party renderer.

## V2 — Live Activities

- [x] **AirPods and Bluetooth battery.** Not IOBluetooth, which would need the Bluetooth
      permission: a registry first-match notification on the same charge-reporting classes the
      System tab reads (`startWatchingConnections`), read two seconds later once the charge is
      published, shown for six seconds as a live activity. Earbuds collapse into one device at
      the lower bud. Settings > Layout > Devices Connecting, on by default. Builds; not yet
      seen with a real device connecting.
- [x] **General-purpose activities.** The timer was the first client. Downloads are the second:
      `DownloadsMonitor` watches the Downloads folder for browsers' temporary files
      (`.download`, `.crdownload`, `.part`, `.partial`, `.opdownload`), reads progress from the
      `NSProgress` a browser publishes for the file (as Finder does) or Safari's `Info.plist`,
      and shows a tick for five seconds when the file lands. Off by default, since it needs the
      Downloads folder permission (`NSDownloadsFolderUsageDescription`, asked from the
      foreground). `--check-downloads` plays out Chrome, Safari and a cancelled download in a
      scratch folder and passes. Two-finger swipes on the closed pill cycle activities (already
      wired) and a swipe up now puts away a download or device notice, never a running timer.

## V2 — calendar and productivity

- [ ] Reminders with no due date. Only dated ones appear, because the list is ordered by
      time and an undated item has nowhere to sit.
- [ ] Focus / Do Not Disturb toggle, plus adapting the UI to the active Focus mode.
- [x] Pomodoro and countdown timer, surfaced as a Live Activity. Built as one thing: a
      deadline-based countdown, with Pomodoro as a preset that decides what follows an
      interval. Settings > Timer. Cycle verified: work, short break, work, long break.
- [x] Four Pomodoro rhythms, Classic, Deep Work, Short, and 52/17, plus Custom. Any of them
      can be started from the notch without changing the configured one.
- [x] Eight quick countdown lengths, a free-entry custom amount, and add-a-minute while
      running.
- [x] A running timer shows in the closed pill as a Live Activity, glyph and countdown, and
      sits beside the artwork rather than replacing it.
- [ ] Quick notes scratchpad that persists between opens.
- [x] Clipboard history. Polled, because there is no push API. Text, links, colours, and
      images, with pin, clear, and click-to-copy-back. Settings > Advanced > Clipboard.
      Kept in memory only, and honours the `org.nspasteboard` concealed marker.

## V2 — system utilities

- [x] **Hide Apple's volume and brightness overlay on macOS 26.** The user still saw both
      overlays: on macOS 26 the overlay is not drawn by `OSDUIHelper` (it was suspended, state T,
      and the overlay still appeared). `SystemKeyInterceptor` now takes the volume, mute and
      brightness keys with an event tap, `HUDCoordinator` sets the level and shows only MinNotch's
      indicator. Needs Accessibility; HUDs pane warns and links to it when missing. Proven with
      `--check-keys --simulate --control`: a posted volume-up moved the volume 0 → 0.0625 with no
      tap, and not at all with the tap. Keyboard backlight keys are left to macOS.
- [x] **Overlay suppression without the flicker.** *(Removed: did nothing on macOS 26, see above.
      Launch still resumes a helper an older build left suspended.)* Suspends `OSDUIHelper` with `SIGSTOP` once,
      starting it quietly with `launchctl kickstart` first if needed, instead of killing it after
      every key press. A suspended helper cannot draw and launchd does not replace it. Resumed when
      the setting goes off, on quit, and at any launch with the setting off, which undoes a crash.
      Only engaged while at least one MinNotch indicator is on. `--check-osd` shows the state
      change (S, T with the same PID, S again); not yet confirmed with a real volume key press.
- [x] **Link shelf.** Links tab: drag a link or a text selection onto the panel, press ⌘V or
      Paste, and links are found with `NSDataDetector` (a bare domain is kept as HTTPS). Only
      `http`/`https` are accepted, so a row can never open a local file or launch an app. Each
      row shows the page title and site icon, read once per link from the page through a
      truncating, redirect-following `BoundedHTTPClient`; icons cached in Caches by host hash.
      Click opens in the default browser, a copy button copies, X removes, Clear empties. Kept
      in UserDefaults across launches, capped in Settings > Advanced > Link Shelf (5 to 100).
      Dragging a link over the closed notch opens the tab; a file still opens the Shelf.
      `--check-links` verified real titles and icons for four sites, refused `file:` and
      `javascript:`, and read the list back from disk.
- [ ] **Shelf polish.** Dragging several files out at once, and a Quick Share target.
- [ ] Weather widget.
- [x] System stats: CPU, GPU, memory, and network, sampled only while the System tab is
      open, with a refresh interval in Settings > Advanced
- [ ] Quick-launch row for favourite apps.
- [ ] Shortcuts widget triggering a macOS Shortcut.
- [ ] Screen recording, camera, and microphone in-use indicators.
- [ ] "Boring mirror": front camera preview with shape options.
- Widgets on the lock screen: the earlier "will not do" was wrong. No public window level reaches
  the lock screen, but a private SkyLight space at absolute level 400 does, and the HUD uses one as
  of 2026-09-23 (`LockScreenSpace`). Media controls there would be the same mechanism.

## V2 — customisation

- [x] **Arrangeable top bar, tabs included.** Settings > Appearance > Top Bar: two lanes, left
      and right of the notch, holding every tab plus settings and battery. Tabs can be moved but
      not removed (switching the feature off hides its tab). `TopStripLayout` places them: what
      does not fit on its side crosses to the other, keeping order, then buttons tighten from 28
      to 21 points, and only then does `NotchGeometry` widen the panel. Fixes the seventh tab
      (Links) hiding the timer behind the camera housing. Review with
      `--capture-notch --tab links --width 460` and `--right timer,settings,battery`.
- [x] **What's New window.** `ReleaseNotes.latest` (0.3.0): New, Improved, Removed, each with
      where to find it. Shown once at launch when its id is unseen, skipped on a first launch
      (the tutorial runs instead), reopenable from the menu bar. `MARKETING_VERSION` matches
      it. Review with `--capture-whats-new`. Update the notes before each shared build.
- [x] **Debug buttons in the top bar.** What's New (sparkles) and Tutorial (graduation cap) open
      from the open panel, right of the notch. Settings > Advanced > Debug Buttons in Top Bar,
      on by default in Debug builds only. Movable in Top Bar, not removable there.
- [x] **Sneak peek bars move.** `PeekPlayingBars` replaces the still waveform: four bars on
      `VisualizerPulse` at 2.4x tempo with its middle half stretched to full height, in the lifted
      cover colours, paused when playback is. Three `--peek --hold` captures show different heights.

- [ ] Gesture vocabulary beyond swipe. Pinch to expand is the obvious next one.
- [ ] Notch sizing refinements beyond the current height and width controls.

---

## Security

Audited against a generic web-app checklist, most of which does not apply: no server, no
database, no accounts, no cookies, and no third-party dependencies. What did apply is done.

- [x] Every outbound request goes through `BoundedHTTPClient`: HTTPS with a host required,
      a body cap enforced as it arrives, same-host redirects only, and a timeout. Replaced a
      `Data(contentsOf:)` on a player-supplied URL string that would have read a `file:` path.
- [x] Lyrics lookups locked to lrclib.net, so a redirect cannot disclose what is playing
- [x] App Transport Security written out explicitly, verified with PlistBuddy against the
      built app rather than the build settings
- [x] Bounded settings clamped at the decode to the same ranges their controls enforce, and
      the import capped by file size. Verify with `--check-settings` and a hostile file.
- [x] No AppleScript injection: the only interpolations are a fixed app name and a
      `String(format: "%.3f")` seek position. Quick add goes through EventKit, not script.
- [x] The one remaining `pkill` (resuming an overlay helper an old build suspended) runs a
      fixed absolute path with literal arguments
- [x] Shelf paths persist as security-scoped bookmarks, so the sandbox move stays open
- [x] No secrets anywhere: LRCLIB needs no key and nothing else is authenticated
- [x] Nothing user-identifying is logged. Every `privacy: .public` is an error string, an
      OSStatus, or an action name.
- [ ] Re-audit after the sandbox is turned on, which changes the file and Apple Events story
- [ ] Dependency scanning becomes real the moment Sparkle is added. There are no
      third-party dependencies today, so there is nothing to scan.

---

## Platforms

- [ ] **macOS 13 (Ventura, 13.7.8).** Asked for, not started. The deployment target is 14.4.
      Blockers found: the Observation framework (`@Observable` in 16 classes, `@Environment(Type.self)`
      and `@Bindable` in 25 view files) is macOS 14 only and has to become `ObservableObject`;
      three two-parameter `onChange` calls and one `symbolEffect` need the macOS 13 forms; the
      Core Audio tap is macOS 14.2+, so Follow the Beat and lyric matching must be gated and
      hidden there. Plan if approved: one codebase with `#available` checks and a 13.0 target,
      done on a short-lived branch and merged, not a long-lived per-version branch.
- [ ] **Windows.** An idea for after a proper Mac release. Nothing here ports: the app is Swift,
      SwiftUI and AppKit over macOS-only frameworks. It would be a separate codebase (its own
      repository or a `windows/` folder), sharing the design and the feature list, and could
      ship on the same GitHub release as a second download.

## Distribution (not started)

Decisions still open, but nothing in the code should make these harder.

- [ ] **Sandbox.** `Config/MinNotch.entitlements` has `app-sandbox` set to false for
      development, with the automation and calendar entitlements already listed. Turning the
      sandbox on will require temporary-exception entitlements for Apple Events to
      `com.apple.Music` and `com.spotify.client`.
- [ ] **App Store build.** Cannot include the MediaRemote bridge. Plan is a compile-time flag
      that removes `MediaRemoteBridge` and makes `SystemNowPlayingSource` report unavailable,
      leaving Apple Music and Spotify working.
- [~] **Direct build.** 0.4.0 is released (2026-09-24, GitHub release `v0.4.0`), and 0.3.0
      the day before; both signed with the personal team as 0.2.0 was, which the user chose over
      `--anonymous`. The next shared build needs new `ReleaseNotes.latest` notes and `id`
      and a `MARKETING_VERSION` bump first. `Scripts/release.sh` builds Release and wraps it in
      `dist/MinNotch-<version>.dmg`, with `--anonymous` to re-sign ad-hoc so the download does
      not carry the signer's Apple ID, and `Scripts/release-notes.sh` for the GitHub release
      description. Hardened runtime is on. Notarisation needs a paid membership; Sparkle for
      updates is still to come.
- [ ] **Homebrew cask** once there is a notarised download.
- [x] **What's New panel.** Built as a window, see V2 — customisation; About > Release Notes opens it.
- [ ] **Monetisation.** Undecided. When decided, add a `.requiresPro` case to
      `FeatureAvailability` and a receipt check in `FeatureFlag.isEnabled`. No call site
      changes.
