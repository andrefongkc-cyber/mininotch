import Foundation
import Observation
import SwiftUI

/// What a running interval is for.
///
/// Pomodoro is a preset on the countdown rather than a system beside it: the only thing that
/// makes an interval a Pomodoro is what happens when it ends, so the timer stays one thing
/// and `phase` decides whether anything follows.
enum TimerPhase: String, Equatable {
    /// A plain countdown. Nothing follows it.
    case countdown
    case work
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .countdown: return "Timer"
        case .work: return "Focus"
        case .shortBreak: return "Break"
        case .longBreak: return "Long Break"
        }
    }

    var symbolName: String {
        switch self {
        case .countdown: return "timer"
        case .work: return "brain.head.profile"
        case .shortBreak: return "cup.and.saucer"
        case .longBreak: return "figure.walk"
        }
    }

    var isPomodoro: Bool { self != .countdown }

    var tint: Color {
        switch self {
        case .countdown: return Color(nsColor: .systemBlue)
        case .work: return Color(nsColor: .systemRed)
        case .shortBreak: return Color(nsColor: .systemGreen)
        case .longBreak: return Color(nsColor: .systemTeal)
        }
    }
}

/// A countdown, and the Pomodoro cycle built on top of it.
///
/// Counts against a wall-clock deadline rather than decrementing a number on a tick. A tick
/// that is late, and every timer tick is late sometimes, would otherwise lose that time
/// permanently, so a twenty-five minute Pomodoro would quietly run long by however much the
/// machine was busy. The tick here only decides when to redraw; `remaining` is always
/// computed from the deadline.
///
/// Raises `onChange` rather than touching anything else. `AppEnvironment` owns the decisions
/// about presenting a Live Activity and posting a notification, the same way the battery
/// service raises `onLowBattery` and does not know notifications exist.
@Observable
final class TimerService {
    enum State: Equatable {
        case idle
        case running
        case paused
        /// Ran out and is waiting to be acknowledged, when auto-advance is off.
        case finished
    }

    private(set) var state: State = .idle
    private(set) var phase: TimerPhase = .countdown
    /// Total length of the interval currently loaded, in seconds.
    private(set) var duration: TimeInterval = 0
    /// Work intervals completed in the current set.
    private(set) var completedIntervals = 0

    /// Republished on every tick, purely so that observing views redraw.
    ///
    /// Observation fires on stored properties. Everything a view actually wants from this
    /// service, `remaining`, `progress`, `remainingText`, is computed from `deadline`, and
    /// `deadline` is `@ObservationIgnored` because it is an implementation detail rather than
    /// something a view should read. The result was that nothing observable changed as the
    /// clock advanced: the panel drew the countdown once and then sat frozen on it until some
    /// unrelated property happened to change, which made pausing look like the number jumping
    /// rather than stopping. This is the stored property that changes.
    private(set) var tickStamp: Date = .now

    /// Fires whenever anything a presenter would draw has changed, including every tick.
    @ObservationIgnored var onChange: (() -> Void)?
    /// Fires once when an interval runs out, with the phase that just ended.
    @ObservationIgnored var onCompletion: ((TimerPhase) -> Void)?

    @ObservationIgnored private var settings: SettingsStore?
    @ObservationIgnored private var deadline: Date?
    /// What was left when it was paused, so resuming does not lose the pause.
    @ObservationIgnored private var pausedRemaining: TimeInterval = 0
    @ObservationIgnored private var ticker: Timer?
    /// The rhythm the current set is running, which may not be the one in Settings: the
    /// widget can start any preset without changing what the button will do next time.
    @ObservationIgnored private var activePreset: PomodoroPreset?

    init() {}

    func start(settings: SettingsStore) {
        self.settings = settings
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        state = .idle
        deadline = nil
    }

    // MARK: Reading

    /// Seconds left, from the clock rather than from an accumulated count.
    var remaining: TimeInterval {
        switch state {
        case .idle: return duration
        case .paused: return pausedRemaining
        case .finished: return 0
        case .running:
            // `tickStamp` is read and discarded on purpose: reading it is what subscribes a view
            // to the clock. The value comes from the real one rather than from `tick`, so
            // pausing cannot lose up to a tick's worth of time, and every derived figure
            // still comes out of the same single subtraction.
            _ = tickStamp
            return max(0, deadline?.timeIntervalSinceNow ?? 0)
        }
    }

