import SwiftUI

/// Settings > General's cards. `main` is what the pane shows; `more` is folded under More
/// Options. The pane itself, with Gestures and Keyboard Shortcuts, is put together in
/// `SettingsPanes`.
struct GeneralSettingsView: View {
    enum Part { case main, more }
    var part: Part = .main

    @Environment(SettingsStore.self) private var settings
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        switch part {
        case .main:
            startup
            opening
            tabs
        case .more:
            timing
            permissions
        }
    }

    private var startup: some View {
        @Bindable var settings = settings
        return SettingsCard(
            header: "Startup",
            footer: LaunchAtLogin.isBlockedByUser
                ? "Login items for MiniNotch are turned off in System Settings > General > Login Items."
                : nil
        ) {
            SettingsRow(
                title: "Launch at Login",
                subtitle: "Start MiniNotch automatically when you log in.",
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

            SettingsDivider()

            SettingsRow(
                title: "Pin Settings to the Menu",
                subtitle: "Pin switches to the menu bar icon's menu, to turn them on and off without opening Settings.",
                systemImage: "pin",
                isEnabled: settings.general.showMenuBarIcon
            ) {
                Menu {
                    ForEach(MenuBarPin.allCases) { pin in
                        Toggle(pin.title, isOn: pinBinding(pin))
                    }
                } label: {
                    Text(pinSummary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private var opening: some View {
        @Bindable var settings = settings
        return SettingsCard(header: "Opening the Notch") {
            SettingsRow(
                title: "Open on Hover",
                subtitle: "Expand the panel when the pointer rests over the notch.",
                systemImage: "cursorarrow"
            ) {
                SettingsToggle(isOn: $settings.general.hoverToOpen)
            }

            SettingsDivider()

            SettingsRow(
                title: "Open on Click",
                subtitle: "Click the pill to expand it.",
                systemImage: "hand.tap"
            ) {
                SettingsToggle(isOn: $settings.general.clickToOpen)
            }
        }
    }

    private var tabs: some View {
        @Bindable var settings = settings
        return SettingsCard(header: "Tabs") {
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
                subtitle: "What the notch opens on every time, with Remember Last Tab off.",
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
    }

    private var timing: some View {
        @Bindable var settings = settings
        return SettingsCard(header: "Opening and Closing") {
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
                title: "Close When the Pointer Leaves",
                systemImage: "arrow.up.left.and.arrow.down.right"
            ) {
                SettingsToggle(isOn: $settings.general.closeOnMouseExit)
            }
        }
    }

    private var permissions: some View {
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

extension GeneralSettingsView {
    /// Pinned or not, kept in the order the choices are listed.
    fileprivate func pinBinding(_ pin: MenuBarPin) -> Binding<Bool> {
        Binding(
            get: { settings.general.menuBarPins.contains(pin) },
            set: { isOn in
                var pins = Set(settings.general.menuBarPins)
                if isOn { pins.insert(pin) } else { pins.remove(pin) }
                settings.general.menuBarPins = MenuBarPin.allCases.filter(pins.contains)
            }
        )
    }

    fileprivate var pinSummary: String {
        switch settings.general.menuBarPins.count {
        case 0: return "None"
        case 1: return settings.general.menuBarPins[0].title
        case let count: return "\(count) Pinned"
        }
    }
}
