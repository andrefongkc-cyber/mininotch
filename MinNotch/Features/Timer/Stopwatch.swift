import Foundation
import Observation

/// The Timer tab's other half: a stopwatch, and which half is showing, and whether the tab is
/// popped out into its own window. Kept by `AppEnvironment` so the notch and that window, and the
/// notch after it closes, show the same thing.
@MainActor
@Observable
final class Stopwatch {
    enum Mode: String { case timer, stopwatch }

    var mode: Mode = .timer
    /// The Timer tab floating in a window of its own (`FloatingTimerController`).
    var isPoppedOut = false

    /// Counted from a start time rather than ticked, for the reason `TimerService` counts
    /// against a deadline: a late redraw never loses time.
    private(set) var startedAt: Date?
    private(set) var accumulated: TimeInterval = 0
    /// Lap times, each the total at the moment Lap was pressed, newest first.
    private(set) var laps: [TimeInterval] = []

    /// Raised when it starts, stops or resets, for Focus (`AppEnvironment.syncFocusGuard`).
    @ObservationIgnored var onChange: (() -> Void)?

    var isRunning: Bool { startedAt != nil }
    var hasTime: Bool { isRunning || accumulated > 0 }

    func elapsed(at date: Date = .now) -> TimeInterval {
        accumulated + (startedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    func toggle() {
        if let startedAt {
            accumulated += Date.now.timeIntervalSince(startedAt)
            self.startedAt = nil
        } else {
            startedAt = .now
        }
        onChange?()
    }

    func lap() {
        guard isRunning else { return }
        laps.insert(elapsed(), at: 0)
    }

    func reset() {
        startedAt = nil
        accumulated = 0
        laps = []
        onChange?()
    }

    /// From zero again, still running, for Focus.
    func restart() {
        accumulated = 0
        laps = []
        startedAt = .now
        onChange?()
    }

    /// "1:02.34" under an hour, "1:02:03" over.
    static func format(_ seconds: TimeInterval) -> String {
        let total = max(seconds, 0)
        let hours = Int(total) / 3600
        let minutes = Int(total) / 60 % 60
        let secs = Int(total) % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        let hundredths = Int((total * 100).rounded(.down)) % 100
        return String(format: "%d:%02d.%02d", minutes, secs, hundredths)
    }
}
