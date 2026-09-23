import AppKit
import SwiftUI

/// Owns one notch surface: its panel, its hosting view, and its view model.
///
/// The panel is created once at the largest size the panel will ever need and never
/// resized. Animating an `NSWindow` frame at sixty frames a second is visibly worse than
/// animating SwiftUI content inside a fixed window, and a stable frame keeps the hover
/// tracking area from being torn down mid-gesture.
@MainActor
final class NotchWindowController {
    let viewModel: NotchViewModel
    private let panel: NotchPanel
    private let environment: AppEnvironment
    private(set) var screen: NSScreen

    init(screen: NSScreen, environment: AppEnvironment) {
        self.screen = screen
        self.environment = environment

        let geometry = NotchGeometry.make(for: screen, settings: environment.settings)
        self.viewModel = NotchViewModel(settings: environment.settings, geometry: geometry)
        self.panel = NotchPanel(contentRect: geometry.windowFrame)

        let root = NotchRootView(viewModel: viewModel)
            .environment(environment)
            .environment(environment.settings)

        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: geometry.windowFrame.size)
        // The hosting view must not paint its own background, or the transparent area
        // around the pill would swallow clicks meant for the desktop behind it.
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        panel.contentView = hosting

        panel.setFrame(geometry.windowFrame, display: false)
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Recomputes geometry after a display change or a settings change that affects size.
    func updateGeometry() {
        let geometry = NotchGeometry.make(for: screen, settings: environment.settings)
        viewModel.update(geometry: geometry)
        panel.setFrame(geometry.windowFrame, display: true)
        panel.contentView?.frame = CGRect(origin: .zero, size: geometry.windowFrame.size)
    }

    /// Moves this surface to a different display, used when the notch follows the pointer.
    func move(to screen: NSScreen) {
        guard NotchGeometry.displayID(of: screen) != NotchGeometry.displayID(of: self.screen) else { return }
        self.screen = screen
        updateGeometry()
    }

    var displayID: CGDirectDisplayID { NotchGeometry.displayID(of: screen) }
}
