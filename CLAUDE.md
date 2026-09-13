# MinNotch — working notes for Claude

A macOS menu-bar/notch utility. A borderless panel overlays the notch area: closed it is a
thin black pill, hovering or clicking expands it into a panel of widgets. Comparable to
NotchNook, Alcove, and TheBoringNotch.

Read this file first in a new session, then `WORKPLAN.md` for what to build next.

## Start here

The app builds clean, runs, and is feature-complete for everything in `WORKPLAN.md` marked
`[x]`. About 12,700 lines across 96 Swift files. One thing blocks progress on several fronts
at once:

**There is no code signing identity on this machine.** The app is ad-hoc signed, which means
every rebuild is a different app to macOS. Consequences, in order of how much they hurt:

1. The system audio permission cannot be granted at all, so the audio-reactive ambient glow
   is permanently on its fallback animation and its FFT has never seen real signal.
2. Calendar, Reminders, Automation, and screen recording grants reset on every build. Use
   `Scripts/run.sh --no-build` to relaunch without losing them.
3. Nothing can be notarised or distributed.

The fix is the user signing in to Xcode with any Apple ID, including a free one, then setting
`DEVELOPMENT_TEAM` and `CODE_SIGN_STYLE = Automatic` in `project.pbxproj`. Ask before
assuming it has been done; check with `security find-identity -v -p codesigning`.

## Build, run, review

```bash
Scripts/build.sh          # build Debug, print only warnings/errors
Scripts/run.sh            # build, kill any running copy, relaunch
Scripts/preview.sh        # render notch views to PNGs in Previews/
```

Six debug-only command line flags on the binary itself, all `#if DEBUG`:

```bash
MinNotch --render-previews <dir>                                  # what preview.sh calls
MinNotch --capture-notch out.png [--collapsed] [--tab system] [--glow bars|off] [--debug]
                                 [--hold 12] [--midway 0.14] [--extended] [--virtual]
                                 [--timer 12]
MinNotch --check-lyrics "Khalid" "8TEEN" 229                      # LRCLIBClient + LRCParser
MinNotch --check-stats 5                                          # CPU/GPU/memory/network
MinNotch --check-audio 8 [--out f]                                # Core Audio tap
MinNotch --check-glow 2 [--source step|fallback]                  # glow shaping chain
MinNotch --check-settings file.minnotch                           # import bounds
MinNotch --check-permissions [--request] [--out f]                # TCC state
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
    Timer/        countdown and the Pomodoro cycle on top of it
    HUD/          volume, brightness and keyboard backlight monitors
    AmbientGlow/  glow styles, geometry, and the Core Audio tap
    Onboarding/   first-launch hook (not built)
  UI/
    Notch/        the notch surface and its widgets
    Settings/     the Settings window, sidebar, and one file per pane
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
  `extendPillForIndicators || !geometry.hasPhysicalNotch`.
- **The pill's leading flank composes, it does not choose.** Artwork and a Live Activity are
  drawn side by side. They used to be a chain of else-ifs with artwork first, which meant a
  running timer was invisible for as long as anything was playing, which is precisely when
  you most want to see how long is left. If two things are both worth knowing, the flank has
  room for both, and `leadingContentWidth` adds them up in the same order and with the same
  spacings the view uses.
- **What the pill and the top strip show is arranged, not assigned.** `SlotLayoutEditor` is
  one drag-to-arrange component used three times: the media transport row, the two flanks of
  the closed pill, and the open panel's trailing top strip. Two things are deliberately not
  destinations, and both are load-bearing. The dead zone over the camera housing is a
  `Spacer` with nothing in it, which is the only reason clicks there fall through to the
  desktop. And the tab strip keeps the leading side of the top strip, because its position is
  what aligns it to the left of the cutout. Adding either to a layout would break something
  that currently works by construction.
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
- **`GeometryReader` reports where the layout is going, not where it is.** During an animated
  frame change the view's frame interpolates and the reader's `proxy.size` does not: it hands
  back the destination immediately. That is why the ambient glow snaps to the fully open
  outline while the black fill is still growing. Measured off the real panel with
  `--capture-notch --midway`: 140 ms into a 520 ms spring the fill was 670 points wide and the
  glow was already drawing 1170. Moving the reader outside the `TimelineView`, removing
  `drawingGroup()`, and pausing the timeline for the length of the transition all failed,
  because none of them is the cause. Anything that must follow an animating size has to carry
  that size in a `Shape`'s `animatableData`, which is the one mechanism here that does
  interpolate, and is already how `NotchShape` animates its corners. **This is still open.**
- **A URL that came from somewhere else is not a URL you may fetch.** The artwork URL arrives
  as a string from whatever media player is running, over Apple Events. It was read with
  `Data(contentsOf:)`, which accepts any scheme the string happens to parse as: a reply of
  `file:///…` would have had an unsandboxed app read that path off disk and try to decode it
  as an image. Transport security does not help, because it ignores `file:` entirely. It also
  had no timeout and no size limit, on the serial queue every media read shares. Every
  outbound request now goes through `BoundedHTTPClient`, which requires HTTPS and a host,
  caps the body while it arrives rather than after, refuses redirects off the original host,
  and times out. Do not add a bare `URLSession` or a `Data(contentsOf:)` beside it.
