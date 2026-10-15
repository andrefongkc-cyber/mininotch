#if DEBUG
import AppKit

/// Checks Focus Timer: switching to another app restarts the interval, switching back to the one
/// it started in, or to MiniNotch, does not, and nothing restarts once it is let go.
///
/// Run with `MiniNotch --check-focus`. App switches are posted as the workspace notifications
/// macOS sends, naming apps that are running (Finder, the Dock), so nothing on screen changes.
@MainActor
enum DebugFocusCheck {
    static let flag = "--check-focus"

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains(flag) else { return false }
        var failures = 0
        func check(_ passed: Bool, _ what: String) {
            print((passed ? "ok   " : "FAIL ") + what)
            if !passed { failures += 1 }
        }
        func app(_ id: String) -> NSRunningApplication? {
            NSRunningApplication.runningApplications(withBundleIdentifier: id).first
        }
        func switchTo(_ app: NSRunningApplication?) {
            guard let app else { return }
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.didActivateApplicationNotification, object: NSWorkspace.shared,
                userInfo: [NSWorkspace.applicationUserInfoKey: app])
        }
        func wait(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

        guard let finder = app("com.apple.finder"), let dock = app("com.apple.dock") else {
            print("FAIL Finder and the Dock must be running"); exit(1)
        }
        let timer = TimerService()
        let focus = FocusGuard()
        focus.onLeave = { timer.restartInterval() }

        switchTo(finder)
        timer.startCountdown(minutes: 1)
        focus.arm()
        check(focus.focusAppName == finder.localizedName, "holds the interval to the app that was in front (\(focus.focusAppName ?? "none"))")

        wait(1.2)
        let before = timer.remaining
        switchTo(finder)
        check(timer.remaining <= before, "coming back to that app restarts nothing (\(Int(timer.remaining)) s left)")
        // The running MiniNotch, which shares this tool's bundle identifier; with none running,
        // this tool's own entry.
        let me = app(Bundle.main.bundleIdentifier ?? "") ?? .current
        check(FocusGuard.isSelf(me), "MiniNotch knows itself (\(me.bundleIdentifier ?? "no bundle"))")
        switchTo(me)
        check(timer.remaining <= before, "MiniNotch itself coming forward restarts nothing")

        switchTo(dock)
        check(timer.remaining > 59.5, "switching to another app starts the interval over (\(String(format: "%.1f", timer.remaining)) s left)")
        check(focus.restarts == 1 && focus.lastLeftTo == dock.localizedName, "and says where the user went (\(focus.lastLeftTo ?? "nowhere"))")
        check(focus.focusAppName == finder.localizedName, "still holding the interval to the first app")

        wait(1.2)
        focus.disarm()
        let paused = timer.remaining
        switchTo(dock)
        check(timer.remaining <= paused, "let go (a pause or a break), switching restarts nothing")

        focus.clear()
        check(focus.focusAppName == nil && focus.restarts == 0, "stopping the timer forgets the app")

        print(failures == 0 ? "\nall passed" : "\n\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
#endif
