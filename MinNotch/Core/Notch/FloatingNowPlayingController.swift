import AppKit
import SwiftUI

/// A small window that floats the Now Playing card above other apps.
///
/// Beside `NotchWindowController`, not a variant of it. The two have almost nothing in
/// common beyond hosting the same card: the notch panel is welded to the top of a display,
/// sized from the hardware cutout, and never resized, while this one is an ordinary movable
/// window the user puts where they like. Forking the notch controller would have meant
/// carrying geometry, hover intent, drag targeting, and multi-display logic that none of
/// this needs.
///
/// It exists for the case the notch cannot serve: an external display with no cutout, where
/// there is nowhere for the notch surface to be.
///
/// Unannotated, like `NotchWindowController` beside it. `AppEnvironment` is not main-actor
/// isolated, and the project is still on Swift 5 with minimal concurrency checking; adding
/// isolation to one leaf here would only fail to compile against the composition root.
@MainActor
final class FloatingNowPlayingController {
    private var panel: NSPanel?
    private let environment: AppEnvironment

    /// Remembered between launches by AppKit, keyed on this name.
    private static let frameAutosaveName = "MinNotchFloatingNowPlaying"

    private static let width: CGFloat = 420
    /// Room above the card for the drag strip and its close button.
    private static let topChrome: CGFloat = 26
    private static let bottomChrome: CGFloat = 12
    /// Transparent room around the card for the glow to spill into (Ambient Lighting > Where It
    /// Shows > Pop-Out Window), always there so the window does not change size when it is
    /// switched on. A blurred layer cannot reach past its own window.
    static let glowRoom: CGFloat = Metrics.notchGlowSpill

    /// Sized from the card itself rather than a constant, so turning lyrics on does not
    /// leave the strip clipped against the bottom of the window.
    private var size: CGSize {
        let card = NowPlayingCardView.preferredHeight(
            style: environment.settings.media.cardStyle,
            showingLyrics: environment.settings.media.showLyrics,
            showingUpNext: environment.nowPlaying.showsUpNext,
            showingLyricsSheet: environment.nowPlaying.showsLyricsSheet,
            showingOutputSheet: environment.nowPlaying.showsOutputSheet,
            outputDeviceCount: environment.audioOutputs.devices.count,
            moduleGap: environment.notchStyle().moduleGap
        )
        return CGSize(width: Self.width + Self.glowRoom * 2,
                      height: card + Self.topChrome + Self.bottomChrome + Self.glowRoom * 2)
    }

    #if DEBUG
    /// Off for the capture tools, which share the real app's defaults and would otherwise move
    /// the user's window.
    var remembersFrame = true

    /// Puts the window at a given place, for `--capture-notch --floating`.
    func debugMove(to origin: CGPoint) {
        panel?.setFrameOrigin(origin)
    }

    /// The window's content, for `--capture-notch --floating`.
    var debugContentView: NSView? { panel?.contentView }
    #endif

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// Opens or closes the window to match the setting. Called from the settings fan-out.
    func settingsChanged() {
        guard environment.settings.media.enabled, environment.settings.media.floatingWindow else {
            hide()
            return
        }
        show()
        resizeToFitCard()
    }

    /// Keeps the height in step with the card when a setting changes what the card contains.
    ///
    /// Anchored at the top left, because an `NSWindow` frame grows upward from its origin
    /// and the window would otherwise appear to jump when the lyric strip is switched on.
    func resizeToFitCard() {
        guard let panel else { return }
        let target = size
        guard abs(panel.frame.height - target.height) > 0.5 else { return }

        var frame = panel.frame
        frame.origin.y += frame.height - target.height
        frame.size = target
        panel.setFrame(frame, display: true, animate: false)
        panel.contentView?.frame = CGRect(origin: .zero, size: target)
    }

