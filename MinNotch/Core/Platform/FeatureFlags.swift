import Foundation

/// Build- and tier-level gating for a feature.
///
/// Monetisation is undecided, so nothing is hardcoded as free or paid. Every flag resolves
/// through `FeatureGate.current`, which today returns `.shipping` for finished work and
/// `.hidden` for anything unbuilt. When a Pro tier exists, `FeatureGate` grows a
/// `.requiresPro` case and a receipt check; call sites do not change.
enum FeatureAvailability {
    /// Built, on by default, no gate.
    case shipping
    /// Built but rough. Rendered with a "Beta" badge.
    case beta
    /// Not built. Rendered with a "Coming soon" badge and disabled controls.
    case hidden
}

enum FeatureFlag: String, CaseIterable {
    case nowPlaying
    case lyrics
    case calendar
    case reminders
    case battery
    case systemStats
    case hud
    case shelf
    case weather
    case shortcutsWidget
    case clipboardHistory
    case linkShelf
    case quickNotes
    case pomodoro
    case focusMode
    case liveActivities
    case mirror
    case gestures
    case haptics
    case customVisualizers
    case multiDisplay
    case audioReactiveGlow

    var availability: FeatureAvailability {
        switch self {
        case .nowPlaying, .calendar, .battery, .multiDisplay, .systemStats:
            return .shipping
        case .lyrics:
            return .beta
        case .gestures, .haptics, .shelf, .hud, .reminders, .customVisualizers, .audioReactiveGlow,
             .clipboardHistory, .pomodoro, .liveActivities, .linkShelf:
            return .beta
        case .weather, .shortcutsWidget, .quickNotes, .focusMode, .mirror:
            return .hidden
        }
    }

    var isEnabled: Bool {
        switch availability {
        case .shipping, .beta: return true
        case .hidden: return false
        }
    }

    /// Badge to show next to this feature's controls, if any.
    var badge: SettingsBadge? {
        switch availability {
        case .shipping: return nil
        case .beta: return .beta
        case .hidden: return .comingSoon
        }
    }
}
