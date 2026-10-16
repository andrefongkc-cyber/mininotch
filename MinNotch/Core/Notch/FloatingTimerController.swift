import AppKit
import SwiftUI

/// The Timer tab in a small window of its own, above other apps, from the tab's pop-out button.
/// Built like `FloatingNowPlayingController`: non-activating, movable by its background, its
/// place and size remembered by AppKit. It resizes from its edges, and its expand button jumps
/// between the small size and a large one; the time grows to fill either (`BigTime`).
@MainActor
final class FloatingTimerController {
    private var panel: NSPanel?
    private let environment: AppEnvironment
    private static let frameAutosaveName = "MiniNotchFloatingTimer"
    nonisolated static let size = CGSize(width: 600, height: TimerWidgetView.preferredHeight + 44)
    private static let expandedSize = CGSize(width: 760, height: 400)
    /// Narrow enough for a corner of the screen, wide enough for the idle rows at their tightest.
    private static let minimumSize = CGSize(width: 440, height: size.height)

    /// Taller than the small size by more than a nudge counts as expanded, however it got there.
    nonisolated static func isExpanded(height: CGFloat) -> Bool { height > size.height + 30 }

    #if DEBUG
    /// Off for the capture tools, which share the real app's defaults and would otherwise move
    /// the user's window.
    var remembersFrame = true
    #endif

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
            styleMask: [.borderless, .resizable, .nonactivatingPanel, .utilityWindow],
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
        panel.minSize = Self.minimumSize

        let theme = environment.notchStyle()
        let root = FloatingTimerView(
            onClose: { [weak self] in
                self?.environment.stopwatch.isPoppedOut = false
                self?.sync()
            },
            onExpand: { [weak self] in self?.toggleExpanded() }
        )
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
        #if DEBUG
        if remembersFrame { panel.setFrameAutosaveName(Self.frameAutosaveName) }
        #else
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        #endif
        if panel.frame.origin == .zero { panel.center() }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// Small to large or back, keeping the top edge where it is and the middle over the same
    /// spot, and inside the screen.
    func toggleExpanded() {
        guard let panel else { return }
        setExpanded(!Self.isExpanded(height: panel.frame.height))
    }

    func setExpanded(_ expanded: Bool) {
        guard let panel else { return }
        let target = expanded ? Self.expandedSize : Self.size
        var frame = panel.frame
        frame.origin.x += (frame.width - target.width) / 2
        frame.origin.y += frame.height - target.height
        frame.size = target
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        panel.setFrame(frame, display: true, animate: true)
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
    let onExpand: () -> Void
    @State private var isHovering = false
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 6) {
            // Close and expand, top left like a window's own buttons, showing while the pointer
            // is over the window.
            HStack(spacing: 6) {
                windowButton("xmark", help: "Put the timer back in the notch", action: onClose)
                windowButton(
                    isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    help: isExpanded ? "Make the timer small again" : "Make the timer bigger (or drag an edge)",
                    action: onExpand
                )
                Spacer()
            }
            .opacity(isHovering ? 1 : 0)
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
        .onGeometryChange(for: Bool.self) { proxy in
            FloatingTimerController.isExpanded(height: proxy.size.height)
        } action: { isExpanded = $0 }
    }

    private func windowButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(theme.ink.opacity(0.7))
                .frame(width: 16, height: 16)
                .background(Circle().fill(theme.ink.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