- **Anything animating over the notch re-renders the whole surface, every display frame.**
  That cost is about one core, and it is close to fixed: measured on the real panel it did
  not move for a frame cap of 15, 30, or 60, for one glow segment against sixteen, for a
  pill-sized layer against a panel-sized one, or with the blur and `drawingGroup()` switched
  off entirely. The media card's own visualizer does the same thing with the glow disabled,
  and a static tab with no animation costs zero. So do not reach for a frame cap or a cheaper
  effect to fix it, because neither touches it. The fix, when someone takes it on, is to stop
  an animating overlay invalidating the entire hosting view. Until then, assume the panel
  costs a core whenever anything on it moves, which is also why the sampling services are
  reference counted to the views that show them.
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
- **The notch panel is always black in both appearances.** Never use a semantic label colour
  (`Palette.primaryText`, `.labelColor`) for content drawn on it: it disappears in light
  mode. Use explicit `.white` with opacity. `Palette` is for the Settings window.
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
- **Swift 5 language mode**, `SWIFT_STRICT_CONCURRENCY = minimal`. Migrating to Swift 6 is a
  planned task, not a drive-by change.

## Permissions and TCC

Four things about permissions on this project will waste an hour if you do not know them.

**`INFOPLIST_KEY_*` silently drops keys Xcode does not recognise.** `NSAudioCaptureUsageDescription`
is one of them. A missing usage description means the permission prompt never fires at all,
which is indistinguishable from the permission being refused. The project therefore uses a
real `Config/Info.plist` rather than `GENERATE_INFOPLIST_FILE`; add new usage descriptions
there and verify with `PlistBuddy` against the built app, not the build settings.

**Every build voids every granted permission.** There is no signing identity on this machine,
so the app is ad-hoc signed, and an ad-hoc signature is a hash of the binary. TCC keys its
grants on that, so each rebuild is a different app as far as macOS is concerned and Calendar
access resets to `notDetermined`. Use `Scripts/run.sh --no-build` to relaunch without
rebuilding when you want to keep access. The permanent fix is a stable identity: signing in to
Xcode with any Apple ID, including a free one, issues an Apple Development certificate, and
setting `DEVELOPMENT_TEAM` and `CODE_SIGN_STYLE = Automatic` then makes grants persist.

**A prompt is only shown to a frontmost app.** MinNotch is an accessory app with no Dock icon,
and the notch panel is non-activating precisely so it never steals focus, so it is never the
active app. `CalendarService.requestAccess()` therefore switches to a regular activation
policy and activates before asking, restoring the policy when the user answers or after a
timeout. Without that the request resolves with no dialog and the status stays
`notDetermined`, which is indistinguishable from a user dismissing a dialog they never saw.

**The system audio permission cannot be granted to this build at all.** macOS will not raise
the system audio recording prompt for an ad-hoc signed app, so `AudioHardwareCreateProcessTap`
simply never returns. `AudioAnalyzer.start()` therefore does its Core Audio work off the main
thread with an eight second timeout: called inline it froze the entire interface. Everything
the tap feeds has a working non-audio fallback, so the app is fully usable without it, and a
real signing identity is what unblocks it.

**Never test permissions by running the binary directly.** A process started from a shell has
the terminal as its responsible process, so TCC judges the request against the terminal and
reports a different status than the real app sees. `--check-permissions` run from a shell will
say `notDetermined` even when the app has full access. Always launch through LaunchServices:

