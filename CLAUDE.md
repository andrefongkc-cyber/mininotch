# MiniNotch — working notes for Claude

A macOS menu-bar/notch utility. A borderless panel overlays the notch area: closed it is a
thin black pill, hovering or clicking expands it into a panel of widgets. Comparable to
NotchNook, Alcove, and TheBoringNotch.

Read this file first in a new session, then `WORKPLAN.md` for what to build next.

**Keeping the workplan current is part of every task, not a wrap-up step.** The first line of
`WORKPLAN.md` is `Status: doing X, next: Y`. Set it when a task starts, and flip that task's
checkbox (`[ ]` not started, `[~]` in progress, `[x]` done) after each meaningful change, not
only at the end. The point is that a fresh session, or this one after context compaction, can
read one line and resume. Do not create a second workplan or a second CLAUDE.md; these two are
the only ones, and they are updated in place.

## Start here

The app builds clean, runs, and is feature-complete for everything in `WORKPLAN.md` marked
`[x]`. 176 Swift files, in Swift 6 language mode.

**It is signed, as of 2026-09-15, with the user's free personal team** (`CODE_SIGN_STYLE =
Automatic`, an Apple Development certificate, no provisioning profile needed for a local Mac
build). The team itself is **not in the repository**: it lives in `Config/Local.xcconfig`, which
is gitignored and is the project's base configuration, with `Config/Local.xcconfig.example`
committed beside it. Without that file the build fails with "requires a development team" and
"Unable to open base configuration reference file", which is the intended message for anyone
else cloning this. `codesign -dv` on the built app must show `flags=0x10000(runtime)` and a real
`TeamIdentifier`; an ad-hoc build shows `flags=0x2(adhoc)` and means signing has broken. What
that changed, and what it did not:

1. The signature is stable across rebuilds, so TCC grants survive a build. Confirmed on 2026-10-02
   for Accessibility: granted, rebuilt, relaunched, still trusted.
2. **The audio tap works.** Signing, `ENABLE_RESOURCE_ACCESS_AUDIO_INPUT = YES` and asking
   from the foreground together fixed it: `--check-audio` received audio on 8 of 8 checks
   against a real sound, with energy 0.59 and live band values. The FFT, banding and onset
   chain have finally seen real signal.
3. Notarisation still needs a paid Developer Program membership, which the user does not have,
   so shared builds are still an unsigned-looking DMG that needs Open Anyway.

Anyone else building this has to set their own team, or signing fails.

**The app is MiniNotch; the code is still MinNotch.** Renamed on 2026-10-05, at the user's request,
everywhere it shows: the product (`PRODUCT_NAME = MiniNotch`, so `MiniNotch.app` and a `MiniNotch`
executable), every word on screen, the DMGs, the GitHub release titles, the README. Deliberately not
renamed, because nothing shows them and changing them costs something: the bundle identifier
`com.minnotch.MinNotch` (permissions, settings and Sparkle all key on it), the Xcode project, target
and scheme, the `MinNotch/` source folder, the DerivedData folder that follows the project, and the
floating window's saved frame name. The Notes file moved from `Application Support/MinNotch` to
`MiniNotch`, carried across on first launch. `Scripts/run.sh` kills both executable names, since a
copy built before the rename runs as `MinNotch`.

**MiniNotch is a background agent.** `LSUIElement` is true in `Config/Info.plist` and
`AppDelegate` sets `.accessory`, so it has no Dock icon and no place in ⌘-Tab; `lsappinfo` reports
it as `UIElement`. The user wants it to stay that way. The only time it may become a regular app,
with a Dock icon, is while macOS is actually showing it a permission prompt (`ForegroundPrompt`).

## Build, run, review

```bash
Scripts/build.sh          # build Debug, print only warnings/errors
Scripts/run.sh            # build, kill any running copy, relaunch
Scripts/preview.sh        # render notch views to PNGs in Previews/
Scripts/audit-search.sh   # every Settings row is in the search index, and nothing stale is
Scripts/release.sh        # Release build wrapped in dist/MiniNotch-<version>.dmg
Scripts/release.sh --anonymous   # …re-signed ad-hoc, carrying no team or Apple ID
Scripts/release-notes.sh  # the same release notes as Markdown, for the GitHub release
Scripts/style-diff.sh <old MiniNotch.app>   # every capture of two builds compared pixel for pixel
swift Scripts/contact-sheet.swift out.png <h> <w> "Label=a.png" ...  # captures side by side (compile it with swiftc first)
swift Scripts/make-icon.swift art.png   # artwork into AppIcon.appiconset, in Apple's grid
```

Debug-only command line flags on the binary itself, all `#if DEBUG`:

```bash
MiniNotch --render-previews <dir>                                  # what preview.sh calls
MiniNotch --capture-notch out.png [--collapsed] [--tab system] [--glow bars|off] [--debug]
                                 [--hold 12] [--midway 0.14] [--extended] [--virtual]
                                 [--timer 12] [--width 460] [--right timer,settings,battery]
                                 [--paused] [--placements closed,open]
                                 [--sample-calendar] [--calendar-step 1] [--calendar-pick 2]
                                 [--card compact|fullArtwork] [--controls shuffle,playPause,repeatMode]
                                 [--lyrics-sheet] [--sample-stats] [--shadow] [--closed-lyrics]
                                 [--sample-shelf] [--output-sheet] [--sample-weather]
                                 [--sample-power] [--keep-open] [--hud-style floatingPill] [--no-media]
                                 [--sample-notes] [--blur-clipboard]
                                 [--notch-style bento-light] [--liquid-glass] [--builtin]
                                 [--no-visualizer] [--no-lyrics] [--swipe-to notes --midway 0.15]
MiniNotch --check-lyrics "Khalid" "8TEEN" 229                      # LRCLIBClient + LRCParser
MiniNotch --check-lyric-sync [--out f]                             # matching lyrics to the audio, synthetic
MiniNotch --check-lyric-sync --audio f.mp3 --lrc f.lrc --shifts 0,0.5 [--peaks]   # …and a real song, old method beside it
MiniNotch --check-stats 5                                          # CPU/GPU/memory/network
MiniNotch --check-audio 8 [--out f]                                # Core Audio tap
MiniNotch --check-glow 2 [--source step|fallback|tempo]            # glow shaping chain, tempo grid
MiniNotch --check-settings file.minnotch                           # import bounds
MiniNotch --check-settings-search pomodoro glow                    # search ranking
MiniNotch --capture-onboarding <dir> [--rerun]                     # tutorial, every page
MiniNotch --capture-whats-new <dir>                                # release notes window and notes
MiniNotch --capture-layout <dir> [--width 460]                     # Settings > Layout editors
MiniNotch --check-permissions [--request] [--out f]                # TCC state
MiniNotch --check-media [--scripts <dir>] [--out f]                # snapshot, shuffle, Up Next
MiniNotch --check-keys [--simulate] [--control] [--out f]          # volume/brightness key tap
MiniNotch --check-links "<url or text>" ...                        # link shelf: titles, icons, refusals
MiniNotch --check-downloads [--out f]                              # download activities, in a scratch folder
MiniNotch --check-lock-screen                                      # the SkyLight calls behind the lock screen HUD
MiniNotch --capture-lock-screen out.png [--hud]                    # what the lock screen window draws
MiniNotch --check-meeting-links                                    # which invitation links count as a meeting
MiniNotch --check-audio-outputs                                    # the outputs the card would offer
MiniNotch --check-weather London | 51.5 -0.13 [--fahrenheit]       # a real forecast, parsed
MiniNotch --check-tab-order                                        # the swipe steps through tabs as the bar draws them
MiniNotch --check-temps                                            # every temperature sensor, and the three the System tab shows
MiniNotch --check-stats-history                                    # the graphs' history survives the System tab closing
MiniNotch --check-power [seconds]                                  # charger in, Mac use, battery, from the SMC
MiniNotch --check-keep-open                                        # Keep the Notch Open: holds, lets go, pin, shortcut default
MiniNotch --check-notes                                            # the note is saved, read back, never overwritten by a capture
MiniNotch --check-update --feed <url> [--out f]                   # a whole Sparkle update, test builds only (see Releases)
MiniNotch --check-clipboard                                        # what the history records, and when it is blurred
MiniNotch --capture-styles out.png                                 # every Notch Style's miniature, dark and light
```

`--capture-notch` grew three options for the animated effects. `--glow off` disables the
glow, which is the only honest A/B for a performance figure, since the media card animates
on its own. `--debug` turns on the outline and the glow's level readout without touching the
real configuration. `--hold <seconds>` keeps the panel on screen instead of capturing after
1.2s, which is how anything animated gets sampled or profiled at all. `--virtual` stands in for an
external monitor, which is the only way to review the non-notch surface without owning one:
it behaves differently on purpose, carrying its indicators without the opt-in and opening on
its own tab. `--timer <minutes>` starts a countdown, and wires the same `onChange` callback
`AppEnvironment.start()` installs, so the Live Activity reaches the pill the way it really
does rather than being pushed in by the tool. `--extended` turns on
the closed pill's indicators, without which a capture of the pill is an empty black bar.
`--midway <seconds>`
settles the panel closed, opens it, and captures partway through the spring, which is the
only way to see what the open and close transition actually draws rather than where it ends
up. It is what caught the glow snapping ahead of the box.

`--out` exists because a process started by LaunchServices has nowhere to send stderr, and
launching it any other way changes the identity TCC judges it against.

All of them build their `AppEnvironment` through `DebugSupport.makeEnvironment()`, which
backs the settings store with a throwaway suite seeded from the real one. Several tools turn
features on so they can render them; without that indirection, looking at a preview silently
rewrote the user's configuration. Never construct `AppEnvironment()` directly in a debug tool.

`--capture-notch` is the one that tells the truth about edges. `ImageRenderer`, and therefore
`Scripts/preview.sh`, flattens the view into a single drawing context, which hides everything
caused by separate layers compositing against a transparent window: seams, halos, and stray
fills all vanish in a preview and are plainly visible on screen. `--capture-notch` builds the
real `NotchPanel` and reads its backing store back. Transparent areas come back at zero alpha,
so a partially transparent pixel that is not near-black is an artifact on the outline. Use it
whenever a report mentions an edge, an outline, or a halo.

`--check-glow` runs the glow's shaping chain headlessly and prints the trace. The constants
in `GlowDynamics.Tuning` are the entire feel of the effect and cannot be judged from the
screen: blurred and stroked, a level pinned at the top and a level that never leaves the
middle look identical. `--source step` feeds a square pulse, which is where an attack that is
too slow, a decay that is too fast, a collapsed auto-gain, or a spring that never overshoots
all show up as numbers. It found a real bug on its first run: near-silence was being gained
up to full scale, so a quiet room drove the glow flat out.

`--check-settings` imports a settings file and prints what the store ended up with, beside
the range each value is allowed. A settings file is the one piece of structured input this app
takes from outside itself, and it is exported, mailed around, hand-edited, and written by older
builds with different limits. Feed it a deliberately hostile file and every number must come
out inside its bounds.

`--check-lyrics` prints the parsed lines, the per-word timing for one line, and which word
the strip would highlight at each moment, which is the only practical way to check the
karaoke highlight without playing a track and watching the notch.

`xcodebuild -project MinNotch.xcodeproj -scheme MinNotch -configuration Debug build` is the
underlying command. There is no test target yet.

**Verifying UI changes.** The notch is a borderless non-activating panel, so `screencapture`
returns a black image unless Screen Recording is granted to the calling process. Use
`Scripts/preview.sh` instead: it runs the app with `--render-previews <dir>` and writes PNGs
of every notch state in both appearances, using fixed sample data. Two limitations of
`ImageRenderer` to know about:

