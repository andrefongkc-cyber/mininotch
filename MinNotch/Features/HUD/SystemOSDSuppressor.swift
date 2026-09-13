import Foundation

/// Hides macOS's own volume and brightness overlay so MinNotch's is the only one on screen.
///
/// There is no supported way to do this. The overlay is drawn by `OSDUIHelper`, a per-user
/// launch agent, and the clean approach of unloading that agent is refused by System
/// Integrity Protection:
///
///     Boot-out failed: 150: Operation not permitted while System Integrity Protection is engaged
///
/// What is left is terminating the process. It is owned by the current user, launchd starts
/// it again on demand, and nothing persists past the next overlay, so this is reversible and
/// self-healing rather than a configuration change. The cost is that the overlay can flicker
/// into view before it goes, because the process has to exist before it can be killed.
///
/// Off by default, and never done silently: killing a system process is the user's call.
enum SystemOSDSuppressor {
    /// Terminates the overlay helper if it is running.
    ///
    /// Fired several times over a short window because the helper is spawned on demand, and
    /// the spawn races the key press that triggered it. One shot frequently arrives before
    /// the process exists.
    static func suppress() {
        kill()
        for delay in [0.08, 0.18, 0.35] {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
                kill()
            }
        }
    }

    private static func kill() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        // Exact match, so nothing else that happens to contain the name is caught.
        process.arguments = ["-x", "OSDUIHelper"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            AppLog.app.error("Could not run pkill for the system overlay: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// False in a sandboxed build, where launching a helper process is not permitted.
    ///
    /// Checked rather than assumed so the App Store build can disable the setting instead of
    /// silently doing nothing.
    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/pkill")
    }
}
