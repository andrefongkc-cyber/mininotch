import AppKit

/// The borderless window that hosts the notch surface.
///
/// It is an `NSPanel` with `.nonactivatingPanel` so clicking the notch never steals focus
/// from the app the user is working in, which is the single biggest thing separating a
/// system-feeling overlay from an app window. It joins every Space and stays put during
/// Mission Control so the notch does not slide away with the desktop.
final class NotchPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = NotchPanel.overlayLevel
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true

        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
    }

    /// Just above the menu bar, but below system alerts, so the surface can overlap the
    /// menu bar without covering anything critical.
    static var overlayLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
    }

    /// A borderless panel is not key by default, but the panel has to accept key events for
    /// text fields inside the expanded state (quick add, quick notes) to work later.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
