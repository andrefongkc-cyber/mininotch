import AppKit
import Carbon.HIToolbox

/// Compiles and runs AppleScript against the media players.
///
/// `NSAppleScript` is not thread-safe and an Apple Event round trip can take a hundred
/// milliseconds, so everything runs on one dedicated serial queue and never on the main
/// thread. Scripts are compiled once and cached, because compilation dominates the cost.
///
/// Nothing here ever launches an application: callers check `isRunning(bundleIdentifier:)`
/// first, otherwise merely reading the now playing track would start Music.
///
/// Unchecked `Sendable` because the confinement is enforced at run time instead: `run` checks
/// it is on `queue`, and the cache is only touched from there.
final class AppleScriptRunner: @unchecked Sendable {
    static let shared = AppleScriptRunner()

    /// Serial so two snapshots can never interleave inside `NSAppleScript`.
    let queue = DispatchQueue(label: "com.minnotch.applescript", qos: .userInitiated)

    private var cache: [String: NSAppleScript] = [:]
    /// Set once the user has denied Apple Events, so we stop re-prompting on every poll.
    private(set) var isAuthorizationDenied = false

    private init() {}

    static func isRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    /// Runs `source` and returns the result descriptor, or nil on any failure.
    ///
    /// Must be called on `queue`.
    @discardableResult
    func run(_ source: String) -> NSAppleEventDescriptor? {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !isAuthorizationDenied else { return nil }

        let script: NSAppleScript
        if let cached = cache[source] {
            script = cached
        } else {
            guard let compiled = NSAppleScript(source: source) else { return nil }
            cache[source] = compiled
            script = compiled
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)

        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            // -1743 is "not authorised to send Apple events"; -600 is "app isn't running".
            if code == -1743 {
                isAuthorizationDenied = true
                AppLog.media.error("Apple Events permission denied; media control is unavailable")
            } else if code != -600 {
                AppLog.media.debug("AppleScript error \(code, privacy: .public)")
            }
            return nil
        }

        return result
    }

    /// Convenience for scripts that return a single delimited string.
    func runReturningString(_ source: String) -> String? {
        run(source)?.stringValue
    }

    /// Re-arms after the user grants permission in System Settings.
    func resetAuthorizationState() {
        isAuthorizationDenied = false
    }
}
