import Foundation

/// A ready-made work and break rhythm.
///
/// Presets rather than only sliders, because the useful lengths are a small set of
/// well-known ones and nobody wants to look up what the 52/17 rule is before using it. The
/// sliders remain, as `custom`, so an unusual rhythm is still expressible.
enum PomodoroPreset: String, Codable, CaseIterable, Identifiable {
    /// Cirillo's original: 25 on, 5 off, a longer break every fourth.
    case classic
    /// Longer blocks for work that takes a while to get into.
    case deepWork
    /// Short cycles, for a day that keeps getting interrupted anyway.
    case short
    /// The 52/17 rule, from the DeskTime study.
    case fiftyTwoSeventeen
    /// Whatever the sliders in Settings say.
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .deepWork: return "Deep Work"
        case .short: return "Short"
        case .fiftyTwoSeventeen: return "52 / 17"
        case .custom: return "Custom"
        }
    }

    /// Work, short break, long break, and how many work intervals precede the long one.
    /// Nil for `custom`, which reads the stored values instead.
    var lengths: (work: Double, shortBreak: Double, longBreak: Double, intervals: Int)? {
        switch self {
        case .classic: return (25, 5, 15, 4)
        case .deepWork: return (50, 10, 30, 2)
        case .short: return (15, 3, 10, 4)
        case .fiftyTwoSeventeen: return (52, 17, 17, 2)
        case .custom: return nil
        }
    }

    /// One-line summary for a settings subtitle or a button's help.
    func summary(custom: TimerSettings) -> String {
        let l = lengths ?? (custom.workMinutes, custom.breakMinutes, custom.longBreakMinutes, custom.intervalsBeforeLongBreak)
        return "\(Int(l.work))m focus · \(Int(l.shortBreak))m break · \(Int(l.longBreak))m long break after \(l.intervals)"
    }
}

/// Settings > Timer.
struct TimerSettings: Codable, Equatable {
    var enabled: Bool = true

    /// Which rhythm "Start Pomodoro" uses. The three lengths below are the `custom` one.
    var pomodoroPreset: PomodoroPreset = .classic

    /// Minutes in a Pomodoro work interval.
    var workMinutes: Double = 25
    /// Minutes in the short break after each work interval.
    var breakMinutes: Double = 5
    /// Minutes in the longer break after a full set.
    var longBreakMinutes: Double = 15
    /// Work intervals before the long break.
    var intervalsBeforeLongBreak: Int = 4

    /// Start the next interval on its own when one finishes.
    ///
    /// On by default: a Pomodoro that waits for a click after every interval is a Pomodoro
    /// that stops the first time you are concentrating hard enough not to notice it.
    var autoAdvance: Bool = true

    /// Post a notification when an interval ends.
    var notifyOnCompletion: Bool = true

    /// Minutes a plain countdown starts at, before the user changes it.
    var defaultCountdownMinutes: Double = 10

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.value(.enabled, true)
        pomodoroPreset = c.value(.pomodoroPreset, PomodoroPreset.classic)
        workMinutes = c.value(.workMinutes, 25, in: 1...120)
        breakMinutes = c.value(.breakMinutes, 5, in: 1...60)
        longBreakMinutes = c.value(.longBreakMinutes, 15, in: 1...60)
        intervalsBeforeLongBreak = c.value(.intervalsBeforeLongBreak, 4, in: 2...8)
        autoAdvance = c.value(.autoAdvance, true)
        notifyOnCompletion = c.value(.notifyOnCompletion, true)
        defaultCountdownMinutes = c.value(.defaultCountdownMinutes, 10, in: 1...180)
    }
}
