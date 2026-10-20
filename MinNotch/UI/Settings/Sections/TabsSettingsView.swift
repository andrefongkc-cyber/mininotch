import SwiftUI

/// Cards for the Notes, Clipboard and System tabs, shown in the Shelf & Notes and Battery & System
/// panes (`SettingsPanes`). These used to be one Tabs pane with Shelf, Timer and Weather.
struct NotesTabSettings: View {
    @Environment(SettingsStore.self) private var settings
    var body: some View {
        @Bindable var settings = settings
        TabSettingsSection(title: "Notes", subtitle: "One scratchpad in its own tab, kept on this Mac.") {
                SettingsCard(
                    header: "Notes",
                    footer: "Saved as you type, in Library > Application Support > MiniNotch > Notes.txt, and never sent anywhere."
                ) {
                    SettingsRow(
                        title: "Show Notes",
                        subtitle: "A Notes tab in the open panel: one scratchpad, kept between opens. The Open Notes shortcut in General > Keyboard Shortcuts opens it ready to type.",
                        systemImage: "note.text",
                        badge: FeatureFlag.quickNotes.badge
                    ) {
                        SettingsToggle(isOn: $settings.advanced.notesEnabled)
                    }
                }

        }
    }
}

struct ClipboardTabSettings: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        @Bindable var settings = settings
        TabSettingsSection(title: "Clipboard", subtitle: "What you copy, offered back from its own tab.") {
                SettingsCard(
                    header: "Clipboard",
                    footer: "History is kept in memory only and is never written to disk. Copies made in the Passwords app or Keychain Access are skipped, and so is anything an app marks as private, which is what other password managers do."
                ) {
                    SettingsRow(
                        title: "Clipboard History",
                        subtitle: "Remember what you copy and offer it back from the Clipboard tab.",
                        systemImage: "doc.on.clipboard"
                    ) {
                        SettingsToggle(isOn: $settings.advanced.clipboardHistoryEnabled)
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: "Items Kept",
                        subtitle: "The oldest is dropped once the history is full. Pinned items do not count towards this.",
                        systemImage: "list.bullet",
                        isEnabled: settings.advanced.clipboardHistoryEnabled
                    ) {
                        ValueSlider(
                            value: Binding(
                                get: { Double(settings.advanced.clipboardHistoryLimit) },
                                set: { settings.advanced.clipboardHistoryLimit = Int($0) }
                            ),
                            range: 5...100,
                            step: 5
                        ) { "\(Int($0))" }
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: "Blur Until Unlocked",
                        subtitle: "Blur what you copied until you unlock it with Touch ID or your password. It blurs again when the tab closes.",
                        systemImage: "lock",
                        isEnabled: settings.advanced.clipboardHistoryEnabled
                    ) {
                        SettingsToggle(isOn: $settings.advanced.clipboardBlurUntilUnlocked)
                    }
                }

        }
    }
}

struct SystemTabSettings: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        @Bindable var settings = settings
        TabSettingsSection(title: "System", subtitle: "CPU, GPU, memory, network and temperatures, with five minutes of graphs.") {
                SettingsCard(
                    header: "System Stats",
                    footer: "The graphs keep the last five minutes: measured every five seconds in the background, and at the refresh interval while the System tab is open. Nothing is measured while this is off or the Mac is in Low Power Mode."
                ) {
                    SettingsRow(
                        title: "Show CPU, GPU, Memory and Network",
                        subtitle: "In the System tab of the notch.",
                        systemImage: "gauge.with.dots.needle.33percent"
                    ) {
                        SettingsToggle(isOn: $settings.advanced.showSystemStats)
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: "Refresh Interval",
                        subtitle: "How often the readout updates while it is on screen.",
                        systemImage: "arrow.clockwise",
                        isEnabled: settings.advanced.showSystemStats
                    ) {
                        ValueSlider(
                            value: $settings.advanced.statsRefreshInterval,
                            range: 0.5...5,
                            step: 0.5
                        ) { String(format: "%.1f s", $0) }
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: "Show Temperatures",
                        subtitle: "The chip, the battery and the SSD, read from the Mac's own sensors through a private part of macOS. In the units chosen in Settings > Weather.",
                        systemImage: "thermometer.medium",
                        isEnabled: settings.advanced.showSystemStats
                    ) {
                        SettingsToggle(isOn: $settings.advanced.showTemperatures)
                    }
                }

        }
    }
}

/// One tab's settings inside the Tabs pane: a heading and its cards.
/// A feature's cards, in a pane that may hold several features.
///
/// It used to put the feature's name and a line about it above the cards, which in the
/// feature-named panes repeated the pane's title and in Shelf & Notes repeated each card's own
/// header ("Shelf", then a card headed "Shelf"). The card headers name the feature now, so this
/// draws the cards alone; `title` and `subtitle` stay as the code's own label for the group.
struct TabSettingsSection<Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
            content
        }
    }
}