- It cannot draw an `NSViewRepresentable`, and paints a yellow "prohibited" placeholder over
  anything containing one. The renderer sets `useVibrancy = false` to avoid this.
- It does not draw `ScrollView` content, so the calendar event list renders empty in a
  preview. That is a preview artefact, not a bug. Check scrolling lists in the running app.
- The backdrop is deliberately a light-to-dark gradient so an edge artifact is visible
  whichever way it errs.
- The Settings window uses `NavigationSplitView` and a sidebar `List`, both AppKit-backed
  and unrenderable offscreen. Review that window by opening it (`Scripts/run.sh`, then click
  the menu bar icon, or launch the app twice).

## Project shape

Hand-written `.xcodeproj` using **Xcode 16 file-system-synchronized groups**
(`PBXFileSystemSynchronizedRootGroup`). Any `.swift` file added anywhere under `MinNotch/`
is compiled automatically. **Never edit `project.pbxproj` to add a file.** Only touch it to
change build settings, and there is no XcodeGen or SPM manifest to keep in sync.

```
MinNotch/
  App/            entry point, AppDelegate, AppEnvironment (composition root), debug renderer
  Core/
    DesignSystem/ Theme, cards, rows, badges, controls, vibrancy wrapper
    Settings/     SettingsStore + one file per settings section
    Notch/        geometry, panel, view model, window controller, multi-display manager
    Hotkeys/      Carbon global shortcuts
    Gestures/     two-finger swipe monitor
    Widgets/      NotchTab + widget registry
    LiveActivity/ ongoing-event model and centre
    Platform/     login item, menu bar item, notifications, feature flags, logging
  Features/
    NowPlaying/   media sources, controller, lyrics, artwork palette
    Calendar/     EventKit service and models
    Battery/      IOKit power source service
    SystemStats/  CPU, GPU, memory and network sampling
    Bluetooth/    accessory charge from the IO registry
    Shelf/        the drag-and-drop file tray
    Clipboard/    copy history, polled
    Downloads/    the Downloads folder watch behind the download activity
    Audio/        sound outputs and volume, for the Now Playing card
    Weather/      Open-Meteo forecast, location, city search
    LockScreen/   the window drawn above the lock screen: HUD and media
    LinkShelf/    saved web links, page titles and icons
    Timer/        countdown and the Pomodoro cycle on top of it
    HUD/          volume, brightness and keyboard backlight monitors
    AmbientGlow/  glow styles, geometry, and the Core Audio tap
    Onboarding/   first-launch tutorial: feature catalogue, presets, coordinator
    WhatsNew/     release notes shown once per release at launch
  UI/
    Notch/        the notch surface and its widgets
    Settings/     the Settings window, sidebar, search index, and one file per pane
    Onboarding/   the tutorial's pages
    WhatsNew/     the release notes window
Config/           Info.plist and entitlements, outside the synced folder so neither is
                  copied in as a resource
Scripts/          build, run, preview
```

## Architecture rules

- **`AppEnvironment` is the only place services are wired together.** Services never call
  each other. The battery service raises `onLowBattery`; the environment decides a
  notification is posted. Settings changes fan out from `AppEnvironment.settingsChanged()`,
  which re-applies everything rather than diffing keys.
- **Settings sections are `Codable` structs, one file each**, held by the `@Observable`
  `SettingsStore`. Mutating a nested field fires the section's `didSet`, which schedules a
  debounced write and calls `onChange`. Every section decodes leniently through
  `KeyedDecodingContainer.value(_:_:)`, so adding a property never invalidates a saved file.
  Export/import is a straight encode of `SettingsSnapshot`.
- **Adding a whole settings *section*** is four places, not three: the struct, a property on
  `SettingsSnapshot`, **a line in `SettingsSnapshot.init(from:)`**, and a stored property on
  `SettingsStore` plus its two lines in the snapshot round trip. Miss the decode line and the
  section silently resets to defaults on every launch while appearing to save correctly,
  because the store writes it and never reads it back. `--check-settings` catches this: the
  values come back as defaults instead of clamped.
- **Adding a setting**: add the property with a default, add one line to that section's
  `init(from:)`, add a `SettingsRow` to the matching pane. Nothing else. If it is a bounded
  number, pass the control's range to the decode as well, `c.value(.key, default, in: 2...28)`,
  and keep the two in step. A slider bounds typing into the UI; it does not bound a file, and
  import decodes straight into the store.
- **Adding a notch widget**: add a `NotchTab` case, register it in `NotchWidgetRegistry`, add
  a branch to `ExpandedPanelView.widget`, and give the view a `preferredHeight`. The panel's
  height comes from the widget, not from a table in `NotchRootView`.
- **Feature gating** goes through `FeatureFlag`. Nothing is hardcoded as free or paid;
  monetisation is undecided. Unbuilt features ship as real, persisted settings rendered with
  a "Coming soon" badge and `.comingSoon()`, so landing the feature is a deletion.
- **In SwiftUI views** use `@Environment(AppEnvironment.self)` and
  `@Environment(SettingsStore.self)`, then `@Bindable var settings = settings` at the top of
  `body` to get bindings.

## Things that will bite you

- **Content must clear the shape's shoulder inset.** `NotchShape` insets its body by
  `shoulderRadius`, so the outermost points of the pill are the concave fillets, not solid
  fill. Anything drawn in that band sits over transparency and reads as a clipped, glitchy
  edge. `CollapsedPillContent.contentInset` is the clearance; sizing and layout both read it,
  which is why they cannot drift apart.
- **A virtual notch always carries its indicators, whatever the setting says.** The opt-in
  exists because on notched hardware the closed pill hides behind the camera housing, so
  widening it is a real choice with a real cost. A virtual notch has no housing: it is
  already a black tab stuck to the top of the screen, and leaving it empty is all of the cost
  and none of the benefit. `isExtended` is therefore
  `extendPillForIndicators || !geometry.hasPhysicalNotch`. That is what it draws when it is drawn
  at all: Advanced > Hide Until Hovered draws nothing at rest (see "A hidden virtual notch").
- **The pill's leading flank composes, it does not choose.** Artwork and a Live Activity are
  drawn side by side. They used to be a chain of else-ifs with artwork first, which meant a
  running timer was invisible for as long as anything was playing, which is precisely when
  you most want to see how long is left. If two things are both worth knowing, the flank has
  room for both, and `leadingContentWidth` adds them up in the same order and with the same
  spacings the view uses.
- **What the pill and the top bar show is arranged, not assigned.** `IconLayoutEditor` is
  one drag-to-arrange component used three times, all in Settings > Layout: the closed pill's
  two flanks, the open panel's top bar (tabs included), and the media transport row. Each is
  drawn as a miniature of the real surface with the camera cutout in it and a tray of icons
  underneath: drag or click to place, drag back or click × to remove. The cutout is drawn but
  is not a destination, because on the notch it is a `Spacer` with nothing in it, which is the
  only reason clicks there fall through to the desktop. The miniature shows the user's
  arrangement, not what `TopStripLayout` resolves, or a drop would appear to land in the wrong
  place. `ImageRenderer` cannot draw drag sources or drop targets, so `--capture-layout` sets
  `LayoutEditorRendering.isStatic` and renders the editors without them.
- **A drop lands where it is let go, judged against the icons' midpoints.** Each side of the
  editor is one `DropDelegate` target that reads the pointer's position, which is also what lets
  it draw a marker in the gap before anything is dropped. It used to be a target per icon that
  inserted before it, and a side that appended: everywhere off an icon meant "at the end", so on
  the closed pill, whose left side hugs the cutout, dropping in the empty space on the left moved
  an icon right, and moving one left needed a hit on a 26 point icon. Reported as "moving right
  is really good but moving left is really hard". The gap index is counted with the dragged item
  still in place, so `place(_:on:at:)` takes one off when it is moving right within a side.
- **The closed pill's miniature is the pill.** `PillIndicatorView` draws one indicator for both
  the notch and Settings > Layout, and `CollapsedPillContent.live` builds the live state for
  both, so the miniature shows this cover, this title and this battery. An indicator with
  nothing to show right now keeps its symbol, faded, so it can still be dragged.
- **The top bar's arrangement is a preference; `TopStripLayout` decides placement.** Every
  enabled feature adds a tab, and a fixed tab strip on the left pushed the seventh (Links)
  behind the camera housing. Items that do not fit on their side cross to the other side next
  to the cutout, keeping the order of both lists read end to end; then buttons tighten from 28
  to 21 points; only then does `NotchGeometry.panelWidth` widen the panel. The view and the
  geometry both read widths from `TopStripLayout`, so they cannot disagree. Tabs cannot be
  removed from the bar (`canRemove`), because a feature that is on must stay reachable, and a
  tab missing from both saved lists joins the left at display time. The sideways swipe between
  tabs walks the same layout (`NotchViewModel.topStripLayout(battery:)`, then `tabsInOrder`), left
  to right as drawn. It used to walk `availableTabs`, the registry's fixed order, so after a tab
  was moved the swipe skipped it and came back to it out of place. `--check-tab-order` rearranges
  the bar and compares.
- **Nothing may hardcode which indicator is the wide one.** `flankWidth` sums whatever the
  user assigned to each side, in their order, with the same spacings the view lays out, and
  takes the larger of the two. It used to know that artwork was 18 points and battery was
  glyph-plus-label, which stopped being true the moment either side could hold anything.
  Widths for text are measured in the font the pill draws in, at the *widest* value the label
  ever takes rather than the current one, or the pill visibly resizes as the battery drains.
- **The closed pill's two flanks must be the same width.** The surface is centred on the
  display, so the dead zone in the middle of the pill only sits over the camera housing while
  the flanks match. Widen one side alone and the whole pill shifts by half that amount,
  sliding the cutout off the hardware it exists to hide behind. With the battery showing and
  nothing playing, that put the dead zone well left of the housing. `flankWidth` is
  `max` of the two sides for this reason, and both sides are laid out at it.
- **Pad inside a fixed-width frame, not outside it.** `.frame(width:).padding()` adds the
  inset *outside* a width that already accounted for it, so the row comes out wider than the
  pill by the inset on each side. The frame around the row then forces the smaller width, the
  overflow is centred, and content is pushed past the pill's edge onto transparency: that is
  what made the pill artwork render with a slice missing. `.padding().frame(width:)` is the
  order that adds up.
- **`EmptyView` takes no space, whatever frame it is given.** The pill's empty flank was an
  `EmptyView` with `.padding().frame(width: flankWidth)`, and both modifiers vanish with it. With
  nothing playing the left side was empty, the row came out a flank narrower than its frame and
  was centred, and the cutout spacer and the right flank slid half a flank left: on the user's
  MacBook Pro the battery's percentage and half its glyph sat under the camera housing. A screenshot
  showed it (it includes the pixels under the housing); a photo only showed the cut. An empty side
  is now a zero-size `Color.clear`, which keeps the frame. `--capture-notch --collapsed --extended
  --no-media` is the case: with a 179-point notch the battery must start right of x = 851.
- **A zero-width frame does not clip in SwiftUI.** Hiding pill content by giving it a
  zero-width frame leaves the content drawn, centred, spilling outside the shape. Guard the
  view itself, not just its size.
- **Nothing readable goes in the top band of the panel.** The panel is anchored to the top
  of the display, so its first rows of pixels are behind the camera housing. `ExpandedPanelView`
  reserves that band as a top strip exactly `geometry.collapsedSize.height` tall and puts its
  controls in the flanks either side of a fixed-width spacer the width of the cutout. Content
  starts below it. Put a title there and it is invisible on the hardware this app is for.
- **The notch panel is non-activating, so system control styles render inactive.**
  `.borderedProminent` draws itself in a disabled-looking grey when its window is not key,
  which is always for this panel. Use `NotchAccentButtonStyle` instead.
