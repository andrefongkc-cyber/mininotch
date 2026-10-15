import AppKit
import SwiftUI

/// The Timer tab in a small window of its own, above other apps, from the tab's pop-out button.
/// Built like `FloatingNowPlayingController`: non-activating, movable by its background, its
/// place remembered by AppKit.
@MainActor
final class FloatingTimerController {
    private var panel: NSPanel?
    private let environment: AppEnvironment
    private static let frameAutosaveName = "MiniNotchFloatingTimer"
    private static let size = CGSize(width: 600, height: TimerWidgetView.preferredHeight + 44)

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// Opens or closes the window to match `Stopwatch.isPoppedOut`.
    func sync() {
        environment.stopwatch.isPoppedOut ? show() : hide()
    }

    private func show() {
        if let panel { panel.orderFrontRegardless(); return }
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.size),
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let theme = environment.notchStyle()
        let root = FloatingTimerView(onClose: { [weak self] in
            self?.environment.stopwatch.isPoppedOut = false
            self?.sync()
        })
        .environment(\.notchStyle, theme)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
        .environment(environment)
        .environment(environment.settings)

        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: Self.size)
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        panel.contentView = hosting
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        if panel.frame.origin == .zero { panel.center() }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    #if DEBUG
    /// The window's content, for `--capture-notch --floating-timer`.
    var debugContentView: NSView? { panel?.contentView }
    #endif

    private func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct FloatingTimerView: View {
    @Environment(\.notchStyle) private var theme
    let onClose: () -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.ink.opacity(0.7))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(theme.ink.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1 : 0)
                .help("Put the timer back in the notch")
                Spacer()
            }
            TimerWidgetView(viewModel: nil, isFloating: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            NotchSurfaceView(style: theme.surface, isTranslucent: false,
                             edge: RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onHover { isHovering = $0 }
    }
}
