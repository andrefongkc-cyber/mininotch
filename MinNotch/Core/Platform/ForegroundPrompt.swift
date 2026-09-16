import AppKit

/// Brings MinNotch to the front for as long as it takes to ask for a permission.
///
/// macOS only shows a permission dialog to the active app. MinNotch is an accessory app with no
/// Dock icon, and its panel is non-activating precisely so it never steals focus, so it is never
/// the active app: a request made as-is resolves with no dialog ever shown, which is
/// indistinguishable from the user refusing one. `CalendarService.requestAccess` does this inline
/// and was the first thing to need it; the audio tap is the second, and it blocks rather than
/// returning, so it cannot even report a refusal.
///
/// Balanced `begin()` / `end()` calls, counted, so two overlapping requests do not put the Dock
/// icon back while the second is still asking. The policy is also restored on a timer, because a
/// request that never answers would otherwise leave the app with a Dock icon it should not have.
@MainActor
enum ForegroundPrompt {
    private static var depth = 0
    private static var wasAccessory = false
    private static var restoreWork: DispatchWorkItem?

    /// Activates the app. `timeout` is the longest the Dock icon may stay, whatever the caller does.
    static func begin(timeout: TimeInterval = 60) {
        depth += 1
        if depth == 1 {
            wasAccessory = NSApp.activationPolicy() == .accessory
            if wasAccessory { NSApp.setActivationPolicy(.regular) }
        }
        NSApp.activate(ignoringOtherApps: true)

        restoreWork?.cancel()
        let work = DispatchWorkItem { forceRestore() }
        restoreWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    /// Call once per `begin()`, however the request ended.
    static func end() {
        guard depth > 0 else { return }
        depth -= 1
        guard depth == 0 else { return }
        forceRestore()
    }

    private static func forceRestore() {
        restoreWork?.cancel()
        restoreWork = nil
        depth = 0
        guard wasAccessory else { return }
        wasAccessory = false
        NSApp.setActivationPolicy(.accessory)
    }
}