- **`Canvas` output does not appear in an AppKit layer capture.** A probe proved it: a
  plain stroked `Shape` on the same path captured fine while the `Canvas` next to it came
  back empty. That makes anything drawn in a `Canvas` unverifiable here, which is why
  `AmbientGlowView` strokes `Shape`s instead and keeps its segment counts low.
- **Never put a bare `Shape` in a view stack.** A `Shape` used as a `View` fills itself
  with the current foreground style, which resolves to white in a dark appearance. One left
  under the notch's black fill laid a white silhouette beneath it, which showed through
  wherever the fill's antialiasing did not cover it exactly: the bottom corners and the two
  top fillets. Use `.fill()`, or `.contentShape()` when you only want hit-testing.
- **Clip the surface once, not twice.** Clipping the fill and the content separately puts two
  independently antialiased edges on top of each other, and on a transparent window the
  compositor blends those partial-coverage pixels against the desktop rather than against the
  panel, which shows as a pale seam along every curve.
- **`GeometryReader` aligns its content top-leading, which is not what an overlay does.** A
  plain `.overlay()` centres. Swapping one for the other moved the glow's layer, which is
  deliberately larger than the outline it traces, down and right by the whole spill, so the
  light no longer sat on the panel it was tracing. If a layer is bigger than the thing it
  decorates, it has to be centred on it.
- **A view inserted during an animation takes its final layout on its first frame.** That, not
  `GeometryReader`, is why the ambient glow jumped to the fully open outline while the fill was
  still growing: with the glow on for the open panel and off for the closed notch, the glow was
  *inserted* when the notch opened. Probes ruled the other suspects out one at a time: a stroked
  shape in the overlay tracks the box inside a `TimelineView`, inside `drawingGroup()`, with a
  blur, and with a width that changes every frame; the same view behind an `if` does not. So
  anything that has to follow the surface through the spring stays in the hierarchy for both
  states and is hidden with an animated opacity (`AmbientGlowView.isVisible`), which also pauses
  its timeline so hidden costs nothing. Draw it with a `Shape` (`GlowStroke`), which is pathed at
  the rect it is rendered in, rather than a `Path` built from a size handed down.
- **A link someone gives the app may only ever be `http` or `https`.** The link shelf hands its
  rows to `NSWorkspace.open`, which opens whatever a scheme is registered to: accept `file:` and a
  click opens a local file, accept a custom scheme and a click launches an app with arguments
  from the link. `LinkShelfService.normalised` refuses everything else at the door, and the
  stored list is re-validated when it is read back.
- **A URL that came from somewhere else is not a URL you may fetch.** The artwork URL arrives
  as a string from whatever media player is running, over Apple Events. It was read with
  `Data(contentsOf:)`, which accepts any scheme the string happens to parse as: a reply of
  `file:///…` would have had an unsandboxed app read that path off disk and try to decode it
  as an image. Transport security does not help, because it ignores `file:` entirely. It also
  had no timeout and no size limit, on the serial queue every media read shares. Every
  outbound request now goes through `BoundedHTTPClient`, which requires HTTPS and a host,
  caps the body while it arrives rather than after, refuses redirects off the original host,
  and times out. Two options relax it for the link shelf only: `truncatesAtLimit` keeps the
  start of an oversized page, since a title sits at the top, and `followsCrossHostRedirects`
  follows a short link to where it goes. Leave both off for anything that sends the user's data. Do not add a bare `URLSession` or a `Data(contentsOf:)` beside it.
- **Only measure CPU inside a real `NSApplication` run loop.** The debug tools used to turn
  `RunLoop.main` by hand, and under that any SwiftUI animation spins: a bare 200-point window with
  one ticking label measured 112% of a core, and 10% under `NSApp.run()`. That artefact is where
  this file's old claim that "anything animating costs a core" came from, and it was wrong.
  `--capture-notch --hold <seconds>` above two seconds now runs the real loop. Measured that way on
  a 60 Hz display: closed notch idle 0%, closed with the glow showing 16%, open media card 12%,
  open card with the glow 21%. A hidden glow is 0%.
- **A blurred layer needs room outside itself.** `drawingGroup()` rasterises into a layer
  the size of the view, so a blur cannot reach past its own bounds. Give a glow no room and
  its falloff is sliced off mid-gradient: it ends on a hard edge exactly where the view does,
  and on a transparent window that edge composites against the desktop, so it reads as a
  translucent strip beside the panel rather than as light. `AmbientGlowView.spill` is the
  room the caller promises; it pads itself outward by that much, insets the path back, and
  caps the blur at half of it so the light always reaches nothing first. The notch passes
  `Metrics.notchGlowSpill`, and `NotchGeometry.windowPadding` is sized from the same
  constant so the window cannot clip what the layer no longer does.
- **Clip the notch content to the shape.** A view being removed by a transition keeps its
  old layout while it fades, and a view being inserted takes its final layout immediately.
  Either way the content is briefly larger than the box that is still growing or shrinking
  around it, so unclipped white panel text is drawn outside the black fill on a transparent
  window. That is the pale smear that trails the box on open and close. `contentLayer`
  clips to `shape`; do not remove it.
- **Size the surface off one animation, not several.** Width and height are driven from a
  single `SurfaceMetrics` value with one curve. Animating them off separate values with
  separate curves makes the box shear as it grows, because one axis arrives before the other.
- **Nothing about the surface's fill may depend on open/closed.** A material or hairline that
  only exists when expanded appears part-way through the growth and reads as a flash of
  light. The vibrancy option is applied in both states for exactly this reason.
- **Do not "hide" a stroke or shadow with a zero-alpha colour.** A `.shadow` still forces an
  offscreen compositing pass at zero alpha, and on a transparent window that shows as a faint
  light fringe along the pill. Apply the modifier conditionally instead.
- **Anything drawn over album art must not take its colour from that album art.** The
  visualizer bars used the cover's dominant colours, which are by construction the colours
  least likely to stand out against the cover, and their black outline disappeared into dark
  sleeves. Lift the colour (`ArtworkPalette.glowPrimary`) and give it a guaranteed dark ground
  (the scrim under the bars) rather than trying to pick an outline that works on every cover.
- **`repeat` ignores its colour when given an explicit font, in this app.** `Image(systemName:
  "repeat")` with `.font(.system(size:))` drew plain white whatever `foregroundStyle` said,
  while `shuffle`, `heart` and the arrows in the same row took theirs, and the identical code
  in a standalone window drew correctly. Transport buttons therefore go through
  `TransportSymbol.image`, an `NSImage` symbol at a point size drawn as a template, which takes
  its colour every time. Found by forcing `.red` and reading pixels off `--capture-notch`. The same thing
  hit the lyric strip's Show Lyrics When Closed button: its glyph came out pure white on and off
  alike until it went through `TransportSymbol.image` too. Any symbol whose colour says something,
  on or off, playing or not, goes through `TransportSymbol.image`. A light Notch Style found more of
  them, white on white: the System, Timer and Notes tab icons, the battery, the thermometer and the
  effects button. The top bar's buttons now all go through it, and the battery through
  `TransportSymbol.hierarchical`, which keeps its two-tone look in a colour.
- **The notch draws in its Notch Style, never in the system appearance.** Never use a semantic
  label colour (`Palette.primaryText`, `.labelColor`) for content drawn on it, and never a literal
  `.white` either: text and glyphs are `theme.ink.opacity(x)` (`@Environment(\.notchStyle) private
  var theme`), at the opacities they always had. White is only for things on the accent or on album
  art, which are the same in every style. `Palette` is for the Settings window. See "Notch Styles".
- **Transparent areas hit-test.** `Color.clear` receives clicks in SwiftUI. Everything around
  the notch surface must be `Spacer`, never a clear colour, or the window swallows clicks
  meant for the desktop.
- **`@Observable` only fires on stored properties, so a computed one over ignored storage
  never redraws.** The timer's countdown is derived from `deadline`, which is
  `@ObservationIgnored` because it is an implementation detail. Nothing observable therefore
  changed as the clock advanced: the panel drew the time once and froze on it, and pressing
  pause made the number jump to the truth rather than stop, which is what "the play button is
  glitchy" turned out to be. The fix is a stored property that changes on every tick,
  `TimerService.tickStamp`, read and discarded inside `remaining`. Verify it with two captures
  at different `--hold` values and compare the pixels: identical means frozen.
- **`ScrollView` has no ideal height.** Inside the panel it lays out at zero unless given an
  explicit frame. See `CalendarWidgetView.eventListHeight`.
- **Every permission has to be asked for from the foreground.** macOS shows a permission dialog
  only to the active app, and this one is an accessory app whose panel never activates, so a
  request made as-is is answered by nobody. EventKit resolves as a refusal with no dialog; the
  audio tap is worse, blocking forever instead of returning. `ForegroundPrompt.begin()` /
  `end()` takes a Dock icon for the length of the request and restores it afterwards, on a timer
  as well, so a request that never answers cannot strand the app with an icon. Wrap any new
  permission request in it, **but only when a prompt can actually appear.** The audio tap and
  the Downloads watch used to take the foreground on every start, so with either feature on
  the app flashed a Dock icon and took focus at every launch, long after the permission was
  granted: `lsappinfo` caught it as `Foreground` for a tenth of a second. Each now remembers a
  start that worked (`audioTap.granted`, `downloads.granted` in the standard defaults) and
  starts straight away next time. A start that fails or times out clears the memory, and
  `AudioAnalyzer.retry()` always asks from the front. To check, relaunch through `open -n -a`
  and poll `lsappinfo info -only ApplicationType -app com.minnotch.MinNotch` every 100 ms: it
  must read `UIElement` throughout.
- **Apple's volume overlay is hidden by taking the keys, not by touching the overlay.** On macOS
  26 `OSDUIHelper` no longer draws it: suspended (state `T`) the overlay still appeared, and killing
  it had always flickered. `SystemKeyInterceptor` is a session event tap on `NX_SYSDEFINED` aux
  buttons that swallows volume and brightness presses, and `HUDCoordinator` sets the level itself
  (`VolumeMonitor.apply`, `BrightnessMonitor.apply`, sixteenth steps, Shift+Option quarter steps)
  and shows its own HUD. It needs Accessibility, which resets with every ad-hoc build like every
  other grant. A key is only taken when it can be acted on; anything else returns the event so
  macOS handles it. Keyboard backlight keys are never taken. `--check-keys --simulate --control`
  proves it end to end: the same posted press moves the volume with no tap and does not with one.
  Every launch still sends `SIGCONT` to `OSDUIHelper`, for Macs an older build left suspended.
- **Read a `Process` pipe before `waitUntilExit()`, not after.** A child that writes more than a
  pipe's buffer (`ps -ax` does) blocks on the full pipe while the parent blocks waiting for it to
  exit. The old `--check-osd` hung on exactly that.
- **Never let AppleScript launch a player.** Check `AppleScriptRunner.isRunning(bundleIdentifier:)`
  first, and use the `if application "X" is running` guard in the script. Otherwise reading
  the current track starts Music.
- **AppleScript returns typed lists, not delimited strings.** Parsing `as text` numbers breaks
  under locales with a comma decimal separator.
- **MediaRemote is gated.** Recent macOS versions require a private entitlement for the now
  playing functions, so `SystemNowPlayingSource` may load and still never receive a payload.
  `hasEverReceivedPayload` distinguishes the two, and Settings > Media reports it. Apple
  Events are the primary path, not the fallback. Private API also cannot ship to the App
  Store, so that build must report the system source as unavailable.
- **`NSAppleScript` is not thread-safe** and a round trip costs ~100 ms. Everything runs on
  `AppleScriptRunner.shared.queue`, never the main thread.
