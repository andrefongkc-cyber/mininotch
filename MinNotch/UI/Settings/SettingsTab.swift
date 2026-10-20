import SwiftUI

/// One row in the Settings sidebar.
///
/// Named after what is being changed rather than after the app's internals: Music, not Media;
/// Volume & Brightness, not HUDs. Each feature has its own pane, so the user looking for the
/// weather finds Weather rather than a Tabs pane (2026-10-19, "way too hard to find things").
/// Grouped the way System Settings groups its own panes: how the notch behaves and looks, then
/// the features, then the Mac's own readings, then the things you configure once and forget.
/// Each pane folds its rarely changed rows under More Options; see `SettingsPanes`.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case appearance
    case layout
    case music
    case lockScreen
    case calendar
    case weather
    case timer
    case shelf
    case batterySystem
    case huds
    case advanced
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .layout: return "Layout"
        case .music: return "Music"
        case .lockScreen: return "Lock Screen"
        case .calendar: return "Calendar"
        case .weather: return "Weather"
        case .timer: return "Timer"
        case .shelf: return "Shelf & Notes"
        case .batterySystem: return "Battery & System"
        case .huds: return "Volume & Brightness"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .layout: return "rectangle.3.group"
        case .music: return "music.note"
        case .lockScreen: return "lock.fill"
        case .calendar: return "calendar"
        case .weather: return "cloud.sun.fill"
        case .timer: return "timer"
        case .shelf: return "tray.full"
        case .batterySystem: return "battery.100percent"
        case .huds: return "speaker.wave.2"
        case .advanced: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }

    /// Tint of the sidebar icon's rounded square, matching the System Settings idiom of one
    /// colour per pane.
    var tint: Color {
        switch self {
        case .general: return Color(nsColor: .systemGray)
        case .appearance: return Color(nsColor: .systemPink)
        case .layout: return Color(nsColor: .systemCyan)
        case .music: return Color(nsColor: .systemRed)
        case .lockScreen: return Color(nsColor: .systemIndigo)
        case .calendar: return Color(nsColor: .systemOrange)
        case .weather: return Color(nsColor: .systemTeal)
        case .timer: return Color(nsColor: .systemYellow)
        case .shelf: return Color(nsColor: .systemBrown)
        case .batterySystem: return Color(nsColor: .systemGreen)
        case .huds: return Color(nsColor: .systemPurple)
        case .advanced: return Color(nsColor: .systemBlue)
        case .about: return Color(nsColor: .systemGray)
        }
    }

    /// Badge shown in the sidebar for panes whose feature is not finished.
    var badge: SettingsBadge? {
        switch self {
        case .huds: return FeatureFlag.hud.badge
        default: return nil
        }
    }

    static let groups: [[SettingsTab]] = [
        [.general, .appearance, .layout],
        [.music, .lockScreen, .calendar, .weather, .timer, .shelf],
        [.batterySystem, .huds],
        [.advanced, .about]
    ]
}

/// The rounded-square icon System Settings puts beside each sidebar row.
struct SidebarIcon: View {
    let tab: SettingsTab

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(tab.tint.gradient)
            .frame(width: 19, height: 19)
            .overlay(
                Image(systemName: tab.symbolName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
            )
    }
}
