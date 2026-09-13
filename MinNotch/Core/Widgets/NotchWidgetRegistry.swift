import Foundation

/// Describes a widget that can occupy a tab in the expanded panel.
///
/// The registry is the single place that answers "which tabs should the panel show right
/// now", combining the feature flag, the per-feature enabled setting, and any runtime
/// requirement such as a granted permission. Views ask the registry rather than checking
/// settings directly, so gating a widget behind a Pro tier later is a one-line change.
struct NotchWidgetDescriptor: Identifiable {
    var tab: NotchTab
    var flag: FeatureFlag
    /// Whether the user has switched the feature on in Settings.
    var isEnabled: (SettingsStore) -> Bool

    var id: String { tab.rawValue }
}

enum NotchWidgetRegistry {
    static let all: [NotchWidgetDescriptor] = [
        NotchWidgetDescriptor(tab: .media, flag: .nowPlaying) { $0.media.enabled },
        NotchWidgetDescriptor(tab: .calendar, flag: .calendar) { $0.calendar.enabled },
        NotchWidgetDescriptor(tab: .system, flag: .systemStats) { _ in true },
        NotchWidgetDescriptor(tab: .shelf, flag: .shelf) { $0.shelf.enabled },
        NotchWidgetDescriptor(tab: .clipboard, flag: .clipboardHistory) { $0.advanced.clipboardHistoryEnabled },
        NotchWidgetDescriptor(tab: .timer, flag: .pomodoro) { $0.timer.enabled }
    ]

    /// Tabs the panel should currently render, in display order.
    static func availableTabs(_ settings: SettingsStore) -> [NotchTab] {
        all.filter { $0.flag.isEnabled && $0.isEnabled(settings) }.map(\.tab)
    }
}