- **The window frame never animates.** The panel is created once at the maximum size and
  SwiftUI animates the content inside it. Do not resize the window per state.
- **Swift 6 language mode**, since 2026-09-22, with no warnings. The rules that got it there,
  and that keep it there:
  - **Services, controllers and windows are `@MainActor`.** They always ran on main; now the
    compiler knows. A new one should be too, unless it genuinely lives on a queue.
  - **A framework callback that can arrive off the main thread is written `@Sendable`**
    (`{ @Sendable granted, error in ... }`) and hops back with `Task { @MainActor in }`. A
    closure written inside a main-actor method otherwise inherits that isolation, and Swift 6
    checks it on entry: EventKit, the notification centre, or `Progress.addSubscriber` calling
    it from their own queue stops the app, and the compiler cannot see it coming. Callbacks
    delivered on the main queue or run loop (notification observers with `queue: .main`,
    `DispatchSource` on `.main`, Core Audio listeners on `DispatchQueue.main`, the event tap,
    IOKit ports set to `.main`) are safe, and `MainActor.assumeIsolated` says so where needed.
  - **Timers are `Timer.onMain(every:)`**, which adds to the main run loop and so can assume
    the main actor honestly. `Timer`'s own block is `@Sendable` with no isolation.
  - **Types confined to a queue say so.** `AppleScriptRunner`, `LyricsCache`,
    `BoundedHTTPClient`, `MediaRemoteBridge` and `SystemNowPlayingSource` are `@unchecked
    Sendable` with a comment naming the queue or lock; `AudioAnalyzer`'s Core Audio and DSP
    state is `nonisolated(unsafe)`, confined to its audio queue, beside main-actor published
    state. `MediaSource` is `Sendable` because every source is handed to the AppleScript queue.
  - The migration found three real races, all fixed: `NowPlayingController.refresh()` read
    the settings on the AppleScript queue, the system source's cache was written on main and
    read on that queue unguarded, and a multi-file drop on the shelf appended to one array
    from several loader threads.
  - Checked after the switch by running every `--check-*` and `--capture-*` tool, and
    `--check-audio` through LaunchServices with sound playing (6 of 6).

## Permissions and TCC

Four things about permissions on this project will waste an hour if you do not know them.

**`INFOPLIST_KEY_*` silently drops keys Xcode does not recognise.** `NSAudioCaptureUsageDescription`
is one of them. A missing usage description means the permission prompt never fires at all,
which is indistinguishable from the permission being refused. The project therefore uses a
real `Config/Info.plist` rather than `GENERATE_INFOPLIST_FILE`; add new usage descriptions
there and verify with `PlistBuddy` against the built app, not the build settings.

**Every build used to void every granted permission**, because an ad-hoc signature is a hash of
the binary and TCC keys its grants on that, so each rebuild was a different app and Calendar
access reset to `notDetermined`. The signing identity above is what fixes it, since the grant
now follows the team and bundle id. Until that is actually watched surviving a rebuild, keep
using `Scripts/run.sh --no-build` when a grant matters, and re-check rather than assume.

**A prompt is only shown to a frontmost app.** MiniNotch is an accessory app with no Dock icon,
and the notch panel is non-activating precisely so it never steals focus, so it is never the
active app. `CalendarService.requestAccess()` therefore switches to a regular activation
policy and activates before asking, restoring the policy when the user answers or after a
timeout. Without that the request resolves with no dialog and the status stays
`notDetermined`, which is indistinguishable from a user dismissing a dialog they never saw.

**The system audio tap needed three things, and two of them were not signing.** It needs a real
signature, the `com.apple.security.device.audio-input` entitlement, and to be asked for while the
app is frontmost. `AudioHardwareCreateProcessTap` does not refuse and does not return when the
prompt cannot be shown: it blocks forever, which is why `AudioAnalyzer.start()` does its Core
Audio work off the main thread with an eight second timeout. Keep both the thread and the
timeout. With `ForegroundPrompt` wrapped around the request the tap starts and delivers audio.

**The "Audio Input" checkbox is a build setting, and the tap will need it once signed.** In
Xcode 26, Signing & Capabilities > Hardened Runtime > Resource Access > Audio Input writes
`ENABLE_RESOURCE_ACCESS_AUDIO_INPUT = YES` into `project.pbxproj`, and the build turns it into
`com.apple.security.device.audio-input`; it never touches `Config/MiniNotch.entitlements`, so
checking that file for it proves nothing. It needs no paid account (an ad-hoc build embeds it).
An ad-hoc build is signed without the hardened runtime flag (`codesign -dv` shows only
`flags=0x2(adhoc)`), so today nothing enforces it; a real Apple Development signature applies
the hardened runtime, and a Core Audio tap app then carries this entitlement, as AudioCap does.
Do not add App Sandbox to get it: Audio Input lives under Hardened Runtime too, and MiniNotch
assumes it is unsandboxed. An explicit build setting beats the file's `app-sandbox` `false`.

**Old builds leave entries behind that a switch cannot fix.** Every differently signed build
(each ad-hoc one before signing, and each copy at another path) adds its own MiniNotch row to
Privacy & Security, and macOS matched against a stale one: the user switched MiniNotch on, re-added
it with +, and `--check-keys` still said `accessibility trusted: false`. `tccutil reset
Accessibility com.minnotch.MinNotch` cleared seven of them; then the HUDs pane's Allow… (which
calls `AXIsProcessTrustedWithOptions` with the prompt, so it is the running copy that is listed)
and one switch fixed it. That reset changes the user's privacy settings, so it is theirs to run.
`SystemKeyInterceptor` logs every key it sees and what it did (`Key volumeUp: taken`) at info
level; read them with `/usr/bin/log`, not `log`, which in zsh is a shell built-in that silently
does something else. Confirmed against real key presses on 2026-10-02, not only simulated ones.

**Never test permissions by running the binary directly.** A process started from a shell has
the terminal as its responsible process, so TCC judges the request against the terminal and
reports a different status than the real app sees. `--check-permissions` run from a shell will
say `notDetermined` even when the app has full access. Always launch through LaunchServices:

```bash
open -n -a <path to MiniNotch.app> --args --check-permissions --out /tmp/perm.log
```

## Permissions this app asks for

| What | API | When |
|---|---|---|
| Calendar | EventKit `requestFullAccessToEvents` | First time the Calendar widget or pane is used |
| Network (lyrics) | `URLSession` to lrclib.net | Only when Settings > Media > Lyrics Source is set to Look Up Online |
| Automation (Music, Spotify) | Apple Events | First media read |
| Accessibility | `AXIsProcessTrustedWithOptions`, then a `CGEvent` tap | Switching on HUDs > Hide the System Overlay |
| Notifications | `UNUserNotificationCenter` | First low-battery alert |
| Downloads folder | Reading `~/Downloads` | Switching on Layout > Downloads |
| Location | `CLLocationManager`, then Open-Meteo | Weather on with Use My Location; Allow in Weather, the Weather tab, or the tutorial |
| Touch ID or password (not a permission) | LocalAuthentication `deviceOwnerAuthentication` | Unlock in the Clipboard tab, with Blur Until Unlocked on |

None are requested at launch. The first-launch tutorial explains each one on its permissions
page, only for features that were ticked, and offers an "Allow Now" button for Calendar and
Notifications. That is the one moment a prompt is welcome: the reason is on screen, and the
tutorial window is frontmost, which this accessory app otherwise never is.

## Settings search

The index, `SettingsSearchIndex.all`, is a flat list, because SwiftUI cannot be asked what rows
a pane contains. It was generated from the panes, and it drifts the moment a row is added or
renamed without it. **Run `Scripts/audit-search.sh` after touching any `SettingsRow`.** It
caught a rename on its first run.

Three things about ranking were wrong first, and `--check-settings-search` is how each showed:

- **Card headers have to be searchable.** "Pomodoro" is in no row's title or subtitle, only in
  the header above the rows, so the search a user would actually type returned nothing.
- **A pane's synonyms belong to the pane, not to its rows.** Applying them to rows matched every
  row in the pane at once: "monitor" returned all nineteen Advanced rows alphabetically, with
  the display ones buried under Clipboard History. Synonyms surface the pane as its own result.
- **A word that starts with the query ranks like a title that does.** Otherwise "Glow Radius"
  beats "Enable Ambient Glow" on a technicality.

Rows and panes do not know search exists. `SettingsRow` and `SettingsPane` read
`settingsSearchTarget` from the environment, scroll and flash when it names them, and the root
view clears it after a moment so returning to the pane later does not replay the flash.

**Neither Settings nor anything using materials can be captured.** `NavigationSplitView` and the
sidebar come back from `cacheDisplay` as a blank white rectangle, not just from `ImageRenderer`.
That is why the search check is text, and why the tutorial is drawn in plain colours: so
`--capture-onboarding` can read every page back from the real window.

## First-launch tutorial

Every checkbox is an `OnboardingFeature` that reads and writes the real settings it stands for,
so the tutorial never holds a second copy of the configuration. Nothing is written until the
checklist is confirmed, and confirming writes every available feature, ticked or not, so the
result is exactly what was on screen. Skipping keeps the defaults. A feature whose `FeatureFlag`
is off is not offered at all.

Recommended leaves out anything that sends data off the Mac, watches the clipboard, or costs
real power. Those are fine features, but each is a choice someone should make on purpose.

A rerun from Settings starts the checklist from the current configuration, not the preset,
because "show me the welcome again" does not mean "reset me to Recommended".

## What's New

`ReleaseNotes.latest` is the release notes window, shown once at launch when its `id` differs
from the one last seen, and from the menu bar's What's New item any time. A first launch marks
it seen, because a new user gets the tutorial and has nothing to compare against. **Before
handing the user a build to share, update `ReleaseNotes.latest` and change its `id`**, and bump
`MARKETING_VERSION` to match. Notes are for people using the app: what they will notice, and
for anything new, where it is and how to switch it on. Nothing internal. In a Debug build the
open panel's top bar has What's New and Tutorial buttons (`AdvancedSettings.showDebugButtons`,
defaulting on only under `#if DEBUG`) for checking both at a glance. Review it with
`--capture-whats-new`, which renders the notes on their own because a window capture does not
draw `ScrollView` content.

`CFBundleVersion` is `$(MARKETING_VERSION)`, not a build number: Sparkle decides what is newer from
it, and the build number had been 1 for every release. `ReleaseNotes.latest` is 0.6.0 and `MARKETING_VERSION` matches. 0.6.0 was released on 2026-10-05
as the GitHub release `v0.6.0`, signed with the personal team like 0.2.0 to 0.5.0, at the user's
request ("release 0.6"). The next shared build needs new notes, a new `id`, and a
version bump. When the README describes something on
`main` that no download has yet, mark it _(next)_ and take the markers out at release.

**Settings says what is new.** `SettingsNewRows` maps row titles to the release that brought them,
and every row from `ReleaseNotes.latest.version` gets a "New" badge, as does its pane in the
sidebar. Add a release's new and renamed rows there when writing its notes;
`Scripts/audit-search.sh` fails if a title there is not a real row, which is how a rename that
would silently drop its badge gets caught.

## Releases

`Scripts/release.sh` builds Release, stages the app next to an Applications symlink, makes
`dist/MiniNotch-<version>.dmg`, and prints the `gh release create` line that publishes it with
`Scripts/release-notes.sh` as the description, so GitHub and the in-app What's New window say the
same thing. It warns when `ReleaseNotes.latest.id` and `MARKETING_VERSION` disagree, because that
combination means nobody updating sees the window.

