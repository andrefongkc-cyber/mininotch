#if DEBUG
import Foundation

/// Checks that the System tab's graphs keep their history when the tab is not open.
///
/// Run with `MiniNotch --check-stats-history`. Takes about 25 seconds.
///
/// Plays out what the user does: the tab closed for a while, opened for a few seconds, closed
/// again. The history must grow at the background rate while closed, faster while open, and
/// never start again from nothing when the tab closes, which is what it used to do: sampling
/// stopped with the tab and the graphs were thrown away, so every opening showed a few seconds.
@MainActor
enum DebugStatsHistoryCheck {
    static let flag = "--check-stats-history"

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains(flag) else { return false }

        let environment = DebugSupport.makeEnvironment()
        environment.settings.advanced.showSystemStats = true
        environment.settings.advanced.statsRefreshInterval = 1
        let service = environment.systemStats
        service.start(settings: environment.settings)

        func wait(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func count() -> Int { service.history.samples.count }

        wait(16)
        let closed = count()
        print("closed for 16 s: \(closed) samples (every 5 s in the background, the first only a baseline)")

        service.beginSampling()
        wait(5)
        let open = count()
        print("open for 5 s:    \(open) samples (every second while the tab is open)")

        service.endSampling()
        let justClosed = count()
        wait(6)
        let after = count()
        print("closed again:    \(justClosed) right away, \(after) after 6 s")

        let spacings = zip(service.history.samples, service.history.samples.dropFirst())
            .map { String(format: "%.1f", $1.time.timeIntervalSince($0.time)) }
        print("gaps between samples, seconds: \(spacings.joined(separator: " "))")

        let passed = closed >= 2 && open >= closed + 3 && justClosed == open && after > justClosed
        print(passed ? "ok   the history survives the tab closing" : "FAIL the history does not survive")
        return true
    }
}
#endif
