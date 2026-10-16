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
    /// When the stopwatch would have read zero, had it run without a pause; nil while stopped.
    /// The grid a redraw once a second, or once a tenth, lines up with.
    var zeroDate: Date? { startedAt?.addingTimeInterval(-accumulated) }
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

    /// How finely the running stopwatch is drawn. It redrew twenty times a second showing
    /// hundredths, so the last digit only ever read 2 or 7 (the user's report): now it is every
    /// frame to the hundredth, or, saving power, ten times a second to the tenth, so whichever
    /// digit is last always moves through all ten. With the hundredths switched off it is whole
    /// seconds, redrawn once a second.
    enum Precision {
        case hundredths, tenths, seconds

        init(showsFraction: Bool, savingPower: Bool) {
            self = !showsFraction ? .seconds : (savingPower ? .tenths : .hundredths)
        }

        /// Seconds between redraws, on the grid of `zeroDate`; nil is every frame.
        var redrawPeriod: TimeInterval? {
            switch self {
            case .hundredths: return nil
            case .tenths: return 0.1
            case .seconds: return 1
            }
        }
    }

    /// "1:02.34" under an hour ("1:02.3" in tenths, "1:02" in seconds), "1:02:03" over.
    static func format(_ seconds: TimeInterval, precision: Precision = .hundredths) -> String {
        let total = max(seconds, 0)
        let hours = Int(total) / 3600
        let minutes = Int(total) / 60 % 60
        let secs = Int(total) % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        switch precision {
        case .hundredths:
            let hundredths = Int((total * 100).rounded(.down)) % 100
            return String(format: "%d:%02d.%02d", minutes, secs, hundredths)
        case .tenths:
            let tenths = Int((total * 10).rounded(.down)) % 10
            return String(format: "%d:%02d.%d", minutes, secs, tenths)
        case .seconds:
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}