**A signature made with a personal team carries the Apple ID it was issued to.** `codesign -dvvv`
on a build signed here prints the user's iCloud address, and that travels in every DMG. That is
what `--anonymous` is for: it re-signs the staged copy ad-hoc, keeping the entitlements, so the
download carries no team and no address. It costs the people who install it the system audio
permission, which cannot be granted to an ad-hoc build at all, and resets their other grants on
every version. Neither choice is free; do not make it silently on the user's behalf.

Nothing is notarised, because that needs a paid membership, so a first download needs
Privacy & Security > Open Anyway once.

**Updates are Sparkle, fed from `appcast.xml` in the repository.** Set up on 2026-10-05; 0.7 is the
first version that has it, so anyone on 0.6 or older updates to 0.7 by hand once. `SUFeedURL` is the
raw GitHub URL of `appcast.xml`, and each entry's enclosure is the DMG on that version's GitHub
release. `Scripts/release.sh` calls `Scripts/appcast.sh`, which signs the DMG with Sparkle's
`sign_update --account mininotch` and writes the entry; publish the release, then commit and push the
feed, never the other way round. The EdDSA private key is in this Mac's login keychain under the
account `mininotch` (public half `SUPublicEDKey` in `Config/Info.plist`). **If it is lost, installed
copies can never verify another update**, so it should be backed up with `generate_keys --account
mininotch -x <file>` somewhere safe, never in the repository. A key under the account `minnotch` was
made first, before the rename, and never used for anything; it can be deleted. Sparkle also requires
the new app's code signature to match the installed one's, so `--anonymous` and team-signed releases
cannot update each other: pick one and keep it (the user has always chosen the team).

`UpdateService` starts only in a release build, because a development copy shares the bundle
identifier and would offer to replace itself with the last release. A scheduled check that finds
something activates the app so the window is in front (`supportsGentleScheduledUpdateReminders`).
Sparkle does its own networking, the one exception to `BoundedHTTPClient`: HTTPS only, and nothing is
installed that fails the signature check.

**Adding Sparkle meant three project file edits**, the only ones beyond build settings: the package
reference and product dependency, and `LD_RUNPATH_SEARCH_PATHS = @executable_path/../Frameworks`, without
which the app linked Sparkle and then failed to launch (`Library not loaded: @rpath/Sparkle.framework`).
Xcode copies and signs a binary package's framework into the app by itself; an explicit Embed
Frameworks phase on top of that broke the build with "The file Sparkle couldn't be opened".

**Testing an update end to end** (`--check-update --feed <url> --out <file>`, DEBUG): build two
versions with `PRODUCT_BUNDLE_IDENTIFIER=com.minnotch.MinNotch.updatetest` and `MARKETING_VERSION`
overridden, so nothing touches the real app's defaults or copy, which the tool refuses to run as.
Sparkle refuses `file://` feeds and the app's transport security refuses plain `http`, so add
`NSAllowsLocalNetworking` to the two test copies only, re-sign them with the same identity and
entitlements, pack the newer one, run `Scripts/appcast.sh <dmg> --url http://localhost:8765/<dmg>
--feed <dir>/appcast.xml`, serve the folder with `python3 -m http.server 8765 --bind 127.0.0.1`, and
launch the older copy with the flag. On 2026-10-05: 0.6.90 found, downloaded, verified and installed
0.6.91 and quit; the same feed with one character of the signature changed was refused ("EdDSA
signature does not match") and left 0.6.90 in place.

## No setting may be inert

Every persisted setting must be read by something. A control that saves a value and changes
nothing is worse than a missing feature, because it tells the user a lie they cannot detect.
Audit it with a script that lists each property in `Core/Settings/Sections` and greps the rest
of the tree for readers, excluding the section's own file and its pane. The expected result is
three false positives: `accentMode` and `customAccent`, read through `resolvedAccent`, and
`ShortcutSettings.bindings`, read through `combo(for:)`. All three are read by an accessor in
their own section's file, which is what the grep cannot see.

If a feature genuinely cannot be built, delete its setting rather than badging it forever.
`showOnLockScreen` was once removed on the belief that macOS composites no third-party window on
the lock screen. That was wrong, which is its own lesson: no public window level reaches it, but
a private one does, and it is back as `HUDSettings.showOnLockScreen`. See the lock screen note
under "How the trickier features behave". Before deleting a setting as impossible, look for how
the apps that do it manage it.

## How the trickier features behave

**The lock screen is a space above every other, and SkyLight can make another above it.** No
window level an app can set reaches the lock screen, because it is its own window server space
drawn over all the ordinary ones. Spaces can have an absolute level, though, which is how
Notification Center shows on a locked Mac: 300 is the lock screen, 400 is Notification Center at
the lock screen. `LockScreenSpace` loads `SLSSpaceCreate`, `SLSSpaceSetAbsoluteLevel`,
`SLSShowSpaces` and `SLSSpaceAddWindowsAndRemoveFromSpaces` from SkyLight at run time, creates a
space at 400, and moves one window into it. `LockScreenController`
(`Features/LockScreen/`) makes that window on `com.apple.screenIsLocked` and throws it away on
`com.apple.screenIsUnlocked`. It can never become key, and draws the HUD while there is a
reading, else the song with previous, play and next in the sneak peek's layout, else nothing.
It takes clicks only while the song's controls are showing (`onInteractiveChange` flips
`ignoresMouseEvents`): a window at the top of the lock screen that swallowed clicks for nothing
would be a trap. HUDs and media each have their own switch. It is a window of
its own, not the notch's, so the private calls can never leave the real notch in a space it
should not be in. `--check-lock-screen` proves the calls resolve and a moved window stays on
screen, and the user confirmed on 2026-09-24 that the HUD really does draw over a locked Mac.
Private API, so it cannot ship in an App Store build.

**An `if` in a modifier is two different views.** `PanelShadow` applied `.shadow` only while
open, through an `if`, and that gave the whole surface a new identity when the notch opened: the
pill was replaced by a panel that took its final size on its first frame, and the two
cross-faded instead of one box growing. The user saw the panel come apart. The shadow is now a
layer of its own behind the surface, present for as long as the setting is on and faded with the
spring. Anything that changes with open and closed goes in a value, never a branch around the
surface.

**A hidden virtual notch is invisible, not absent.** Advanced > Hide Until Hovered
(`hideVirtualNotchUntilHover`) is for an external monitor where a black tab at the top is
unwanted. While it is at rest (`NotchRootView.isHiddenAtRest`: the setting, no physical notch,
closed, no HUD) the surface keeps the virtual notch's own rect and its `.contentShape`, so
hovering there still reaches `NotchViewModel.hoverChanged` and a click still opens it. Only the
clipped fill and content fade to zero opacity, and the glow's `isVisible` goes false.
`isHiddenAtRest` sits in `SurfaceMetrics`, so the fade rides the same spring that grows the box:
opening, the panel grows out of nothing; closing, it shrinks back into nothing. It is a value and
never an `if` around the surface, for the reason under "An `if` in a modifier". The sneak peek and
the closed lyrics strip are off on a hidden notch, so nothing reveals it on its own, but a
volume or brightness HUD still shows because it answers what the user just did. A real notch is
never affected. `--capture-notch --virtual --collapsed --extended --hide-virtual` must draw
nothing at all; add `--midway 0.12` without `--collapsed` to see it grow in.

**While the pill is the notch's size, the glow traces the housing, not the pill.** `NotchShape`
insets its body by the shoulder radius, so at the notch's width the body is nine points narrower
than the housing on each side, and the housing has no pixels. The glow's sides started inside it
and only their blur's tail reached the screen: one point outside the housing, alpha 71 at the
sides against 197 below. `NotchRootView.glowShape` traces the housing in that one case, and the
two now measure 209 and 200. Capture with `--collapsed --placements closed,open` and read alpha
just outside `x = 494` and below `y = 63` to check it.

**The song is not a live activity.** It used to be presented as one, the lowest priority, which
put the artist in the Live Activity slot with no choice of title and never took it down again, so
the pill named an artist after the player had quit. `PillIndicator.song` reads the track directly
and shows the title or the artist (`GeneralSettings.pillSongText`), capped at 120 points because
both flanks are drawn at the wider one's width and one long name made the pill reach halfway
across the menu bar. A settings file without `pillSongText` predates it and gets the Song placed
beside its Live Activity, once. The cover and the song show while a song is loaded, paused or
not; the playing indicator shows whenever something plays, beside the cover rather than instead
of it.

**Weather sends two rounded numbers, and only when asked to.** `WeatherService` fetches from
Open-Meteo (free, no key) through a `BoundedHTTPClient` allowed only its two hosts, with the
location rounded to two decimals, about a kilometre, in `OpenMeteo.forecastURL`. The place name
comes from Apple's reverse geocoder, so Open-Meteo never sees more than the two numbers. Location
needs three things, the same lesson as the audio tap: `ENABLE_RESOURCE_ACCESS_LOCATION = YES`
(the hardened runtime refuses Core Location without it), `NSLocationUsageDescription` in
`Config/Info.plist`, and the request made from the foreground. A typed city needs none of them.
Every settings change fans out to `settingsChanged`, so the service compares the weather section
with the one it last applied and only then touches the network; otherwise it refreshes on a half
hour timer, which the pill needs because it shows the temperature with the widget closed. Times
are asked for as Unix seconds and labelled in the place's own time zone. `--check-weather London`
or `--check-weather 51.5 -0.13` fetches for real; `--sample-weather` captures the tab and the pill
offline.

**The output switcher is public Core Audio, and AirPlay is one device.** `AudioOutputService`
lists devices with output streams that can be the default, leaving out hidden ones and aggregates
(the audio tap builds a private aggregate to listen through), and sets
`kAudioHardwarePropertyDefaultOutputDevice` and the virtual main volume, which is all the Sound
menu does. No permission. AirPlay receivers cannot be listed or picked without private API, so
AirPlay is one row and the Settings subtitle says to pick receivers in Control Center. The sheet
takes the lyrics sheet's place, never both, and sizes to the outputs there are, one to four; the
button reads the list before opening so the card is the right height on its first frame.
`--check-audio-outputs` lists what the card would offer, read-only, and `--output-sheet` captures
the card with the list open.

**Notch Styles are data, drawn by one set of views.** Settings > Appearance > Notch Style picks a
design language (Minimal, Bento, Glass, Neumorphic, Clay, Skeuomorphic) and Dark, Light or Match
System, labelled Auto as macOS's own Appearance settings do (`AppearanceSettings.notchLanguage`, `notchVariant`, decoded leniently, so a file from before
lands on Minimal Dark). `NotchStyle` is a plain value resolved from them (`AppEnvironment.notchStyle()`,
with `SystemAppearance` for Match System) and read from the environment: `ink`, the surface, and a
treatment per kind of element (tile, button, module, transport disc, groove, the accent fill, the
artwork) plus the glow's strength and the room modules need. The twelve are functions in
`NotchStyleCatalogue`. Views never ask which language is on: rows are `NotchElementView(.tile,
emphasis: 0.05)`, a hover highlight `NotchElementView(.button, emphasis: isHovering ? 0.08 : 0)`, a
bar's groove `.groove` and its fill `NotchTrackFill`, a group of content `.notchModule()`, where the
emphasis is the white opacity the site always used. A plain element draws exactly that fill; a
styled one reads it as how much to light up. Shadows and highlights are blurred shapes flattened with
`drawingGroup` and given room, because a layer filter does not appear in `--capture-notch`.

**Minimal Dark is the notch as it always was, and that is checked, not assumed.** Its catalogue entry
holds the old literal values, and `Scripts/style-diff.sh <a build from before>` captures 25 still
states and the Layout miniatures with both builds and compares every pixel (`png-diff.swift`). It
found every refactor step identical; the only changes it ever showed were deliberate, the symbol
colour fixes above. Keep a pre-change build to compare against before touching anything a style
reads. Captures use `--builtin`, because which screen is "main" changes with whatever the user
clicked, and one capture landing on a 1x external monitor fails the whole comparison.