    /// 0...1 through the current interval.
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(1 - remaining / duration, 0), 1)
    }

    var isActive: Bool { state == .running || state == .paused || state == .finished }

    /// `12:34`, or `1:02:03` once there is an hour on it.
    var remainingText: String { Self.format(remaining) }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    // MARK: Commands

    /// Starts a plain countdown of `minutes`.
    func startCountdown(minutes: Double) {
        activePreset = nil
        completedIntervals = 0
        // Clamped rather than trusted: the custom field takes free text, and a zero-length
        // countdown would finish on the first tick and read as the button doing nothing.
        begin(phase: .countdown, seconds: min(max(minutes, 0.1), 1440) * 60)
    }

    /// Starts, or restarts, a Pomodoro set at its first work interval.
    ///
    /// `preset` overrides the configured rhythm for this set only. Starting an unusual one
    /// from the notch should not quietly rewrite what the Settings button does tomorrow.
    func startPomodoro(preset: PomodoroPreset? = nil) {
        activePreset = preset ?? settings?.timer.pomodoroPreset
        completedIntervals = 0
        begin(phase: .work, seconds: minutes(for: .work) * 60)
    }

    /// Adds time to whatever is running, without disturbing the phase or the set.
    ///
    /// The total grows with it, so the progress bar does not jump backwards past its own
    /// start when a minute is added near the end.
    func extend(byMinutes added: Double) {
        guard isActive, added > 0 else { return }
        let seconds = added * 60
        duration += seconds

        switch state {
        case .running:
            deadline = (deadline ?? Date()).addingTimeInterval(seconds)
        case .paused:
            pausedRemaining += seconds
        case .finished:
            // Reopens a finished interval rather than needing it restarted from zero.
            pausedRemaining = seconds
            deadline = Date().addingTimeInterval(seconds)
            state = .running
            startTicking()
        case .idle:
            break
        }
        // Explicit rather than relying on `duration` above happening to be observable, so
        // that a later change to how the total is tracked cannot silently freeze the display.
        tickStamp = Date()
        onChange?()
    }

    func pause() {
        guard state == .running else { return }
        pausedRemaining = remaining
        state = .paused
        deadline = nil
        stopTicking()
        onChange?()
    }

    func resume() {
        guard state == .paused else { return }
        deadline = Date().addingTimeInterval(pausedRemaining)
        state = .running
        startTicking()
        onChange?()
    }

    func toggle() {
        switch state {
        case .running: pause()
        case .paused: resume()
        case .idle, .finished: break
        }
    }

    /// Ends everything and clears the set.
    func reset() {
        stopTicking()
        state = .idle
        phase = .countdown
        deadline = nil
        pausedRemaining = 0
        duration = 0
        completedIntervals = 0
        activePreset = nil
        onChange?()
    }

    /// Ends the current interval early and moves to whatever would have followed it.
    func skip() {
        guard isActive else { return }
        advance(from: phase)
    }

    // MARK: Internals

    private func begin(phase: TimerPhase, seconds: TimeInterval) {
        self.phase = phase
        duration = seconds
        deadline = Date().addingTimeInterval(seconds)
        pausedRemaining = seconds
        state = .running
        startTicking()
        onChange?()
    }

    private func startTicking() {
        stopTicking()
        // Twice a second, so the displayed second never lags the real one by a whole tick.
        let ticker = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard state == .running else { return }
        tickStamp = Date()

        guard remaining <= 0 else {
            onChange?()
            return
        }

        let ended = phase
        onCompletion?(ended)

        guard settings?.timer.autoAdvance == true, ended.isPomodoro else {
            stopTicking()
            state = .finished
            onChange?()
            return
        }
        advance(from: ended)
    }

    /// Moves to the interval that follows `ended`.
    ///
    /// A countdown has nothing after it, so it stops. A work interval leads to a break, long
    /// every `intervalsBeforeLongBreak`, and any break leads back to work.
    private func advance(from ended: TimerPhase) {
        switch ended {
        case .countdown:
            stopTicking()
            state = .finished
            onChange?()

        case .work:
            completedIntervals += 1
            let isLong = intervalsBeforeLongBreak > 0
                && completedIntervals % intervalsBeforeLongBreak == 0
            let next: TimerPhase = isLong ? .longBreak : .shortBreak
            begin(phase: next, seconds: minutes(for: next) * 60)

        case .shortBreak, .longBreak:
            begin(phase: .work, seconds: minutes(for: .work) * 60)
        }
    }

    private var intervalsBeforeLongBreak: Int {
        lengths?.intervals ?? settings?.timer.intervalsBeforeLongBreak ?? 4
    }

    /// The rhythm in force, from the preset the set is running or from the stored values
    /// when that preset is `custom`.
    private var lengths: (work: Double, shortBreak: Double, longBreak: Double, intervals: Int)? {
        let preset = activePreset ?? settings?.timer.pomodoroPreset ?? .classic
        return preset.lengths
    }

    private func minutes(for phase: TimerPhase) -> Double {
        guard let settings else { return 25 }
        if phase == .countdown { return settings.timer.defaultCountdownMinutes }

        let l = lengths ?? (
            settings.timer.workMinutes,
            settings.timer.breakMinutes,
            settings.timer.longBreakMinutes,
            settings.timer.intervalsBeforeLongBreak
        )
        switch phase {
        case .countdown: return settings.timer.defaultCountdownMinutes
        case .work: return l.work
        case .shortBreak: return l.shortBreak
        case .longBreak: return l.longBreak
        }
    }
}
