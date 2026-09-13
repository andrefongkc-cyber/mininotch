import SwiftUI

/// One row in the Settings sidebar.
///
/// Grouped the way System Settings groups its own panes: behaviour first, then the
/// individual features, then the things you configure once and forget.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case appearance
    case media
    case calendar
    case huds
    case battery
    case shelf
    case timer
    case shortcuts
    case advanced
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .media: return "Media"
        case .calendar: return "Calendar"
        case .huds: return "HUDs"
        case .battery: return "Battery"
        case .shelf: return "Shelf"
        case .timer: return "Timer"
        case .shortcuts: return "Shortcuts"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .media: return "music.note"
        case .calendar: return "calendar"
        case .huds: return "speaker.wave.2"
        case .battery: return "battery.100percent"
        case .shelf: return "tray.full"
        case .timer: return "timer"
        case .shortcuts: return "command"
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
        case .media: return Color(nsColor: .systemRed)
        case .calendar: return Color(nsColor: .systemOrange)
        case .huds: return Color(nsColor: .systemPurple)
        case .battery: return Color(nsColor: .systemGreen)
        case .shelf: return Color(nsColor: .systemTeal)
        case .timer: return Color(nsColor: .systemYellow)
        case .shortcuts: return Color(nsColor: .systemIndigo)
        case .advanced: return Color(nsColor: .systemBlue)
        case .about: return Color(nsColor: .systemGray)
        }
    }

    /// Badge shown in the sidebar for panes whose feature is not finished.
    var badge: SettingsBadge? {
        switch self {
        case .huds: return FeatureFlag.hud.badge
        case .shelf: return FeatureFlag.shelf.badge
        case .timer: return FeatureFlag.pomodoro.badge
        default: return nil
        }
    }

    static let groups: [[SettingsTab]] = [
        [.general, .appearance],
        [.media, .calendar, .huds, .battery, .shelf, .timer],
        [.shortcuts, .advanced, .about]
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