**Over a camera housing the closed notch stays black, in every style** (the user's choice, "a",
2026-10-05). The housing is black hardware, so any surface that is not black shows it as a hole. On
a notched Mac the closed notch, its HUD, peek and lyrics draw in the language's dark variant
(`darkVariant`) over a black cover whose opacity rides the open spring, so the panel lightens as it
grows; the open panel draws the housing as a black tab with the hardware's corners. On a display
without a notch the whole style applies. Full Artwork's header also takes the dark variant, since it
sits on the darkened cover. Minimal Dark's surface is already black and draws neither cover nor tab.

**Modules make room for themselves, and only where a style has them.** A module reaches outside its
content (`notchModule(horizontal:vertical:)`) instead of padding it, so content keeps its place, and
`NotchStyle.moduleGap` adds the room: above the first module (`ExpandedPanelView`), between the music
card's parts, and to the panel's height (`NotchRootView`, the floating window). Minimal's gap is 0.
The floating volume pill holds its row in a module inset past the notch's shoulders.

**Glass is a real behind-window material, which no capture can show.** `--capture-notch` draws the
tint and edges only. Checked once on screen with `screencapture` (2026-10-05): the desktop blurs
through, and the blur stays inside the rounded shape. Translucent Panel is Minimal's only; Glass is
always see-through. `--capture-styles` renders every miniature for the picker, since the Settings
window cannot be captured; `--notch-style <language>-<dark|light>` on the capture tools draws any
style, and `Scripts/contact-sheet.swift` lays captures side by side. Light styles give multicolour
weather symbols a faint outline (`notchMulticolorSymbol`), because their clouds are white.

**Liquid Glass is a background under any style, macOS 26 only.** Settings > Appearance > Notch Style >
Background (`AppearanceSettings.notchBackground`, Solid or Liquid Glass). `NotchStyle.resolve` sets
`surface.liquidGlass` when it is chosen and `NotchBackground.isLiquidGlassSupported`; the surface is
then SwiftUI's `glassEffect` in the notch's own outline, and the style's glass, grain and edge give
way to it. It is Apple's *clear* glass, the see-through kind that bends what is behind it, with what
makes glass read as glass laid on top: a bright edge along the sides and bottom, a sheen across the
top, and a light dim (black 0.22 on a dark style, white 0.4 on a light one) so text stays legible
over a busy desktop. Glass Opacity (`liquidGlassOpacity`, 0 to 1, default 0.45, light styles take
0.72 of it) tints it towards the style's base and lays the base over it by the square of the
amount, to nearly the solid style at 1; the dim, edge and sheen fade as it rises. It took four
rounds with the user: clear glass alone was all but invisible over a plain or dark window; regular
glass came out a smooth grey slab over dark windows; regular glass under a milky frost read as
frosted plastic ("more glassy"). Four candidates were then compared on screen over a dark and a
bright pattern, and this one showed the window behind through the glass, bent at the edge, with
text legible. A style's panels, tiles, buttons and grooves let the glass through too (`glazed`, from
about 40% solid at 0 to solid at 1): solid panels sat on the glass as slabs, and Neumorphic, whose
look is panels the colour of the surface, showed almost no glass at all. Their outer shadows are
masked to outside the shape (`NotchElementView`), since a shadow seen through a glass panel looked
like dirt rather than depth. `--backdrop` puts a bright,
detailed test pattern behind the notch for judging glass on screen (`--dark-backdrop` a dark one,
`--floating` the floating window too). Before looking at a screenshot of the real screen, check its
corners are the pattern: one that shrank let the user's own windows into the shot. Before macOS 26 the row is shown switched off with
"Liquid Glass needs macOS 26 or later", and a saved Liquid Glass draws Solid. Glass takes its
appearance from its surroundings, which follow the system, so the surface sets the style's
colour scheme on it (`NotchSurfaceStyle.isDark`): a light style on a dark Mac drew dark glass under
dark text. No capture can draw it; it was checked with `screencapture` on 2026-10-06.

**Tried and rejected on 2026-10-07: the desktop barely blurred.** After another "more glassy", the body
became an `NSVisualEffectView` with its backdrop blur turned down to 6 points (its `gaussianBlur`
filter, through `filters.<name>.<key>`) under a 14 point rim of Apple's glass. It was see-through
and bent at the edge, and the user disliked it on sight ("I don't like this background") and asked
for this one back; it was reverted. Do not offer it again. Two things learned on the way still hold:
Apple's glass frosts with its size, about fifty points of blur at the panel's size, so no layer on
top makes it clearer; and quit the running MiniNotch before judging glass on screen, because its
open panel sits at the same level in the same place and shows through a test panel.

