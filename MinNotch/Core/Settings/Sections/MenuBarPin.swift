import Foundation

/// A setting that can be pinned to the menu bar icon's menu (Settings > General > Menu Bar), to
/// switch on and off without opening Settings.
///
/// Only switches that take effect by themselves are offered. Hide the System Overlay is not:
/// switching it on asks for Accessibility from the HUDs pane, and a menu item would skip that.
enum MenuBarPin: String, Codable, CaseIterable, Identifiable {
    case openOnHover
    case indicatorsWhenClosed
    case notchOnOtherDisplays
    case lyricsWhenClosed
    case sneakPeek
    case ambientGlow
    case followTheBeat
    case focusTimer
    case clipboardHistory
    case haptics

    var id: String { rawValue }

    /// The setting's own title in Settings, so the two read the same.
    var title: String {
        switch self {
        case .openOnHover: return "Open on Hover"
        case .indicatorsWhenClosed: return "Show Indicators When Closed"
        case .notchOnOtherDisplays: return "Show on Displays Without a Notch"
        case .lyricsWhenClosed: return "Show Lyrics When Closed"
        case .sneakPeek: return "Sneak Peek on Track Change"
        case .ambientGlow: return "Ambient Glow"
        case .followTheBeat: return "Follow the Beat"
        case .focusTimer: return "Focus Timer"
        case .clipboardHistory: return "Clipboard History"
        case .haptics: return "Haptic Feedback"
        }
    }

    @MainActor var keyPath: ReferenceWritableKeyPath<SettingsStore, Bool> {
        switch self {
        case .openOnHover: return \.general.hoverToOpen
        case .indicatorsWhenClosed: return \.general.extendPillForIndicators
        case .notchOnOtherDisplays: return \.advanced.showOnNonNotchDisplays
        case .lyricsWhenClosed: return \.media.showLyricsWhenClosed
        case .sneakPeek: return \.media.sneakPeekOnTrackChange
        case .ambientGlow: return \.appearance.ambientGlow.isEnabled
        case .followTheBeat: return \.appearance.ambientGlow.isAudioReactive
        case .focusTimer: return \.timer.focusMode
        case .clipboardHistory: return \.advanced.clipboardHistoryEnabled
        case .haptics: return \.advanced.hapticFeedbackEnabled
        }
    }
}
