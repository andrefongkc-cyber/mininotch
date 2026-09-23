import AppKit

/// Application lifecycle.
///
/// Kept deliberately thin: it owns `AppEnvironment` and forwards launch and terminate, and
/// nothing else. Everything that could need testing lives in the environment or a service.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // An accessory app has no Dock icon and no menu bar of its own, which is what makes
        // the notch feel like part of the system rather than a running application.
        NSApp.setActivationPolicy(.accessory)
        environment.start()
        AppLog.app.info("MinNotch started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.stop()
    }

    /// Clicking the app in Finder while it is already running opens Settings, since there
    /// is no window to bring forward.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        environment.openSettings()
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
