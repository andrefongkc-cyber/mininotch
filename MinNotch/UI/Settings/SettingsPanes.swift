import SwiftUI

/// Every Settings pane, put together from the cards in `Sections/`.
///
/// Each pane shows the settings most people change and folds the rest under More Options
/// (`SettingsMoreOptions`). The card views take a `part` saying which of their cards to draw, so a
/// pane can take cards from several of them: General holds the gestures and keyboard shortcuts,
/// Lock Screen holds the song and the volume indicator, Shelf & Notes the shelf, notes and
/// clipboard. A search result reaches a folded row as well: the row opens its fold.
struct SettingsPanes: View {
    let tab: SettingsTab

    var body: some View {
        switch tab {
        case .general:
            SettingsPane(title: tab.title) {
                GeneralSettingsView()
                SettingsMoreOptions(tab.rawValue) {
                    GeneralSettingsView(part: .more)
                    AdvancedSettingsView(part: .gestures)
                    ShortcutsSettingsView()
                }
            }
        case .appearance:
            SettingsPane(title: tab.title, subtitle: "How the notch looks: its style, accent, size and glow.") {
                AppearanceSettingsView()
                SettingsMoreOptions(tab.rawValue) {
                    AppearanceSettingsView(part: .more)
                }
            }
        case .layout:
            SettingsPane(
                title: tab.title,
                subtitle: "Drag icons into the notch to choose what it shows and where, or click one in a tray to add it. Drag an icon back to its tray, or hover it and click ×, to take it out."
            ) {
                LayoutSettingsView()
                SettingsMoreOptions(tab.rawValue) {
                    LayoutSettingsView(part: .more)
                }
            }
        case .music:
            SettingsPane(title: tab.title) {
                MediaSettingsView()
                SettingsMoreOptions(tab.rawValue) {
                    MediaSettingsView(part: .more)
                }
            }
        case .lockScreen:
            SettingsPane(title: tab.title, subtitle: "What MiniNotch shows while your Mac is locked.") {
                MediaSettingsView(part: .lockScreen)
                HUDSettingsView(part: .lockScreen)
                SettingsMoreOptions(tab.rawValue) {
                    MediaSettingsView(part: .lockScreenMore)
                }
            }
        case .calendar:
            SettingsPane(title: tab.title) {
                CalendarSettingsView()
                SettingsMoreOptions(tab.rawValue) {
                    CalendarSettingsView(part: .more)
                }
            }
        case .weather:
            SettingsPane(
                title: tab.title,
                subtitle: "The forecast in its own tab, and the temperature in the closed pill if you place it there in Layout."
            ) {
                WeatherSettingsView()
            }
        case .timer:
            SettingsPane(title: tab.title, subtitle: "A countdown in the notch, and the Pomodoro cycle built on top of it.") {
                TimerSettingsView()
                SettingsMoreOptions(tab.rawValue) {
                    TimerSettingsView(part: .more)
                }
            }
        case .shelf:
            SettingsPane(title: tab.title, subtitle: "Files, links, a scratchpad, and what you copy, kept in the notch.") {
                ShelfSettingsView()
                NotesTabSettings()
                ClipboardTabSettings()
                SettingsMoreOptions(tab.rawValue) {
                    ShelfSettingsView(part: .more)
                }
            }
        case .batterySystem:
            SettingsPane(title: tab.title) {
                BatterySettingsView()
                SystemTabSettings()
                SettingsMoreOptions(tab.rawValue) {
                    BatterySettingsView(part: .more)
                }
            }
        case .huds:
            SettingsPane(
                title: tab.title,
                subtitle: "Show volume, brightness, and keyboard backlight in the notch instead of hunting for the overlay in the middle of the screen."
            ) {
                HUDSettingsView()
                SettingsMoreOptions(tab.rawValue) {
                    HUDSettingsView(part: .more)
                }
            }
        case .advanced:
            SettingsPane(title: tab.title) {
                AdvancedSettingsView()
            }
        case .about:
            AboutSettingsView()
        }
    }
}
