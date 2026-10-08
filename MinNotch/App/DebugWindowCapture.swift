#if DEBUG
import AppKit
import SwiftUI

/// Captures the notch as AppKit actually renders it, rather than as `ImageRenderer` draws it.
///
/// Run with `MiniNotch --capture-notch <file.png>`. `ImageRenderer` flattens a SwiftUI view
/// into one drawing context, which hides anything caused by separate layers being composited
/// against a transparent window: edge seams, halos, and stray fills all disappear in an
/// offscreen render and are plainly visible on screen. This builds the real `NotchPanel` with
/// a real `NSHostingView` and reads its backing store back, so the pixels are the ones the
/// window server would show.
///
/// Transparent areas come back with zero alpha, which makes the check easy: any pixel with
/// alpha that is not near-black is something drawn that should not be.
@MainActor
enum DebugWindowCapture {
    static let flag = "--capture-notch"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return false }

        let path = arguments.indices.contains(index + 1)
            ? arguments[index + 1]
            : NSTemporaryDirectory() + "notch-capture.png"
        let expanded = !arguments.contains("--collapsed")

        var tab = NotchTab.media
        if let tabIndex = arguments.firstIndex(of: "--tab"),
           arguments.indices.contains(tabIndex + 1),
           let parsed = NotchTab(rawValue: arguments[tabIndex + 1]) {
            tab = parsed
        }

        capture(to: path, expanded: expanded, tab: tab)
        return true
    }

    private static func capture(to path: String, expanded: Bool, tab: NotchTab) {
        let arguments = CommandLine.arguments
        let environment = DebugSupport.makeEnvironment()
        let settings = environment.settings
        environment.battery.applySampleStatus()
        environment.nowPlaying.applySample(settings: settings)

        // The calendar reads real data rather than a sample, so its service has to be
        // started or it reports its default not-determined state and the capture shows the
        // permission prompt no matter what access the app actually has.
        // `--sample-calendar` uses fixed sample events instead, which needs no permission.
        if arguments.contains("--sample-calendar") {
            environment.calendarService.applySampleItems(settings: settings)
            // The sample standup is four minutes away, so this puts its countdown in the pill
            // through the same path the real clock does.
            environment.syncMeetingActivity()
        } else {
            environment.calendarService.start(settings: settings)
        }
        if let index = arguments.firstIndex(of: "--calendar-step"), arguments.indices.contains(index + 1) {
            CalendarWidgetView.debugStep = Int(arguments[index + 1]) ?? 0
        }
        if let index = arguments.firstIndex(of: "--calendar-pick"), arguments.indices.contains(index + 1) {
            CalendarWidgetView.debugPick = Int(arguments[index + 1])
        }

        // Effects are off by default, so a capture would not show them otherwise. `--no-visualizer`
        // and `--no-lyrics` leave each out, for measuring what playing costs piece by piece.
        settings.media.showVisualizer = !arguments.contains("--no-visualizer")
        if arguments.contains("--no-lyrics") { settings.media.showLyrics = false }
        settings.appearance.ambientGlow.isEnabled = true
        // Both widgets are off by default, so their tabs would not exist to capture.
        settings.advanced.clipboardHistoryEnabled = true
        settings.timer.enabled = true
        environment.clipboard.applySample()
        settings.advanced.linkShelfEnabled = true
        environment.linkShelf.applySample()

        // The debug buttons default on in a Debug build, which is what this tool is, but a
        // capture is a picture of the app people run. `--debug` puts them back.
        settings.advanced.showDebugButtons = arguments.contains("--debug")

        // `--controls shuffle,previous,playPause,next,repeatMode,favorite` sets the transport row.
        if let index = arguments.firstIndex(of: "--controls"), arguments.indices.contains(index + 1) {
            settings.media.controlOrder = arguments[index + 1].split(separator: ",").compactMap { MediaControl(rawValue: String($0)) }
        }

        // `--sample-stats` fills the System tab with fixed readings and a history with a spike.
        if arguments.contains("--sample-stats") {
            environment.systemStats.start(settings: settings)
            environment.systemStats.applySampleHistory()
        }

        // `--sample-power` plugs the sample battery into a 60 W charger, with fixed watts.
        if arguments.contains("--sample-power") {
            environment.battery.applySampleCharging(settings: settings)
        }

        // `--lyrics-sheet` opens the full lyrics list instead of the two-line strip.
        if arguments.contains("--lyrics-sheet") {
            environment.nowPlaying.isShowingLyricsSheet = true
        }

        // `--card compact|fullArtwork` picks the Now Playing card style.
        if let index = arguments.firstIndex(of: "--card"), arguments.indices.contains(index + 1),
           let style = NowPlayingCardStyle(rawValue: arguments[index + 1]) {
            settings.media.cardStyle = style
        }

        // Playback paused, which is the state the glow must be completely still in.
        if arguments.contains("--paused") {
            environment.nowPlaying.applySample(settings: settings, isPlaying: false)
        }

        // Squeezes or widens the panel, which is how the top bar's overflow gets reviewed.
        if let index = arguments.firstIndex(of: "--width"),
           arguments.indices.contains(index + 1),
           let width = Double(arguments[index + 1]) {
            settings.appearance.expandedWidth = width
        }
        // Puts the given items on the right of the notch, e.g. `--right timer,settings,battery`.
        if let index = arguments.firstIndex(of: "--right"),
           arguments.indices.contains(index + 1) {
            let right = arguments[index + 1].split(separator: ",").compactMap { TopStripItem(rawValue: String($0)) }
            settings.appearance.topStripLeading.removeAll { right.contains($0) }
            settings.appearance.topStripTrailing = right
        }

        // A running timer, so the pill's activity and the panel's running state can both be
        // captured. Without it the timer is idle and neither is on screen.
        if let index = arguments.firstIndex(of: "--timer"),
           arguments.indices.contains(index + 1),
           let minutes = Double(arguments[index + 1]) {
            environment.timer.start(settings: settings)
            // The same wiring `AppEnvironment.start()` installs, which this tool does not
            // call. Without it the timer runs but never reaches the pill.
            environment.timer.onChange = { [weak environment] in environment?.syncTimerActivity() }
            environment.timer.startCountdown(minutes: minutes)
        }

        if let index = arguments.firstIndex(of: "--glow"),
           arguments.indices.contains(index + 1) {
            let value = arguments[index + 1]
            // `--glow off` is the A/B for performance work: everything else in the panel
            // animates too, so a figure for the glow only means anything next to one
            // measured without it.
            if value == "off" {
                settings.appearance.ambientGlow.isEnabled = false
            } else if let style = AmbientGlowStyleKind(rawValue: value) {
                settings.appearance.ambientGlow.style = style
            }
        }
        settings.media.tintFromArtwork = true
        // The closed pill shows nothing at all unless the indicators are switched on, so a
        // capture of it is blank without this.
        if arguments.contains("--extended") { settings.general.extendPillForIndicators = true }
        // The Now Playing card with its sound output list open, reading this Mac's real outputs.
        if arguments.contains("--output-sheet") {
            settings.media.showOutputButton = true
            environment.audioOutputs.refresh()
            environment.nowPlaying.isShowingOutputSheet = true
        }
        // A fixed forecast, so the Weather tab and the pill's temperature can be captured with
        // no network and no location.
        if arguments.contains("--sample-weather") {
            settings.weather.enabled = true
            environment.weather.applySample()
            // Weather is not in the default pill arrangement, so place it for the capture.
            if !settings.general.pillLeading.contains(.weather), !settings.general.pillTrailing.contains(.weather) {
                settings.general.pillTrailing.insert(.weather, at: 0)
            }
        }
        if arguments.contains("--sample-shelf") {
            settings.shelf.enabled = true
            environment.shelf.applySample()
        }
        // Media > Lyrics > Show Lyrics When Closed, with the sample song's synced lyrics. Set
        // either way, like the shadow, so a capture does not inherit it from the real settings.
        settings.media.showLyricsWhenClosed = arguments.contains("--closed-lyrics")
        if arguments.contains("--closed-lyrics") { settings.media.showLyrics = true }
        // Appearance > Panel Shadow, which is off by default and only exists while open.
        settings.appearance.showPanelShadow = arguments.contains("--shadow")
        // Advanced > Hide Until Hovered, which only changes a virtual notch, so pair it with
        // `--virtual`. Set either way, so a capture does not inherit it from the real settings.
        settings.advanced.hideVirtualNotchUntilHover = arguments.contains("--hide-virtual")
        // Advanced > Clipboard > Blur Until Unlocked, with `--tab clipboard`: the locked list.
        settings.advanced.clipboardBlurUntilUnlocked = arguments.contains("--blur-clipboard")
        // Which states the glow shows in: `closed`, `open`, or `closed,open`. The glow behaves
        // differently when it is on for only one of them, so both cases have to be capturable.
        if let index = arguments.firstIndex(of: "--placements"), arguments.indices.contains(index + 1) {
            let names = arguments[index + 1].split(separator: ",").map(String.init)
            var placements = Set<AmbientGlowPlacement>()
            if names.contains("closed") { placements.insert(.collapsedNotch) }
            if names.contains("open") { placements.insert(.expandedPanel) }
            settings.appearance.ambientGlow.placements = placements
        }
        // `--notch-style bento-light` draws in that Notch Style: a language, a dash, and dark or
        // light. Set either way, so a capture never inherits the real setting; Minimal Dark
        // without it, which is what `Scripts/style-diff.sh` compares.
        DebugSupport.applyNotchStyle(arguments, to: settings)
        // `--debug` also turns on the outline and the glow's level readout, which is the
        // only way to review the tuning overlay without changing the real configuration.
        settings.advanced.showDebugOverlay = arguments.contains("--debug")

        // `--builtin` uses the Mac's own display whichever screen is in front, so a run of captures
        // compared pixel for pixel cannot land on an external monitor halfway through.
        let builtIn = arguments.contains("--builtin") ? NSScreen.screens.first(where: \.isBuiltIn) : nil
        guard let screen = builtIn ?? NSScreen.main else {
            report("No screen"); exit(1)
        }

        var geometry = NotchGeometry.make(for: screen, settings: settings)

        // Stands in for an external monitor. Multi-display is written but has only ever run
        // on the built-in display, and the virtual notch behaves differently from a real one
        // in ways that are meant to be visible: it carries its indicators without the opt-in
        // and it opens on its own tab.
        if arguments.contains("--virtual") {
            geometry = NotchGeometry(
                displayID: geometry.displayID,
                screenFrame: geometry.screenFrame,
                hasPhysicalNotch: false,
                collapsedSize: CGSize(
                    width: settings.advanced.virtualNotchWidth,
                    height: settings.advanced.virtualNotchHeight
                ),
                expandedSize: geometry.expandedSize,
                windowFrame: geometry.windowFrame
            )
        }
        let viewModel = NotchViewModel(settings: settings, geometry: geometry)
        viewModel.selectedTab = tab
        var midway: Double?
        if let i = arguments.firstIndex(of: "--midway"), arguments.indices.contains(i + 1) {
            midway = Double(arguments[i + 1])
        }
        if expanded && midway == nil { viewModel.expand() }
        // `--sample-notes` fills the Notes tab with a fixed note, leaving the real one alone.
        if arguments.contains("--sample-notes") {
            settings.advanced.notesEnabled = true
            environment.notes.applySample()
        }

        // `--no-media` captures with nothing playing, so a side whose indicators are all about the
        // song is empty: the case that slid the pill off the camera housing.
        if arguments.contains("--no-media") {
            settings.media.enabled = false
        }

        // `--hud-style floatingPill|notchInline|progressRing` shows a volume indicator in that style,
        // with `--collapsed`. A long dismiss delay keeps it up until the capture.
        if let index = arguments.firstIndex(of: "--hud-style"), arguments.indices.contains(index + 1),
           let style = HUDStyle(rawValue: arguments[index + 1]) {
            settings.huds.style = style
            settings.huds.dismissDelay = 10
            environment.hud.preview(.volume)
        }
        // `--keep-open` holds the panel open, which puts its pin in the top bar.
        if expanded && midway == nil && arguments.contains("--keep-open") { viewModel.setKeptOpen(true) }
        // The track-change drop below the pill. Held for longer than the real one, so the
        // capture lands while it is still out.
        if arguments.contains("--peek") { viewModel.peek(for: 60) }

        // `--backdrop`: a bright, detailed window behind the notch, so what glass does to what is
        // behind it can be seen whatever the user has open.
        var backdrop: NSWindow?
        if arguments.contains("--backdrop") {
            let window = NSWindow(contentRect: geometry.windowFrame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .floating
            let hosting = NSHostingView(rootView: GlassBackdrop(isDark: arguments.contains("--dark-backdrop")))
            // No sizing from the content: a pattern whose ideal size is small shrank the window to
            // it, and a screenshot meant to show only the pattern showed whatever was behind.
            hosting.sizingOptions = []
            window.contentView = hosting
            window.setFrame(geometry.windowFrame, display: true)
            window.orderFrontRegardless()
            // Printed, so a script can refuse to take a screenshot unless the pattern covers it.
            print("backdrop \(Int(window.frame.minX)) \(Int(window.frame.width)) \(Int(window.frame.height))")
            fflush(stdout)
            backdrop = window
        }
        _ = backdrop
        // `--floating`: the floating Now Playing window too, over the left of the notch's area
        // (and the backdrop, with `--backdrop`), for checking how it draws a Notch Style.
        var floating: FloatingNowPlayingController?
        if arguments.contains("--floating") {
            let controller = FloatingNowPlayingController(environment: environment)
            controller.show()
            controller.debugMove(to: CGPoint(x: geometry.windowFrame.minX + 10, y: geometry.windowFrame.maxY - 380))
            floating = controller
        }
        _ = floating

        let panel = NotchPanel(contentRect: geometry.windowFrame)
        let hosting = NSHostingView(
            rootView: NotchRootView(viewModel: viewModel)
                .environment(environment)
                .environment(settings)
        )
        hosting.frame = CGRect(origin: .zero, size: geometry.windowFrame.size)
        if arguments.contains("--no-sizing") { hosting.sizingOptions = [] }
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        panel.contentView = hosting
        panel.setFrame(geometry.windowFrame, display: true)
        panel.orderFrontRegardless()
        // `--activate` makes the app the active one, as using Settings or typing a note does;
        // `--key` also makes the panel the key window. Liquid Glass and materials can draw
        // differently in each, which a capture taken inactive never shows.
        if arguments.contains("--activate") || arguments.contains("--key") {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        if arguments.contains("--key") { panel.makeKey() }

        // The panel has to be on screen and settled for its backing store to hold anything.
        //
        // `--hold <seconds>` keeps it up for longer, which is how the animated effects get
        // measured: a real panel drawing a real glow is the only place the frame rate, the
        // layout pass, and the compositing cost can be sampled together.
        var hold: TimeInterval = 1.2
        if let index = arguments.firstIndex(of: "--hold"),
           arguments.indices.contains(index + 1),
           let seconds = Double(arguments[index + 1]) {
            hold = seconds
            report("Holding the panel for \(seconds)s before capturing")
        }
        if let i = arguments.firstIndex(of: "--live"), arguments.indices.contains(i + 1) {
            // Opening, reopening or swiping, timed inside a real `NSApplication` run loop. The
            // hand-turned loop the other options use drew Liquid Glass frosted every time, which
            // sent one investigation the wrong way for hours. `--was-active` makes this the active
            // app and hands focus back first, which is what frosts glass in the running app.
            let after = { (seconds: Double, step: @escaping @MainActor () -> Void) in
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { step() } }
            }
            if arguments.contains("--was-active") {
                after(0.1) { NSApplication.shared.activate(ignoringOtherApps: true) }
                after(0.6) { NSApplication.shared.deactivate() }
            }
            switch arguments[i + 1] {
            case "grow":
                after(1.0) { withAnimation(Motion.notch) { viewModel.expand() } }
            case "reopen":
                after(1.2) { withAnimation(Motion.notch) { viewModel.collapse() } }
                after(2.4) { withAnimation(Motion.notch) { viewModel.expand() } }
            case "swipe":
                let target = arguments.firstIndex(of: "--swipe-to").flatMap { arguments.indices.contains($0 + 1) ? NotchTab(rawValue: arguments[$0 + 1]) : nil }
                after(1.2) { viewModel.swipe(to: target ?? .clipboard) }
            default:
                break
            }
            Timer.scheduledTimer(withTimeInterval: hold, repeats: false) { _ in
                MainActor.assumeIsolated { writeCapture(of: hosting, to: path) }
            }
            NSApplication.shared.setActivationPolicy(.accessory)
            NSApplication.shared.run()
        } else if let midway, let i = arguments.firstIndex(of: "--swipe-to"), arguments.indices.contains(i + 1),
           let target = NotchTab(rawValue: arguments[i + 1]) {
            // Settle open on `--tab`, then change tab the way a two-finger swipe does and capture
            // partway: the panel should already be on its way to the new tab's height.
            viewModel.expand()
            RunLoop.main.run(until: Date().addingTimeInterval(1.2))
            viewModel.swipe(to: target)
            RunLoop.main.run(until: Date().addingTimeInterval(midway))
        } else if let midway {
            // Settle collapsed, then expand and capture partway through the spring.
            RunLoop.main.run(until: Date().addingTimeInterval(1.0))
            withAnimation(Motion.notch) { viewModel.expand() }
            RunLoop.main.run(until: Date().addingTimeInterval(midway))
        } else if hold > 2 {
            // A long hold is for sampling CPU, and that has to happen inside a real
            // `NSApplication` run loop. Turning `RunLoop.main` by hand instead makes SwiftUI's
            // animation driver spin: a single ticking label measured 112% of a core that way
            // and 10% under `NSApp.run()`. Every "an animation costs a core" figure this
            // project once recorded came from the hand-turned loop.
            Timer.scheduledTimer(withTimeInterval: hold, repeats: false) { _ in
                MainActor.assumeIsolated {
                    writeCapture(of: hosting, to: path)
                    return
                }
            }
            NSApplication.shared.setActivationPolicy(.accessory)
            NSApplication.shared.run()
        } else {
            RunLoop.main.run(until: Date().addingTimeInterval(hold))
        }

        writeCapture(of: hosting, to: path)
    }

    private static func writeCapture(of hosting: NSView, to path: String) {
        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            report("Could not create a bitmap"); exit(1)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: representation)

        guard let png = representation.representation(using: .png, properties: [:]) else {
            report("Could not encode PNG"); exit(1)
        }
        try? png.write(to: URL(fileURLWithPath: path))

        report("Captured \(representation.pixelsWide)x\(representation.pixelsHigh) to \(path)")
        exit(0)
    }

    private static func report(_ message: String) {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    }
}
/// Stripes of colour under large and small text, behind the notch for `--backdrop`.
private struct GlassBackdrop: View {
    /// `--dark-backdrop`: dark greys with a few lighter shapes, like a dark Settings window, which
    /// is what glass is hardest to see over.
    var isDark = false

    var body: some View {
        if isDark { dark } else { stripes }
    }

    private var dark: some View {
        ZStack(alignment: .topLeading) {
            Color(white: 0.12)
            ForEach(0..<6, id: \.self) { index in
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: 0.2))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(white: 0.3)))
                    .frame(width: 150, height: 70)
                    .offset(x: CGFloat(index % 3) * 170 + 20, y: CGFloat(index / 3) * 90 + 60)
            }
            Text("Settings-like text 0123456789")
                .font(.system(size: 16))
                .foregroundStyle(Color(white: 0.85))
                .offset(x: 30, y: 250)
        }
    }

    private var stripes: some View {
        VStack(spacing: 0) {
            ForEach(0..<12, id: \.self) { row in
                HStack {
                    Text(String(repeating: "Liquid Glass test 0123456789  ", count: 4))
                        .font(.system(size: row.isMultiple(of: 3) ? 22 : 12, weight: .semibold))
                        .foregroundStyle(row.isMultiple(of: 2) ? Color.white : Color.black)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hue: Double(row) / 12, saturation: 0.7, brightness: row.isMultiple(of: 2) ? 0.55 : 0.95))
            }
        }
    }
}
#endif