    func show() {
        if let panel {
            panel.orderFrontRegardless()
            return
        }

        let initial = size
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: initial),
            // Non-activating for the same reason the notch is: reaching for the transport
            // controls should never pull focus out of whatever the user is typing in.
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = FloatingNowPlayingView(
            onClose: { [weak self] in self?.dismissFromChrome() },
            onLayoutChange: { [weak self] in self?.resizeToFitCard() }
        )
            .environment(environment)
            .environment(environment.settings)

        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: initial)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        panel.contentView = hosting

        // Autosave restores a remembered position; the centre is only the first-run default.
        #if DEBUG
        if remembersFrame { panel.setFrameAutosaveName(Self.frameAutosaveName) }
        #else
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        #endif
        if panel.frame.origin == .zero { panel.center() }
        // A place saved before the glow's margin: move out by the margin, so the card stays
        // where it was left rather than jumping in by it.
        if abs(panel.frame.width - Self.width) < 1 {
            var frame = panel.frame
            frame.origin.x -= Self.glowRoom
            frame.origin.y -= Self.glowRoom
            frame.size = initial
            panel.setFrame(frame, display: false)
        }
        panel.orderFrontRegardless()

        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Closing from the window's own button turns the setting off rather than just hiding.
    ///
    /// Otherwise the setting still reads as on with no window on screen, and the only way
    /// back is to toggle it off and on again.
    private func dismissFromChrome() {
        environment.settings.media.floatingWindow = false
    }
}

/// The floating window's contents: the same card the notch shows, plus a title bar to grab.
///
/// Black in both appearances, like the notch, because it is the same card and that card
/// draws in explicit whites. A semantic background would leave its text invisible in light
/// mode.
private struct FloatingNowPlayingView: View {
    var onClose: () -> Void
    /// Called when something the window's height depends on changes without a settings
    /// change, such as switching from Spotify to Music, which adds the Up Next row.
    var onLayoutChange: () -> Void

    @Environment(AppEnvironment.self) private var environment

    @State private var isHovering = false

    /// A window of its own, away from the camera housing, so always the full Notch Style.
    private var theme: NotchStyle { environment.notchStyle() }
    private static let cornerRadius: CGFloat = 14

    var body: some View {
        card
            .overlay(glow)
            .padding(FloatingNowPlayingController.glowRoom)
    }

    /// Ambient Lighting around the window, while Where It Shows includes the pop-out window.
    /// Overlaid on the clipped card, so the light spills past its edge into the window's
    /// transparent margin, and kept in place while hidden, as the notch's is.
    @ViewBuilder
    private var glow: some View {
        let settings = environment.settings
        let glow = settings.appearance.ambientGlow
        if glow.isActive(isLowPower: environment.battery.status.isLowPowerMode),
           glow.placements.contains(.popOutWindow) {
            AmbientGlowView(
                outline: .roundedRect(cornerRadius: Self.cornerRadius),
                settings: styledGlow(glow),
                palette: environment.nowPlaying.palette,
                isPlaying: environment.nowPlaying.track?.isPlaying ?? false,
                // `isRunning`, never `current`, for the reason in `NotchRootView.ambientGlow`.
                audio: environment.audioAnalyzer.isRunning ? environment.audioAnalyzer : nil,
                tempo: environment.glowTempo(),
                // Only caps the blur; a `GeometryReader` here would align the glow's larger layer
                // top-leading instead of centring it on the card.
                sizeHint: CGSize(width: 420, height: 180),
                spill: min(CGFloat(glow.glowRadius) * 2, FloatingNowPlayingController.glowRoom)
            )
            .allowsHitTesting(false)
        }
    }

    private func styledGlow(_ glow: AmbientGlowSettings) -> AmbientGlowSettings {
        guard theme.glow.intensityScale != 1 else { return glow }
        var styled = glow
        styled.intensity = min(glow.intensity * theme.glow.intensityScale, 1)
        return styled
    }

    private var card: some View {
        NowPlayingCardView()
            .padding(.horizontal, 14)
            .padding(.top, 26)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.notchStyle, theme)
            .environment(\.colorScheme, theme.isDark ? .dark : .light)
            .background(
                NotchSurfaceView(
                    style: theme.surface,
                    isTranslucent: false,
                    edge: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                )
            )
            .overlay(alignment: .topLeading) { closeButton }
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .onHover { isHovering = $0 }
            .onChange(of: environment.nowPlaying.showsUpNext) { onLayoutChange() }
            .onChange(of: environment.nowPlaying.showsOutputSheet) { onLayoutChange() }
            .onChange(of: environment.audioOutputs.devices.count) { onLayoutChange() }
    }

    /// Appears on hover, the way a media window's chrome usually does, so the card is not
    /// permanently sharing its space with a button nobody is reaching for.
    @ViewBuilder
    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(theme.ink.opacity(0.9))
                .frame(width: 14, height: 14)
                .background(Circle().fill(theme.ink.opacity(0.18)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(9)
        .opacity(isHovering ? 1 : 0)
        .animation(Motion.hover, value: isHovering)
        .help("Close. Reopen from Settings > Music.")
        .accessibilityLabel("Close the floating Now Playing window")
    }
}
