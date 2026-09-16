#if DEBUG
import AppKit
import SwiftUI

/// Captures the notch as AppKit actually renders it, rather than as `ImageRenderer` draws it.
///
/// Run with `MinNotch --capture-notch <file.png>`. `ImageRenderer` flattens a SwiftUI view
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
        environment.calendarService.start(settings: settings)

        // Effects are off by default, so a capture would not show them otherwise.
        settings.media.showVisualizer = true
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
        // Which states the glow shows in: `closed`, `open`, or `closed,open`. The glow behaves
        // differently when it is on for only one of them, so both cases have to be capturable.
        if let index = arguments.firstIndex(of: "--placements"), arguments.indices.contains(index + 1) {
            let names = arguments[index + 1].split(separator: ",").map(String.init)
            var placements = Set<AmbientGlowPlacement>()
            if names.contains("closed") { placements.insert(.collapsedNotch) }
            if names.contains("open") { placements.insert(.expandedPanel) }
            settings.appearance.ambientGlow.placements = placements
        }
        // `--debug` also turns on the outline and the glow's level readout, which is the
        // only way to review the tuning overlay without changing the real configuration.
        settings.advanced.showDebugOverlay = arguments.contains("--debug")

        guard let screen = NSScreen.main else {
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
        // The track-change drop below the pill. Held for longer than the real one, so the
        // capture lands while it is still out.
        if arguments.contains("--peek") { viewModel.peek(for: 60) }

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
        if let midway {
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
#endif
