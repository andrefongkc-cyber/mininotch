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

    /// Sized from the card itself rather than a constant, so turning lyrics on does not
    /// leave the strip clipped against the bottom of the window.
    private var size: CGSize {
        let card = NowPlayingCardView.preferredHeight(
            style: environment.settings.media.cardStyle,
            showingLyrics: environment.settings.media.showLyrics,
            showingUpNext: environment.nowPlaying.showsUpNext,
            showingLyricsSheet: environment.nowPlaying.showsLyricsSheet,
            showingOutputSheet: environment.nowPlaying.showsOutputSheet,
            outputDeviceCount: environment.audioOutputs.devices.count
        )
        return CGSize(width: Self.width, height: card + Self.topChrome + Self.bottomChrome)
    }

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
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        if panel.frame.origin == .zero { panel.center() }
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

    var body: some View {
        NowPlayingCardView()
            .padding(.horizontal, 14)
            .padding(.top, 26)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.black)
            .overlay(alignment: .topLeading) { closeButton }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 14, height: 14)
                .background(Circle().fill(Color.white.opacity(0.18)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(9)
        .opacity(isHovering ? 1 : 0)
        .animation(Motion.hover, value: isHovering)
        .help("Close. Reopen from Settings > Media.")
        .accessibilityLabel("Close the floating Now Playing window")
    }
}
