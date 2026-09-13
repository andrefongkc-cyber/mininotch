#if DEBUG
import AppKit

/// Imports a settings file and prints what the store actually ended up with.
///
/// Run with `MinNotch --check-settings <file.minnotch>`.
///
/// A settings file is the one piece of structured input this app takes from outside itself:
/// it is exported, handed to other people, edited by hand, and written by older builds with
/// different limits. Decoding is lenient so a missing or malformed key degrades to a default,
/// and the numbers are clamped to the same ranges their controls enforce, but neither of those
/// is worth much unasserted. This prints the result so a deliberately hostile file can be
/// shown to come out bounded rather than assumed to.
@MainActor
enum DebugSettingsCheck {
    static let flag = "--check-settings"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return false }
        guard arguments.indices.contains(index + 1) else {
            report("usage: --check-settings <file>")
            exit(1)
        }

        let path = arguments[index + 1]
        guard let data = FileManager.default.contents(atPath: path) else {
            report("could not read \(path)")
            exit(1)
        }

        // Backed by a throwaway suite, so checking a file cannot overwrite real settings.
        let settings = DebugSupport.makeEnvironment().settings

        do {
            try settings.importData(data)
        } catch {
            report("rejected: \(error.localizedDescription)")
            exit(0)
        }

        report("imported \(data.count) bytes")
        report("")
        report(String(format: "  expandedWidth        %10.2f   (460...820)", settings.appearance.expandedWidth))
        report(String(format: "  panelCornerRadius    %10.2f   (8...32)", settings.appearance.panelCornerRadius))
        report(String(format: "  glow.intensity       %10.2f   (0.1...1)", settings.appearance.ambientGlow.intensity))
        report(String(format: "  glow.speed           %10.2f   (0...1)", settings.appearance.ambientGlow.speed))
        report(String(format: "  glow.glowRadius      %10.2f   (2...28)", settings.appearance.ambientGlow.glowRadius))
        report(String(format: "  hoverOpenDelay       %10.2f   (0...1)", settings.general.hoverOpenDelay))
        report(String(format: "  virtualNotchHeight   %10.2f   (22...48)", settings.advanced.virtualNotchHeight))
        report(String(format: "  virtualNotchWidth    %10.2f   (120...320)", settings.advanced.virtualNotchWidth))
        report(String(format: "  statsRefreshInterval %10.2f   (0.5...5)", settings.advanced.statsRefreshInterval))
        report(String(format: "  gestureSensitivity   %10.2f   (0...1)", settings.advanced.gestureSensitivity))
        report(String(format: "  lyricsOffset         %10.2f   (-2...2)", settings.media.lyricsOffset))
        report(String(format: "  pollInterval         %10.2f   (0.5...5)", settings.media.pollInterval))
        report(String(format: "  huds.dismissDelay    %10.2f   (0.5...4)", settings.huds.dismissDelay))
        report(String(format: "  lowBatteryThreshold  %10d   (5...50)", settings.battery.lowBatteryThreshold))
        report(String(format: "  shelf.maxItems       %10d   (4...40)", settings.shelf.maxItems))
        report(String(format: "  upcomingDayCount     %10d   (1...14)", settings.calendar.upcomingDayCount))
        report(String(format: "  maxVisibleEvents     %10d   (2...12)", settings.calendar.maxVisibleEvents))
        report(String(format: "  clipboardLimit       %10d   (5...100)", settings.advanced.clipboardHistoryLimit))
        report(String(format: "  timer.workMinutes    %10.2f   (1...120)", settings.timer.workMinutes))
        report(String(format: "  timer.breakMinutes   %10.2f   (1...60)", settings.timer.breakMinutes))
        report(String(format: "  timer.longBreak      %10.2f   (1...60)", settings.timer.longBreakMinutes))
        report(String(format: "  timer.intervals      %10d   (2...8)", settings.timer.intervalsBeforeLongBreak))
        report(String(format: "  timer.countdown      %10.2f   (1...180)", settings.timer.defaultCountdownMinutes))
        report("  nonNotchDefaultTab   \(settings.advanced.nonNotchDefaultTab.rawValue)  (must be a real tab)")
        report("")
        report("Every value must sit inside the range beside it, whatever the file asked for.")

        exit(0)
    }

    private static func report(_ message: String) {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    }
}
#endif
