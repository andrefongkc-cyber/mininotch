import AppKit
import Observation

/// Settings > Tabs > Timer > Focus Timer: while a countdown, a Pomodoro focus interval or the
/// stopwatch runs, switching to any app but the one it started in starts it over (`onLeave`).
///
/// It watches `didActivateApplicationNotification`, which needs no permission. MiniNotch itself
/// never counts: the notch and the timer window do not activate it, and typing a custom length
/// does, so the app watched is the last other one in front (`lastOtherApp`), not this one.
@MainActor
@Observable
final class FocusGuard {
    /// The app the interval has to stay in, while armed.
    private(set) var focusAppName: String?
    @ObservationIgnored private var focusBundleID: String?
    /// Where the user went the last time it restarted, for the timer to say so.
    private(set) var lastLeftTo: String?
    private(set) var restarts = 0
    private(set) var isArmed = false

    /// Whether this timer has already popped the window out, so closing it is not undone on resume.
    @ObservationIgnored var hasPoppedOut = false
    @ObservationIgnored var onLeave: (() -> Void)?
    @ObservationIgnored private var lastOther: (bundleID: String, name: String)?
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        if let front = NSWorkspace.shared.frontmostApplication, !Self.isSelf(front) {
            lastOther = (front.bundleIdentifier ?? "", front.localizedName ?? "")
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.activated(app) }
        }
    }

    /// Starts watching, keeping the app from before if this interval already had one.
    func arm() {
        guard !isArmed else { return }
        isArmed = true
        if focusBundleID == nil {
            focusBundleID = lastOther?.bundleID
            focusAppName = lastOther?.name
        }
    }

    /// Stops watching for now, as while paused or on a break; the app is kept.
    func disarm() {
        isArmed = false
    }

    /// Forgets everything, when the timer stops.
    func clear() {
        isArmed = false
        focusBundleID = nil
        focusAppName = nil
        lastLeftTo = nil
        restarts = 0
        hasPoppedOut = false
    }

    private func activated(_ app: NSRunningApplication?) {
        guard let app, !Self.isSelf(app) else { return }
        let id = app.bundleIdentifier ?? ""
        lastOther = (id, app.localizedName ?? "")
        guard isArmed, let focusBundleID, id != focusBundleID else { return }
        lastLeftTo = app.localizedName
        restarts += 1
        onLeave?()
    }

    /// By process, or by bundle identifier: a process that has not checked in with LaunchServices
    /// (a debug tool run from a shell) gets no process identifier for itself.
    static func isSelf(_ app: NSRunningApplication) -> Bool {
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return true }
        guard let id = app.bundleIdentifier else { return false }
        return id == Bundle.main.bundleIdentifier
    }
}