**What playing costs, and why the picker is pictures.** With nothing moving the open panel costs
almost nothing; playing (the artwork's visualizer at 20 Hz, the lyric highlight at 10 Hz) redraws
what sits over it. The album art's shadow used to sit over the visualizer, so it was blurred again on
every tick; it now sits under it, which looks the same (the cover is opaque) and costs much less.
Measured with `--capture-notch --hold 9` and the GPU's `Device Utilization %` from `ioreg -c
IOAccelerator`, which is noisy with other apps running, so compare runs in alternation. The Notch
Style tiles in Settings are rendered once each into a picture (`NotchStylePreviewCache`), because six
live miniatures full of blurred layers made scrolling Appearance heavy, and the Ambient Lighting
preview pauses scrolled away (macOS 15+) or with the window behind. An open panel closes when the
desktop changes (`NSWorkspace.activeSpaceDidChangeNotification`), unless kept open: it sits above the
transition and Mission Control, and anything animating in it had macOS redraw the lot every frame.
There is no public signal for Mission Control itself.

**Two-finger swipes are a listen-only scroll tap, consulted only over a notch.** A local event monitor
saw swipes over the top bar and nowhere else: a scroll view under the pointer (clipboard, calendar
list, shelf, Notes, lyrics) takes a trackpad gesture's events off the queue for itself after the
first, so the monitor never saw the rest. The tap sees every scroll event before any window does,
needs no permission because it only listens, and returns at once unless a panel is hovered
(`NotchWindowManager.hoveredPanel`); the local monitor is the fallback if it cannot be made.

**Two-finger swipes read the fingers, not the content.** `NotchGestureMonitor` flips the deltas when
`isDirectionInvertedFromDevice` says Natural Scrolling has, so the directions are the same with it
off as with it on (they used to come out backwards with it off). Up and down over a scroll view with
more in it than shows belong to the list (a hit test up to an `NSScrollView`): scrolling the clipboard
used to close the notch. A mouse wheel has no phases, so a pause of 0.35 s starts a new gesture.
Momentum (the coast after the fingers lift) counts towards the swipe it belongs to, which still fires
once: a quick flick does most of its travel there, and ignoring it dropped flicks. A gesture is over
only when the next begins. A swipe to another tab (`NotchViewModel.swipe(to:)`) changes the height at
once, with the content: it used to hold the old height for 0.8 s so a run of swipes stayed under the
fingers, and the user saw every resize trail its tab ("queuing"). Two fingers do not move the pointer,
so after a swipe to a shorter tab it rests below the panel over nothing. Until it moves
(`swipeAnchor`, checked every 0.1 s) it still counts as over the panel (`isHeldBySwipe`: swipes go
there, it does not close), and `NotchRootView.swipeCatcher` fills the old height at alpha 1/255,
invisible, because the window passes events through where it draws nothing and the next swipe's
scrolling would reach the window behind (a browser takes a sideways one as Back). The old tab fades
out in 0.08 s (`ExpandedPanelView.tabChange`); on the box's spring its text lay over the new tab's.
`--capture-notch --tab shelf --swipe-to notes --midway 0.15` captures a swipe partway.

**Never read `AudioAnalyzer.current` in a view's body.** It changes with every audio buffer, about
ninety times a second. `NotchRootView` and the Ambient Lighting card read it to decide whether to
hand the analyser to the glow, so for as long as the tap ran the whole panel, and the whole card,
evaluated ninety times a second: the GPU load and lag the user saw while music played, in Mission
Control, and with Settings open on Appearance. Read `isRunning`; the glow and the meters read
`current` inside their own timelines. The capture tools never run the tap, which is why no capture
measurement caught it. Settings' meter also listens only while in view in a window in front.

**Liquid Glass shows what is behind it.** With clear glass, over a dark window with small text (the
user's chat) the notch looked nearly solid, and over a bright page see-through, which the user took
for the glass switching on and off at random; regular glass reads as glass over both. It is not the
app being active or not: `--capture-notch --activate` and `--key` drew the same.

**Files and links share the Shelf tab.** The user asked for the Shelf (files, AirDrop) and Links
(paste a link, copy it back) together, so `NotchTab.links` is a feature but no longer a tab:
`panelTab` maps it to `.shelf`, `NotchWidgetRegistry.availableTabs` lists the shared tab once, and
`selectedTab` turns a request for Links into the Shelf. The case stays so saved arrangements and a
remembered tab still decode; `TopStripLayout.resolve` drops the `.links` item because no shown tab
matches it. `ShelfTabView` draws files over links, each in a fixed-height `isCombined` layout so
the panel does not resize under a drop, and takes every drop itself (`ShelfTabDrop`): files go to
the shelf wherever they land, anything else to the links, and the half a drop will go to lights up.
A file is also a URL, which is why two separate targets would not do. Paste (⌘V) holds files copied
in Finder and keeps a copied link. With either feature off the tab is the other one, drawn as
before. Layout keeps a tile for each feature.

**Notes is one plain text file, typed into the notch.** `NotesService` keeps one note in
Application Support (`MiniNotch/Notes.txt`), written 0.8 s after typing stops and at once on quit;
nothing leaves the Mac. The tab (`NotesWidgetView`) is a `TextEditor` forced dark, because the panel
is black in both appearances and a light-mode caret is black on black. Typing works the way
Calendar's Quick Add does: the panel can become key, a click activates the app, and focus sets
`isInteractionLocked` so the panel cannot close mid-sentence. The Open Notes shortcut
(`HotkeyAction.quickNote`, unbound by default) opens the tab on the open or pointed-at panel, makes
that panel key (`NotchWindowController.takeKeyboard`) and asks for focus (`NotesService.wantsFocus`).
Advanced > Show Notes, on by default, and in the tutorial's Recommended set, since it is local and
costs nothing. A capture's sample note (`--sample-notes`) is never marked loaded, so it can never be
saved over the real one; `--check-notes` proves it with a scratch file.

**What's New and the tutorial share one debug button.** `TopStripItem.whatsNew` opens a small menu
(`NotchMenu`, an `NSMenu` at the pointer, so the button keeps the bar's look) offering either.
`.tutorial` stays as a case only so saved arrangements decode; `TopStripLayout.resolve` never shows
it.

**Shelf clicks and drags both arrive through `ShelfDragSource`.** The AppKit drag view covers
each chip so it can offer move or copy and hear how the drag ended, so it is also what receives
the click: a mouse-up with no drag in between is a click, and selects (⌘ toggles, ⇧ extends). A
drag from a chip inside the selection carries the whole selection, one `NSDraggingItem` per file,
and the URLs are fixed when the drag starts because the selection can change mid-drag. AirDrop is
`NSSharingService`'s picker, a window of this app's, so the app is activated first (no Dock icon
needed) and the service is held while the picker is open. The AirDrop tile is a drop target inside
the shelf's own: the innermost target under the pointer wins, so files dropped on it are sent
without being kept.

**A meeting link is found, never trusted.** `MeetingLink` runs a link detector over an event's
URL, location and notes, because Zoom, Meet and Teams each put the link somewhere different, and
takes the first https link to Zoom, Meet, Teams, Webex or FaceTime. A calendar invitation is text
anyone can send and Join opens the link with `NSWorkspace.open`, so a `file:` link, a custom
scheme like `zoommtg:`, plain http, and a lookalike host must all be refused;
`--check-meeting-links` has one of each. The countdown itself (`syncMeetingActivity`) runs on a
15 second tick whenever it is switched on, not only once the calendar can be read, because access
arrives from a dialog with no settings change to start a clock. A countdown swiped away stays
away: `LiveActivityCenter.putAway` remembers the id, which is per occurrence.

**Lyrics with the notch closed use the sneak peek's shape and size**, so a track change swaps what
the strip says rather than resizing the notch. The lyric strip on the card has a button for it,
left of the expand button, writing the same setting as Media > Show Lyrics When Closed. Only synced lyrics, only while playing; it redraws
ten times a second while it is up, about 4% of a core in a Debug build.

**Five things make the glow look right, and all five were bugs first.** A segment covering
the whole outline is stroked as a closed path, never as a trim from 0 to 1: a trim is an open
stroke, so it caps at both ends and the caps overlap at the seam, which on the closed pill is
a bright spot that reads as uneven lighting. Blur radius is capped against the shape's smaller
dimension, because a blur wider than the pill is tall smears its top and bottom edges together
and washes out the middle. The whole stack is wrapped in `drawingGroup()`, without which the
blur is recomposited per stroked shape every frame and drags the rest of the interface down.
And artwork colours are lifted through `ArtworkPalette.glowPrimary` before being used as
light, since a muted cover otherwise produces a glow too dim to see, which is why Rainbow
looked like the only style that worked. Last, the glow is drawn into a layer wider than the
outline it traces, because `NotchShape` insets its body by `shoulderRadius` and the blur was
otherwise chopped after nine points, leaving a hard-edged translucent bar down each side of
the panel instead of a fade.

**Raw analysis drawn straight is why a correct audio effect still looks flat.** A band's
magnitude is a noisy, mostly mid-scale number: it wanders, it rarely reaches zero, and it
never leaps, so a bar driven from it slides instead of striking. `GlowDynamics` is four
stages that fix that, and every one of them was missing. Auto-gain, a rolling floor and
ceiling per channel, so the same drum reads the same on a quiet master as a loud one. An
attack and decay envelope, near-instant up and a 220 ms half-life down, which is what turns
a momentary peak into something an eye has time to see. A damped spring, stepped by hand at
frame rate, so the drawn value chases the envelope and overshoots it rather than being
assigned to it: that overshoot is the entire difference between bouncing and snapping. And
an onset detector on the gained signal, before the envelope, so it sees the jump rather than
the ramp the envelope makes of it.

The spring cannot be `.animation(.spring)`. A SwiftUI animation restarts every time its value
changes, and this value changes every frame, so it never gets far enough into the curve to
overshoot and comes out looking exactly like a linear ramp.

**The fallback runs through the same chain as real audio, and that is not a nicety.** It was
the only thing that ever drove the glow until the tap started working, and it stays the path
for anyone who leaves audio-reactive off or refuses the permission. `GlowFallbackSource` therefore emits impulses rather than curves, because the
envelope and spring downstream exist to shape a bare "now" into a hit; a source that
pre-smooths its own oscillation gets shaped twice and arrives looking like breathing. Styles
do not branch on whether audio is live, deliberately: what they receive is the same kind of
number either way.

**Two things about the analyser were actively wrong before this.** It divided every band by
the loudest band in the same buffer, which guaranteed some band was always at full scale, so
the bars could never all drop together and there were no dynamics to see at any volume. And
it mapped linear FFT magnitude straight to level, which spends almost the whole range on the
difference between loud and very loud, leaving everything but the bass squashed near zero.
Bands are now decibels with a three-decibel-per-band tilt towards the top, because music
carries less energy per octave as frequency rises, and all the levelling happens once in
`GlowDynamics`, which runs per frame and therefore knows how much time has passed.

**Level has to move geometry, not just brightness.** Opacity saturates at 1 and the eye reads
size far more precisely than brightness, so an effect that only brightens reads as glowing
along with the music rather than hitting on it. Stroke width carries most of it, Bars also
varies each bar's arc length, Wave and Chase lengthen with energy, and the blur radius itself
rides the level, capped so it can never exceed the spill the caller promised.

**Glow styles return data, not drawing.** An `AmbientGlowStyle` turns `GlowInput` into
`[GlowSegment]` and never touches a graphics context, so a style can be reasoned about
without a renderer and a sixth one is a single function. Placement is a separate dimension
from style: the closed pill, the open panel, or both. The glow view stays in the tree for
both and fades with `isVisible` rather than being inserted, because an inserted view takes its
final layout on its first frame and would jump ahead of the growing box. There is no album art
placement: the artwork is drawn still, on purpose.

**Lyrics are matched to the audio by lining every line up with the singing at once.** The player's
clock is right and the *file* is wrong: LRCLIB alone holds a dozen uploads of one song, each a
slightly different length. `LyricsSyncCalibrator` takes the tap's `voiceLevel` (the centre of the
stereo image, 300 Hz to 4 kHz, less the sides, from `SpectrumFrameAnalyzer`), works out each
moment's rise (the next 0.12 s against the 0.25 s before), and keeps it on the track's clock in
50 ms bins. Every offset within ±2 s is scored at once: the rise at each sung line's start moved by
that offset, weighted by nearness, lines after a pause counting up to three times, less any rise
inside an instrumental break. It answers only when the best offset is clear of every other by
0.45 dB a line, when line starts stand 3.5 standard errors above random moments of the same audio
(`significance`), when nothing up to 12 s out fits better (`isBestFarAndWide`, a song's four bar
repeat sits about 9 s away), and once the answer has held while two more lines were heard. A
remembered answer (`LyricsSyncMemory`, hashed per track and file) applies from the first line of
the next play. The calibrator changes ninety times a second, so it is `@ObservationIgnored` and
views read `lyricsSync`, a summary published only when it changes.

It replaced a method that took the strongest jump in the 94 Hz to 1.5 kHz bands near each line
after a five second gap. Those bands hold the kick, snare and bass as much as the voice, and the
band comes back after a break before the singer does, so it locked onto the drums: on a real song
it moved on-time lyrics by +0.49 s and was half a second wrong on four of the five files it
answered, which is what "sometimes accurate, sometimes behind, sometimes ahead" was. Every
threshold above was set from `--check-lyric-sync --audio song.mp3 --lrc song.lrc --shifts …`,
which decodes a file through the live analysis and moves the lyric file by known amounts; the
right answer moves with the shift whatever the song's true offset is. On the one sung song
available (Life Is a Highway, a video version 27.25 s out), 9 of 9 files within reach came out
right to 0.05 s, answered once each and never changed; 7 of 7 too far out and 21 of 21 lyric files
against instrumentals were refused. It answers late, two to three minutes into a song, because it
waits to be sure; the memory is what makes that acceptable. Only one sung song has been through it,
so its thresholds are the first thing to revisit when a report comes in: `log show --predicate
'subsystem == "com.minnotch.MinNotch"' --info` prints every answer with its margin and
significance, and nothing about what played. `--check-lyric-sync` alone runs the synthetic cases.

**A glow that moves with nothing playing is worse than one that freezes.** `GlowFallbackSource`
used to breathe while playback was paused, so that the light never looked dead. In use that reads
as the effect following music badly, and it makes the audio-reactive version unprovable by eye:
the first question anyone asks is whether it is listening at all. Paused is now completely still,
verified by two captures 1.2 s apart being byte-identical, and Settings > Ambient Lighting has a
live meter of what the tap is hearing so "is this real" has an answer that is not a guess.

**Lyric timing is only as good as its timestamp.** `NowPlayingController` stamps the
capture time on the queue that read the player, not on main after the hop. Each read still carries
its own error, so a poll that disagrees with the running clock by under a quarter second moves it
a third of the way (`smoothedPosition`) instead of resetting it, which kept the highlight from
twitching twice a second; a larger difference is a seek or a stall and is taken at once. An Apple Event
round trip is a hundred milliseconds or more, and timestamping on arrival makes every later
extrapolation that much late, which shows up as the lyric highlight trailing the vocal.
`lyricsTime(at:)` adds the user's offset on top and is separate from `elapsed(at:)` so the
correction never moves the scrubber.

**A download is a folder watch, not a browser integration.** Every browser writes a download to
a temporary name and renames it when it finishes: Safari to a `.download` bundle, Chrome and its
relatives to `.crdownload`, Firefox to `.part`. `DownloadsMonitor` watches `~/Downloads` for
those and treats the rename as the finish, which works for browsers nobody has thought about and
needs nothing from any of them. Progress comes from the `NSProgress` a browser publishes for the
file, the same thing Finder's progress bars read, with Safari's `Info.plist` byte counts as a
fallback; a download nobody publishes progress for still shows, without a percentage. Reading the
folder is a permission, so the feature is off by default and asks from the foreground.
`--check-downloads` plays a Chrome download, a Safari one and a cancelled one out in a scratch
folder, which is the only way to check this without a network and a browser.

**An accessory connecting is a registry notification, not IOBluetooth.** `IOBluetoothDevice`'s
connection callbacks would mean the Bluetooth permission for something the user did not ask for.
`IOServiceAddMatchingNotification` on the same charge-reporting classes the System tab reads says
"a device appeared" for free, and the charge is read two seconds later because a service that has
just matched has usually not published it yet. The iterator has to be drained once when it is
armed, or everything already connected arrives as news at launch.

**Clicking a lyric line seeks by lyric time, not by track time.** The strip's clock is
`elapsed + offset + audio correction - latency`, so seeking to a line's timestamp directly would
land that far from the line. `seek(toLyricsTime:)` takes the difference between the two clocks
and undoes it.

**The audio tap listens only while something plays.** Both of its users want music: the glow
stands still with nothing playing, and lyrics exist only while a song does. It used to run for as
long as Follow the Beat or Fix Timing Automatically was on, about 6% of a core analysing silence.
`AppEnvironment.applyAudioAnalysisSetting` now starts it on `NowPlayingController.onPlayingChange`
and pauses it 20 seconds after playback stops (`audioIdleGrace`, which rides out a skip or a
pause). The pause is `AudioAnalyzer.pause()`, not `stop()`: `stop()` clears a recorded failure so
that switching the setting off and on asks again, and a pause that did that would re-prompt a
refused permission at every song. The Ambient Lighting meter keeps it listening while it is on
screen (`beginAudioPreview`), playing or not. The output latency is kept across a pause
(`hasMeasuredLatency`), so lyric compensation does not drop out for the moment a tap takes to
start. Idle with nothing playing measured 0.2 to 0.3% after, against about 6% before. Siri's
`corespeechd` holds a tap of its own, so `pmset -g assertions` showing an `AudioTap` is not proof
MiniNotch is listening: check the PID it was created for.

**Keep the Notch Open holds the panel on the display it is open on.** ⌃⌥P by default (Settings >
Shortcuts), or the top bar's Keep Open pin, which can be placed in Layout and appears by itself
while the panel is kept, so letting go is always on screen. `NotchViewModel.isKeptOpen` stops the
pointer leaving and a click on the panel from closing it; `collapse()` clears it, so anything that
closes the panel on purpose lets it go and it can never be stuck. `NotchWindowManager.toggleKeepOpen`
picks the panel that is open, else the one under the pointer. In Follow the Pointer mode the one
notch already stays put while open, so a kept panel stays on its display while the pointer works
on another. A new shortcut's default reaches settings saved before it through
`ShortcutSettings.knownActions`: an action missing from it gets its default once, unless the combo
is taken, because a cleared shortcut and an unknown one are otherwise the same missing key.
`--check-keep-open` covers all of it.

**The clipboard is the one sampler that does not stop when nobody is looking.** Every other
polling service is reference counted to the view that displays it, because nothing is lost by
not sampling while the panel is closed. A clipboard history is the opposite: copying happens
while the user is working in another app, which is exactly when the notch is shut, so a
history that only recorded while its own widget was on screen would record almost nothing.
`ClipboardHistoryService` polls whenever the feature is on, and the reference count raises the
rate from 1s to 0.25s while the widget is visible rather than gating the timer. The read
itself is one integer, `NSPasteboard.changeCount`, which is what makes that affordable. It
never writes history to disk, and it skips anything marked with the `org.nspasteboard`
concealed or transient types, which is how password managers ask not to be remembered.

**Apple's Passwords app marks nothing, so its copies are skipped by who was in front.** The user
found a password copied there in the history. The pasteboard does not record which app wrote to it,
so each poll remembers every app that came to the front since the last one
(`didActivateApplicationNotification`) plus the one in front now, and a change made while any of
`ClipboardHistoryService.privateApps` (Passwords, its menu bar item, Keychain Access) was among them
is never read, as Maccy does it. Copying in Passwords and switching away within the second is
still caught; a copy elsewhere in a moment that also visited Passwords is lost, which is the
right way round.

**Blur Until Unlocked never draws the real text while locked.** Advanced > Clipboard > Blur Until
Unlocked, on by default at the user's request, blurs the Clipboard tab until `OwnerCheck` (LocalAuthentication's
`deviceOwnerAuthentication`: Touch ID, else the login password, or a Watch; no permission or
entitlement), from the Unlock button or a click on a row, which then copies it. A locked row draws
filler text as long as the real one, blurred, so a blur that fails to apply, an accessibility
client, or a capture finds nothing; the swatch and the kind's icon stay. A plain `.blur` is a layer
filter that `--capture-notch` does not draw, which is how this was found: the first capture showed
the real text, sharp. The blur is baked in with `drawingGroup`, with padding so it fades inside
the layer. `isRevealed` lives in the service and only `reveal()` sets it, ignored while no view of
the tab is open; it clears when the last one closes (`endSampling`), when the screen locks, when
the Mac sleeps, and when the setting is switched on. The panel is held open
(`isInteractionLocked`) while the dialog is up. `--check-clipboard` runs the recording and the
blur rules on a private pasteboard; the dialog itself can only be tried by hand.

**The timer counts against a deadline, not down from a number.** A tick that is late, and
every timer tick is late sometimes, would otherwise lose that time for good and a
twenty-five minute Pomodoro would quietly run long by however busy the machine was. The tick
only decides when to redraw. Pomodoro is a preset on the countdown rather than a system
beside it: the only thing that makes an interval a Pomodoro is what happens when it ends, so
`TimerPhase` decides whether anything follows and the timer stays one thing.

**Sampling is reference counted to the view that shows it.** `BluetoothBatteryService`, the
charging power and the HUD's brightness polling start on `onAppear` and stop on `onDisappear`, because a menu bar
utility that wakes every couple of seconds forever is a battery complaint waiting to happen.
Volume is the exception: CoreAudio pushes changes, so it costs nothing to leave attached.

`SystemStatsService` is the other exception, like the clipboard. It used to stop with the System
tab and throw its history away, so the graphs only ever showed the seconds since the tab opened,
and the user asked for them to be kept. It now samples at the refresh interval while the tab is
open and every five seconds otherwise (temperatures every fifteen), with timer tolerance so the
wakeups can share, and not at all while the readout is off or in Low Power Mode. The history is
timestamped and kept for five minutes. Measured on its own, `--check-stats-history` (27 s, five of
them at one sample a second) used 0.07 s of CPU, about a quarter of a percent of one core.

**Temperatures come from private HID sensors, and never on main.** `TemperatureSensors` loads
`IOHIDEventSystemClientCreate` and `IOHIDServiceClientCopyEvent` from IOKit at run time (they are
not in the headers), matches the vendor thermal sensors (usage page `0xff00`, usage 5), and reads
temperature events from them, which is how monitoring apps such as Stats do it. Apple silicon does
not label them CPU or GPU, so the chip temperature is the hottest `PMU tdie` sensor, beside the
battery's fuel gauge and the SSD's `NAND` sensor; values outside 5 to 130 °C are calibration
readings (`tdev` reads -22 on an M4) and are dropped. One read of the 31 sensors used takes about
25 ms on an M4, a round trip each, so it runs on the sensors' own queue and lands in the readings a
moment later, one interval behind the history. Units follow Settings > Weather > Temperature Units,
with the unit letter shown, since a chip at "138°" looks broken to someone used to Celsius.
`--check-temps` lists every sensor this Mac offers.

**Charging power comes from the SMC, not the battery's registry entry.** While plugged in, the
System tab shows what the charger delivers, what the Mac uses and what goes into the battery, over
a bar as wide as the charger's rating, with the battery's share as a percentage
(Settings > Battery > Show Charging Power). The battery's IO registry entry has a
`PowerTelemetryData` dictionary that looks like the answer and is not: it refreshes about every 45
seconds, its load and battery figures disagreed with the battery's own current while charging, and
on battery it reported a power in of 2^64 - 160. `PowerSensors` reads the SMC instead, as Stats and
AlDente do, through the `AppleSMC` user client any process may read: `PDTR` (watts in), `PSTR`
(watts the Mac uses, not counting the battery) and `B0AC` × `B0AV` (battery milliamps and
millivolts, positive while charging). These update every second and add up to within a watt or two
of conversion loss. Apple silicon stores them little-endian, `flt ` for the watts and `si16`/`ui16`
for the battery; the Intel path (big-endian, `sp78`-style fixed point) is written and has never run.
The request struct is handled as 80 bytes at C's offsets, because a Swift struct does not promise
C's padding. A reading is about 1 ms, on its own queue. `BatteryService` reads once a second, only
while plugged in and while the System tab is showing it, and smooths over about three seconds,
because the Mac's own draw swings by several watts a second. The row's height is reserved from
`showsChargingPower` (plugged in, setting on, keys present), not from the first reading, so the
panel is the right height on its first frame. The charger's rating is public
(`IOPSCopyExternalPowerAdapterDetails`). `--check-power` prints each figure, what it is made of,
and the loss; `--sample-power` captures the row with fixed numbers.

**Each System reading has its graph under it.** `StatChart` draws the last five minutes by time,
newest at the right edge, and breaks the line where samples are more than 20 s apart (the Mac
asleep or in Low Power Mode) rather than joining across the gap. It used to sit faintly behind the
numbers with a history thrown away whenever the tab closed, so what anyone saw was a few seconds
of it, a sliver against the cell's edge that read as a glitch.

CPU and network are deltas between two readings, so `beginSampling()` takes one sample to
establish a baseline and a second 0.3s later; without that the first thing the user sees is a
zero that sits there for the whole refresh interval. GPU utilisation comes from the
`PerformanceStatistics` key in the IORegistry, which needs no entitlement but is not published
by every Mac. A nil reading means "not reported here", not "idle", and the cell says so.


**The closed pill defaults to seamless.** `GeneralSettings.extendPillForIndicators` is off,
so at rest the pill is exactly the size of the hardware notch, which on a notched Mac means
it is invisible. Turning it on widens the pill either side of the cutout to show battery and
playback, because those strips are the only place content is visible on that hardware.

**Lyrics need the online source to be useful.** Apple Music does not expose its synced lyrics
to AppleScript, and a streamed track's `lyrics` property is almost always empty, so
`AppleMusicLyricsProvider` only finds anything for files the user tagged themselves.
`LRCLIBClient` is the path that actually works, and it is opt-in via
`MediaSettings.lyricsSource`. When there is nothing to show, the strip renders
`LyricsStatus.message` rather than collapsing, so an empty strip always explains itself.

The strip highlights the individual word being sung. Enhanced LRC carries `<mm:ss.xx>` word
stamps and is used directly when present, but almost no source provides it, so `LRCParser`
otherwise spreads each line across the gap to the next one in proportion to word length.
That estimate is what makes the highlight work on ordinary LRC, which is everything LRCLIB
returns.

## Current state

Everything below is built, compiles with no warnings, and runs. What is *not* verified is
called out explicitly, because several things here can only be checked on a signed build.

**Working and checked by eye or by tooling**

- Notch surface: closed pill matching the hardware cutout, expanded panel with a top strip
  either side of the cutout, one-spring open and close, multi-display targeting
- Now Playing: Apple Music and Spotify via Apple Events, MediaRemote fallback, artwork with
  retry, scrubber with seek, word-level lyrics from LRCLIB with duration matching
- Calendar and Reminders: grid, upcoming list, per-calendar visibility, quick add, tick-off
- Battery, Bluetooth accessory charge, CPU/GPU/memory/network stats
- Shelf: drop, bookmark persistence, drag out with a real copy or move operation
- HUDs for volume, brightness, keyboard backlight, with optional suppression of Apple's
- Ambient glow: five styles, closed and open placements, live preview, style cycling from the notch
- Link shelf: saved web links with titles and icons, open, copy, capped and persisted
- Calendar navigation: arrows by week or month, a picked day listing that day, Quick Add onto it
- Now Playing: three card styles, repeat and favourite with their state read back, the playing
  app's icon on the artwork, and a full scrolling lyrics list that seeks when a line is clicked
- Live activities beyond the timer: downloads (`--check-downloads`) and a device's charge when
  it connects, with a swipe up to put either away
- System stats with a minute of history behind each reading
- Settings: twelve panes, searchable, every persisted setting read by something. Layout is
  the newest: the closed pill, the widgets, the top bar and the transport row, each arranged on
  a miniature of the surface it belongs to
- Floating Now Playing window, toggled from Settings or the pop-out button on the media card
- Global shortcuts, launch at login, gestures, haptics

**Built but never exercised against reality**

Everything here builds and passes whatever tooling can reach it. None of it has been used by
hand, and each one is a place to look first when something is reported.

- The drag and drop in Settings > Layout. The editors were rendered with `--capture-layout`,
  which deliberately draws them *without* their drag sources and drop targets.
- The calendar against a real calendar. Only the sample events have been through it, because
  the Debug build has no Calendar grant.
- Repeat, favourite, the lyrics list and the artwork bars with a player actually running. The
  scripts compile and the shaping is checked headlessly; nothing has been pressed.
- A real download, and a device connecting. `--check-downloads` plays both halves of a download
  out in a scratch folder, which is not the same as the folder macOS gates behind a permission.
- VLC, which is not installed here, so its script has never been compiled against its own
  dictionary.
- How the glow looks driven by real audio. The tap delivers signal (`--check-audio`), so the
  FFT, banding and onset detection have run against it, but nobody has watched the effect
  itself with audio-reactive on rather than the fallback.
- Multi-display targeting beyond one screen. All three modes are written; only the built-in
  display has ever been used.
- Sandboxed behaviour. Everything so far assumes unsandboxed.
- From the 0.3 feedback batch (2026-09-23): the rewritten drag and drop in Settings > Layout
  (built and reasoned through, never dragged), the closed lyrics strip against a real song, and
  the tutorial's Allow Now for system audio and Accessibility.

**Known to be missing**

A test target. See `WORKPLAN.md`.

## Working with this user

- They test on the real app and report what they see, often in screenshots. Take those
  seriously: several rounds of "it still looks wrong" turned out to be four separate genuine
  bugs in the same effect, not one misunderstanding.
- Verify before claiming a fix. `--capture-notch` and the check tools exist because eyeballing
  a preview gave the wrong answer twice.
- When something cannot be done, say so plainly and say why, rather than shipping a control
  that does nothing. That principle is load-bearing here; see "No setting may be inert".
