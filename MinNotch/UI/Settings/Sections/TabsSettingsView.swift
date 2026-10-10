import SwiftUI

/// Settings > Tabs: every tab of the open notch that has settings, one section each, in the
/// order of the sidebar they replaced (Shelf, Timer, Weather) and then the ones that lived in
/// Advanced (Notes, Clipboard, System).
struct TabsSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        SettingsPane(title: "Tabs", subtitle: "Settings for each tab of the open notch. Which tabs show, and where, is in Layout.") {
            ShelfSettingsView()
            TimerSettingsView()
            WeatherSettingsView()
            NotesTabSettings()
            ClipboardTabSettings()
            SystemTabSettings()
        }
    }
}

private struct NotesTabSettings: View {
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
                        subtitle: "A Notes tab in the open panel: one scratchpad, kept between opens. The Open Notes shortcut in Shortcuts opens it ready to type.",
                        systemImage: "note.text",
                        badge: FeatureFlag.quickNotes.badge
                    ) {
                        SettingsToggle(isOn: $settings.advanced.notesEnabled)
                    }
                }

        }
    }
}

private struct ClipboardTabSettings: View {
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

private struct SystemTabSettings: View {
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
                        subtitle: "The chip, the battery and the SSD, read from the Mac's own sensors through a private part of macOS. In the units chosen in Settings > Tabs > Weather.",
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
struct TabSettingsSection<Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(Palette.primaryText)
                if let subtitle {
                    Text(subtitle).font(Typography.helper).foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 8)
            content
        }
    }
}
