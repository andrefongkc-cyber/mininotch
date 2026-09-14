# MinNotch workplan

Living document. Update the checkboxes as work lands. `CLAUDE.md` holds the architecture
rules and the traps; this file holds the sequence.

Status key: `[x]` done, `[~]` partially done, `[ ]` not started.

---

## Where things stand

The app is well past V1. Everything originally scoped as V1 is built, and most of what was
scoped as V2 is too: HUDs, the shelf, reminders, gestures, haptics, system stats, Bluetooth
accessory charge, and a five-style ambient lighting system. Roughly 12,700 lines across 96
Swift files, building with no warnings.

**The one blocker.** There is no code signing identity on this machine, so the app is ad-hoc
signed. That single fact costs three things: the system audio permission cannot be granted at
all, every rebuild resets every other granted permission, and nothing can be notarised.
Everything else on this list is ordinary work; this one needs the user to sign in to Xcode.

**Do these next, in this order:**

1. Signing (below). It unblocks the audio tap and stops permissions resetting.
2. App icon. The asset catalog is empty and it shows every time the app launches, including
   in the new welcome window, which is the first thing a new user sees.
3. A test target. Nothing is verified automatically across more than a hundred files.
4. The link shelf, below.

---

## Blocking

- [ ] **Real signing.** No identity exists on this machine. Sign in to Xcode with any Apple
      ID, including a free one, then set `DEVELOPMENT_TEAM` and switch `CODE_SIGN_STYLE` to
      Automatic in `project.pbxproj`. Verify with `security find-identity -v -p codesigning`.
      Until then: the system audio permission cannot be granted at all, so the audio-reactive
      glow stays on its fallback; Calendar, Reminders, Automation, and screen recording reset
      on every build, so use `Scripts/run.sh --no-build` to keep them; and notarising is
      impossible. This is a prerequisite for the entire Distribution section.

---

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
- [x] `NavigationSplitView` window with all eleven panes and System Settings styling
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

- [ ] **App icon.** `Assets.xcassets/AppIcon.appiconset` is empty; the build warns.
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
- [ ] **Swift 6 language mode.** Currently Swift 5 with minimal concurrency checking. The
      services are all main-actor in practice; annotate them and turn checking up.
- [ ] **Source app badge on the artwork.** The reference layouts show a small badge for the
      app that owns playback. `NowPlayingTrack.sourceAppName` is there; it needs the icon,
      which `NSWorkspace` can supply from the bundle identifier.
- [ ] **Panel height on tab change.** Heights are declared per widget as constants. If they
      drift from the real layout, consider measuring content with a preference key instead.
- [ ] **Lyrics scrolling view.** The strip shows two lines. A full sheet belongs in the
      expanded media view.
- [ ] **Stats history.** The readout shows an instant only. A short rolling window behind
      each bar would make a spike legible instead of something you have to catch.
- [ ] **Lyrics caching.** Every track change with the online source on is a fresh request.
      Add a small on-disk cache keyed by artist, title, and duration, plus a negative cache
      so a track with no lyrics is not looked up again on every replay.

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
- [x] `showOnLockScreen` deleted: macOS has no lock screen surface for third-party apps

## Ambient lighting

- [x] Five styles behind one `AmbientGlowStyle` protocol: Pulse, Wave, Bars, Chase, Rainbow
- [x] Three placements, multi-select: album art, closed notch, open panel
- [x] Colour modes, intensity, speed, and glow radius shared across every style
- [x] Live preview in Settings > Appearance, with every control in one card
- [x] Output latency compensation for lyric timing, read from the active output device
- [ ] Beat sources beyond live audio: tap tempo, manual BPM, and library tempo tags. Only
      live audio and the synthetic fallback exist.
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
- [ ] **The notch re-renders its whole surface every display frame while anything on it
      animates**, which costs about one core. Independent of frame rate, segment count, layer
      size, and the blur, and reproducible with the glow off and the media card's own
      visualizer running. Needs the animating overlay to stop invalidating the whole hosting
      view. Reproduce with `--capture-notch --hold 12 --glow off`.
- [~] Audio-reactive layer via a Core Audio process tap and a vDSP FFT, with band energy and
      onset detection. Replaced an earlier ScreenCaptureKit implementation, which asked for
      screen recording in order to read sound. **Partly verified**: the tap is created, the
      aggregate device is built, the IO proc fires, and buffers arrive. They are silent,
      because macOS will not raise the system audio permission prompt for an ad-hoc signed
      build, so the FFT, banding, and onset threshold remain unexercised against real signal.
- [ ] Cross-fade the glow between the closed and open outlines during the transition. It
      currently swaps when the state flips.
- [ ] **The glow outline does not grow with the box.** It holds the closed outline for one
      frame, then snaps to the fully open one while the fill is still two thirds of the way
      there. Cause found: `GeometryReader` hands back the destination size during an animated
      frame change, so no arrangement of it can work, and neither a custom `Animatable` view
      nor pausing the timeline fixes it. The outline has to become a `Shape` carrying its size
      and corner radius in `animatableData`. Reproduce and measure with
      `--capture-notch --midway 0.14`.

## Media sources: what Apple Events actually allow

Checked before building, because two commonly requested sources cannot work the way they
look like they should.

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

