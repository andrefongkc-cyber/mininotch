import AppKit
import Carbon.HIToolbox

/// Everything a global shortcut can trigger.
///
/// Only `.toggleNotch` is bound by default in V1. The rest are declared now so that
/// Settings > Shortcuts lists real, recordable rows, and so wiring a V2 feature to a
/// shortcut is a matter of handling its case in `AppEnvironment.perform(_:)`.
enum HotkeyAction: String, CaseIterable, Identifiable {
    case toggleNotch
    case openSettings
    case playPause
    case nextTrack
    case previousTrack
    case toggleShelf
    case quickNote
    case startTimer
    case keepOpen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleNotch: return "Show or Hide the Notch"
        case .openSettings: return "Open Settings"
        case .playPause: return "Play / Pause"
        case .nextTrack: return "Next Track"
        case .previousTrack: return "Previous Track"
        case .toggleShelf: return "Toggle Shelf"
        case .quickNote: return "New Quick Note"
        case .startTimer: return "Start Timer"
        case .keepOpen: return "Keep the Notch Open"
        }
    }

    var symbolName: String {
        switch self {
        case .toggleNotch: return "rectangle.topthird.inset.filled"
        case .openSettings: return "gearshape"
        case .playPause: return "playpause"
        case .nextTrack: return "forward.end"
        case .previousTrack: return "backward.end"
        case .toggleShelf: return "tray.full"
        case .quickNote: return "note.text"
        case .startTimer: return "timer"
        case .keepOpen: return "pin"
        }
    }

    /// Feature that must be enabled for this action to do anything.
    var requiredFlag: FeatureFlag? {
        switch self {
        case .toggleNotch, .openSettings, .keepOpen: return nil
        case .playPause, .nextTrack, .previousTrack: return .nowPlaying
        case .toggleShelf: return .shelf
        case .quickNote: return .quickNotes
        case .startTimer: return .pomodoro
        }
    }

    var isAvailable: Bool { requiredFlag?.isEnabled ?? true }

    /// ⌃⌥N and ⌃⌥P are unclaimed by macOS and by the common apps that would conflict.
    static let defaultBindings: [String: KeyCombo] = [
        HotkeyAction.toggleNotch.rawValue: KeyCombo(
            keyCode: UInt32(kVK_ANSI_N),
            modifierFlags: NSEvent.ModifierFlags([.control, .option]).rawValue
        ),
        HotkeyAction.keepOpen.rawValue: KeyCombo(
            keyCode: UInt32(kVK_ANSI_P),
            modifierFlags: NSEvent.ModifierFlags([.control, .option]).rawValue
        ),
    ]

    /// Every action there was before `knownActions` was saved, for settings files older than it.
    static let actionsBeforeKnownActions: [String] = [
        "toggleNotch", "openSettings", "playPause", "nextTrack", "previousTrack",
        "toggleShelf", "quickNote", "startTimer",
    ]
}
