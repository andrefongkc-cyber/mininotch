import SwiftUI

struct GeneralSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        @Bindable var settings = settings

        SettingsPane(title: "General") {
            SettingsCard(
                header: "Startup",
                footer: LaunchAtLogin.isBlockedByUser
                    ? "Login items for MinNotch are turned off in System Settings > General > Login Items."
                    : nil
            ) {
                SettingsRow(
                    title: "Launch at Login",
                    subtitle: "Start MinNotch automatically when you log in.",
                    systemImage: "power"
                ) {
                    SettingsToggle(isOn: $settings.general.launchAtLogin)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Show Menu Bar Icon",
                    subtitle: "Turn this off to run from the notch alone. The keyboard shortcut keeps working either way.",
                    systemImage: "menubar.rectangle"
                ) {
                    SettingsToggle(isOn: $settings.general.showMenuBarIcon)
                }
            }

            SettingsCard(header: "Opening the Notch") {
                SettingsRow(
                    title: "Open on Hover",
                    subtitle: "Expand the panel when the pointer rests over the notch.",
                    systemImage: "cursorarrow"
                ) {
                    SettingsToggle(isOn: $settings.general.hoverToOpen)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Hover Delay",
                    subtitle: "How long the pointer has to rest before the panel opens.",
                    systemImage: "clock",
                    isEnabled: settings.general.hoverToOpen
                ) {
                    ValueSlider(
                        value: $settings.general.hoverOpenDelay,
                        range: 0...1.0,
                        step: 0.05
                    ) { value in
                        value == 0 ? "Instant" : String(format: "%.2f s", value)
                    }
                }

                SettingsDivider()

                SettingsRow(
                    title: "Open on Click",
                    subtitle: "Click the pill to expand it.",
                    systemImage: "hand.tap"
                ) {
                    SettingsToggle(isOn: $settings.general.clickToOpen)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Close When the Pointer Leaves",
                    systemImage: "arrow.up.left.and.arrow.down.right"
                ) {
                    SettingsToggle(isOn: $settings.general.closeOnMouseExit)
                }
            }

            SettingsCard(header: "Tabs") {
                SettingsRow(
                    title: "Remember Last Tab",
                    subtitle: "Reopen on whichever widget you used last.",
                    systemImage: "arrow.uturn.backward"
                ) {
                    SettingsToggle(isOn: $settings.general.rememberLastTab)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Default Tab",
                    systemImage: "square.grid.2x2",
                    isEnabled: !settings.general.rememberLastTab
                ) {
                    InlinePicker(selection: $settings.general.defaultTab) {
                        ForEach(NotchTab.allCases) { tab in
                            Label(tab.title, systemImage: tab.symbolName).tag(tab)
                        }
                    }
                }
            }

            SettingsCard(header: "Permissions") {
                SettingsRow(
                    title: "Login Items",
                    subtitle: "Review which apps macOS allows to start at login.",
                    systemImage: "list.bullet.rectangle"
                ) {
                    Button("Open") { LaunchAtLogin.openLoginItemsSettings() }
                        .controlSize(.small)
                }
            }
        }
    }
}