- [ ] VLC as a named `AppleScriptMediaSource`, wired into the existing automatic selection
      and stickiness. Needs VLC installed to verify.
- [ ] Up Next, Music only, with an honest empty state everywhere else.

---

## V2 — media

- [ ] **Sneak peek on track change.** Setting and `NotchViewModel.peek(for:)` already exist
      and `AppEnvironment.trackChanged` already calls it behind `FeatureFlag.liveActivities`.
      Remaining work is the animation polish and turning the flag on.
- [ ] **Feed the artwork visualizer from the audio analyser.** The bars over the album art
      still animate on the fallback pulse even when the glow's audio layer is running.
- [ ] **Card styles.** `NowPlayingCardStyle` has `.compact` and `.fullArtwork` declared and
      pickable; both currently render as `.classic`. Add the two views.
- [x] **Draggable control layout.** One `SlotLayoutEditor` component, used three times: the
      media transport row (Settings > Media), the closed pill's two flanks (General), and the
      open panel's trailing top strip (Appearance). Drag to reorder, drag between sides, drag
      out to remove.
- [ ] Real commands for shuffle, repeat, and favourite on each source. They can be arranged
      today but have nothing behind them, and the Media pane says so.
- [x] **Custom visualizer image.** Shipped as an animated image rather than Lottie, since
      `NSImageView` plays GIF and APNG with no third-party renderer.

## V2 — Live Activities

- [ ] **AirPods and Bluetooth battery.** `LiveActivityCenter` and the `.bluetoothDevice` kind
      exist. Needs an IOBluetooth source and the pill presentation.
- [~] **General-purpose activities.** The timer is the first real client: `TimerService`
      raises `onChange`, `AppEnvironment` turns it into a `LiveActivity`, and the service
      knows nothing about the pill. Downloads still to come, as is swipe-to-cycle and
      swipe-to-dismiss wired to `LiveActivityCenter.cycle(by:)`.

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

- [ ] **Overlay suppression without the flicker.** Terminating `OSDUIHelper` works but
      races the overlay's own appearance, so it can flash before it goes. Unloading the launch
      agent would be clean but is refused under System Integrity Protection, and a sandboxed
      build cannot spawn `pkill` at all.
- [ ] **Link shelf.** The same idea as the file shelf, for URLs. Paste or drag a link onto
      the notch and it is bookmarked there; click it and it opens in the default browser.
      Shape it after `ShelfService`: its own `Features/` folder, an ordered list with a
      configurable cap, and its own `NotchTab` and widget. Differences worth planning for
      before starting. A URL is not a file, so there are no security-scoped bookmarks and it
      can persist as plain values in the settings store rather than as bookmark data. It
      should read the page title where it can, since a bare URL is unreadable in a row that
      narrow, which means a network fetch and therefore `BoundedHTTPClient` rather than a
      bare `URLSession`. Dropped payloads arrive as `.url` and as `.text` that happens to
      parse, and `ClipboardHistoryService.isWebURL` already has the scheme-and-host check
      worth reusing. Opening goes through `NSWorkspace.open`, which respects the default
      browser without asking for anything.
- [ ] **Shelf polish.** Dragging several files out at once, and a Quick Share target.
- [ ] Weather widget.
- [x] System stats: CPU, GPU, memory, and network, sampled only while the System tab is
      open, with a refresh interval in Settings > Advanced
- [ ] Quick-launch row for favourite apps.
- [ ] Shortcuts widget triggering a macOS Shortcut.
- [ ] Screen recording, camera, and microphone in-use indicators.
- [ ] "Boring mirror": front camera preview with shape options.
- [ ] Widgets on the lock screen.

## V2 — customisation

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
- [x] `pkill` for the system overlay runs a fixed absolute path with literal arguments
- [x] Shelf paths persist as security-scoped bookmarks, so the sandbox move stays open
- [x] No secrets anywhere: LRCLIB needs no key and nothing else is authenticated
- [x] Nothing user-identifying is logged. Every `privacy: .public` is an error string, an
      OSStatus, or an action name.
- [ ] Re-audit after the sandbox is turned on, which changes the file and Apple Events story
- [ ] Dependency scanning becomes real the moment Sparkle is added. There are no
      third-party dependencies today, so there is nothing to scan.

---

## Distribution (not started)

Decisions still open, but nothing in the code should make these harder.

- [ ] **Sandbox.** `Config/MinNotch.entitlements` has `app-sandbox` set to false for
      development, with the automation and calendar entitlements already listed. Turning the
      sandbox on will require temporary-exception entitlements for Apple Events to
      `com.apple.Music` and `com.spotify.client`.
- [ ] **App Store build.** Cannot include the MediaRemote bridge. Plan is a compile-time flag
      that removes `MediaRemoteBridge` and makes `SystemNowPlayingSource` report unavailable,
      leaving Apple Music and Spotify working.
- [ ] **Direct build.** Notarised, hardened runtime already on, Sparkle for updates.
- [ ] **Homebrew cask** once there is a notarised download.
- [ ] **What's New panel** tied to version bumps. The About pane already has the row.
- [ ] **Monetisation.** Undecided. When decided, add a `.requiresPro` case to
      `FeatureAvailability` and a receipt check in `FeatureFlag.isEnabled`. No call site
      changes.