```bash
open -n -a <path to MinNotch.app> --args --check-permissions --out /tmp/perm.log
```

## Permissions this app asks for

| What | API | When |
|---|---|---|
| Calendar | EventKit `requestFullAccessToEvents` | First time the Calendar widget or pane is used |
| Network (lyrics) | `URLSession` to lrclib.net | Only when Settings > Media > Lyrics Source is set to Look Up Online |
| Automation (Music, Spotify) | Apple Events | First media read |
| Notifications | `UNUserNotificationCenter` | First low-battery alert |

None are requested at launch. `OnboardingCoordinator` is the hook for explaining them first;
it is called from `AppEnvironment.start()` and currently does nothing but mark itself done.

## No setting may be inert

Every persisted setting must be read by something. A control that saves a value and changes
nothing is worse than a missing feature, because it tells the user a lie they cannot detect.
Audit it with a script that lists each property in `Core/Settings/Sections` and greps the rest
of the tree for readers, excluding the section's own file and its pane. The expected result is
three false positives: `accentMode` and `customAccent`, read through `resolvedAccent`, and
`ShortcutSettings.bindings`, read through `combo(for:)`. All three are read by an accessor in
their own section's file, which is what the grep cannot see.

If a feature genuinely cannot be built, delete its setting rather than badging it forever.
`showOnLockScreen` was removed for this reason: macOS composites no third-party window on the
lock screen and offers no widget surface there, unlike iOS.

## How the trickier features behave

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

**The fallback runs through the same chain as real audio, and that is not a nicety.** The
system audio permission cannot be granted to an ad-hoc signed build at all, so on this
machine the fallback is the only thing that ever drives the glow and the whole effect is
judged on it. `GlowFallbackSource` therefore emits impulses rather than curves, because the
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
from style: the same style draws against the notch outline, the album artwork's rounded
square, or both, and only the placement currently on screen is rendered.

**Lyric timing is only as good as its timestamp.** `NowPlayingController` stamps the
capture time on the queue that read the player, not on main after the hop. An Apple Event
round trip is a hundred milliseconds or more, and timestamping on arrival makes every later
extrapolation that much late, which shows up as the lyric highlight trailing the vocal.
`lyricsTime(at:)` adds the user's offset on top and is separate from `elapsed(at:)` so the
correction never moves the scrubber.

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

**The timer counts against a deadline, not down from a number.** A tick that is late, and
every timer tick is late sometimes, would otherwise lose that time for good and a
twenty-five minute Pomodoro would quietly run long by however busy the machine was. The tick
only decides when to redraw. Pomodoro is a preset on the countdown rather than a system
beside it: the only thing that makes an interval a Pomodoro is what happens when it ends, so
`TimerPhase` decides whether anything follows and the timer stays one thing.

**Sampling is reference counted to the view that shows it.** `SystemStatsService`,
`BluetoothBatteryService`, and the HUD's brightness polling all start on `onAppear` and stop
on `onDisappear`, because a menu bar utility that wakes every couple of seconds forever is a
battery complaint waiting to happen. Volume is the exception: CoreAudio pushes changes, so it
costs nothing to leave attached.

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
- Ambient glow: five styles, three placements, live preview, style cycling from the notch
- Settings: ten panes, every persisted setting read by something
- Global shortcuts, launch at login, gestures, haptics

**Built but never exercised against reality**

- The Core Audio tap's FFT, banding, and onset detection. The tap starts and buffers arrive,
  but they are silent because the permission cannot be granted to an ad-hoc build.
- Multi-display targeting beyond one screen. All three modes are written; only the built-in
  display has ever been used.
- Sandboxed behaviour. Everything so far assumes unsandboxed.

**Known to be missing**

App icon, onboarding flow, and any test target. See `WORKPLAN.md`.

## Working with this user

- They test on the real app and report what they see, often in screenshots. Take those
  seriously: several rounds of "it still looks wrong" turned out to be four separate genuine
  bugs in the same effect, not one misunderstanding.
- Verify before claiming a fix. `--capture-notch` and the check tools exist because eyeballing
  a preview gave the wrong answer twice.
- When something cannot be done, say so plainly and say why, rather than shipping a control
  that does nothing. That principle is load-bearing here; see "No setting may be inert".
