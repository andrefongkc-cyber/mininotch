import AppKit
import SwiftUI

/// Sets how much Liquid Glass in this window blurs what is behind it. See CLAUDE.md, "Liquid Glass
/// frosts once the app has ever been active".
///
/// SwiftUI's glass is a backdrop layer with a `glassBackground` filter whose `inputBlurRadius`
/// is 10 at the notch's size, a heavy frost over a desktop seen at half resolution. The user
/// wanted it see-through, and saw it see-through only some of the time: in a process that had
/// never been the active app the blur was not applied, and once anything had activated it
/// (Settings, typing a note, Touch ID, a permission prompt, even locking and unlocking the Mac)
/// every glass in the process frosted until relaunch, new windows included. Glass Opacity now
/// decides the blur instead, every time.
///
/// No API sets it, so this walks the window's layers and sets the filter through Core
/// Animation's `filters.<name>.<key>` key path, after SwiftUI has laid the glass out and again
/// on the next turn of the run loop, since SwiftUI can write the filter after this view's
/// layout. A layer is only touched when it carries a filter by that name with that input, so
/// a macOS that draws glass differently is left alone and shows Apple's frost.
struct GlassClarity: NSViewRepresentable {
    /// Points of blur, in the backdrop's own units.
    var blurRadius: Double

    func makeNSView(context: Context) -> GlassClarityView {
        let view = GlassClarityView()
        view.blurRadius = blurRadius
        return view
    }

    func updateNSView(_ view: GlassClarityView, context: Context) {
        view.blurRadius = blurRadius
        view.apply()
    }
}

final class GlassClarityView: NSView {
    var blurRadius: Double = 10
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observe()
        apply()
    }

    /// Leaving the window removes them (`window` is nil then), and they hold the view weakly.
    ///
    /// SwiftUI writes the filter again when the app or the window changes state, which the
    /// layout above never hears about: the app becoming active (Settings, a note, Touch ID) or
    /// giving it up, the window becoming key or being covered, the Mac waking or unlocking.
    private func observe() {
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        guard let window else { return }
        let local = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let events: [(NotificationCenter, Notification.Name, AnyObject?)] = [
            (local, NSApplication.didBecomeActiveNotification, nil),
            (local, NSApplication.didResignActiveNotification, nil),
            (local, NSWindow.didBecomeKeyNotification, window),
            (local, NSWindow.didResignKeyNotification, window),
            (local, NSWindow.didChangeOcclusionStateNotification, window),
            (local, NSWindow.didChangeScreenNotification, window),
            (workspace, NSWorkspace.screensDidWakeNotification, nil),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification, nil),
            (distributed, Notification.Name("com.apple.screenIsUnlocked"), nil),
        ]
        for (center, name, object) in events {
            let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            }
            observers.append((center, token))
        }
    }

    override func layout() {
        super.layout()
        apply()
    }

    func apply() {
        set()
        DispatchQueue.main.async { [weak self] in self?.set() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.set() }
    }

    private func set() {
        guard let root = window?.contentView?.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        visit(root)
        CATransaction.commit()
    }

    private func visit(_ layer: CALayer) {
        if let filter = layer.filters?.first(where: { ($0 as AnyObject).value(forKey: "name") as? String == "glassBackground" }),
           let inputs = (filter as AnyObject).value(forKey: "inputKeys") as? [String],
           inputs.contains("inputBlurRadius"),
           (layer.value(forKeyPath: "filters.glassBackground.inputBlurRadius") as? Double) != blurRadius {
            layer.setValue(blurRadius, forKeyPath: "filters.glassBackground.inputBlurRadius")
        }
        layer.sublayers?.forEach(visit)
    }
}
