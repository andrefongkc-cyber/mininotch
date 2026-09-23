import AppKit
import SwiftUI

/// Hosts the Settings window.
///
/// A plain `NSWindow` rather than SwiftUI's `Settings` scene: this is an accessory app with
/// no menu bar of its own, so the scene's ⌘, plumbing does not apply, and the window has to
/// be brought forward explicitly because an accessory app is never the active app until it
/// asks to be.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private unowned let environment: AppEnvironment
    private var window: NSWindow?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func show() {
        if window == nil { window = makeWindow() }
        guard let window else { return }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.center()
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsRootView()
            .environment(environment)
            .environment(environment.settings)
            .frame(
                minWidth: Metrics.settingsWindowMinWidth,
                minHeight: Metrics.settingsWindowMinHeight
            )

        let window = NSWindow(
            contentRect: CGRect(
                x: 0,
                y: 0,
                width: Metrics.settingsWindowMinWidth,
                height: Metrics.settingsWindowMinHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "MinNotch Settings"
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: root)
        window.setContentSize(
            CGSize(width: Metrics.settingsWindowMinWidth, height: Metrics.settingsWindowMinHeight)
        )
        return window
    }

    /// Write any debounced settings change immediately, so closing the window and quitting
    /// straight after cannot lose the last edit.
    func windowWillClose(_ notification: Notification) {
        environment.settings.flush()
    }
}
