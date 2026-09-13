import SwiftUI

struct ShortcutsSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        SettingsPane(
            title: "Shortcuts",
            subtitle: "Global shortcuts work from any app. MinNotch uses the system shortcut API, so no Accessibility permission is needed."
        ) {
            SettingsCard(header: "Global Shortcuts") {
                SettingsRow(
                    title: "Enable Global Shortcuts",
                    subtitle: "Turn this off to silence every shortcut without losing what you recorded.",
                    systemImage: "command"
                ) {
                    SettingsToggle(isOn: $settings.shortcuts.globalHotkeysEnabled)
                }
            }

            SettingsCard(
                header: "Actions",
                footer: "Press Escape while recording to cancel, or Delete to clear a shortcut."
            ) {
                ForEach(Array(HotkeyAction.allCases.enumerated()), id: \.element.id) { index, action in
                    if index > 0 { SettingsDivider() }

                    SettingsRow(
                        title: action.title,
                        systemImage: action.symbolName,
                        badge: action.isAvailable ? nil : .comingSoon,
                        isEnabled: settings.shortcuts.globalHotkeysEnabled
                    ) {
                        KeyComboRecorderView(
                            combo: Binding(
                                get: { settings.shortcuts.combo(for: action) },
                                set: { newValue in
                                    var shortcuts = settings.shortcuts
                                    shortcuts.setCombo(newValue, for: action)
                                    settings.shortcuts = shortcuts
                                }
                            ),
                            conflictCheck: { combo in
                                HotkeyManager.shared
                                    .conflictingAction(for: combo, in: settings.shortcuts, excluding: action)?
                                    .title
                            }
                        )
                    }
                }
            }
        }
    }
}
