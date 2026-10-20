import SwiftUI

/// Settings > Battery & System's battery cards (`main`, and `more` under More Options). The
/// pane is put together in `SettingsPanes`.
struct BatterySettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppEnvironment.self) private var environment

    private var status: BatteryStatus { environment.battery.status }

    enum Part { case main, more }
    var part: Part = .main

    var body: some View {
        switch part {
        case .main: mainCards
        case .more: moreCards
        }
    }

    private var mainCards: some View {
        @Bindable var settings = settings
        return Group {
                SettingsCard(header: "Current") {
                    SettingsRow(
                        title: status.isPresent ? "\(status.percentage)%" : "No Battery",
                        subtitle: status.isPresent ? currentDescription : "This Mac runs on wall power.",
                        systemImage: status.symbolName
                    ) {
                        EmptyView()
                    }
                }

                SettingsCard(header: "In the Notch") {
                    SettingsRow(
                        title: "Show Percentage",
                        subtitle: "Otherwise only the battery glyph is shown. Whether the battery appears at all, and where, is arranged in Layout.",
                        systemImage: "percent",
                        isEnabled: status.isPresent
                    ) {
                        SettingsToggle(isOn: $settings.battery.showPercentage)
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: "Show Time Remaining",
                        subtitle: "In the expanded System panel.",
                        systemImage: "clock.arrow.circlepath",
                        isEnabled: status.isPresent
                    ) {
                        SettingsToggle(isOn: $settings.battery.showTimeRemaining)
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: "Show Charging Power",
                        subtitle: "While plugged in, the System panel shows what the charger delivers, what the Mac uses, and how much goes into the battery.",
                        systemImage: "bolt",
                        isEnabled: status.isPresent
                    ) {
                        SettingsToggle(isOn: $settings.battery.showChargingPower)
                    }
                }

                SettingsCard(
                    header: "Notifications",
                    footer: "MiniNotch asks for notification permission the first time it needs to alert you."
                ) {
                    SettingsRow(
                        title: "Low Battery Alert",
                        systemImage: "exclamationmark.triangle",
                        isEnabled: status.isPresent
                    ) {
                        SettingsToggle(isOn: $settings.battery.lowBatteryNotifications)
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: "Alert Threshold",
                        subtitle: "Notify once the charge drops to this level.",
                        systemImage: "gauge.with.dots.needle.33percent",
                        isEnabled: status.isPresent && settings.battery.lowBatteryNotifications
                    ) {
                        ValueSlider(
                            value: Binding(
                                get: { Double(settings.battery.lowBatteryThreshold) },
                                set: { settings.battery.lowBatteryThreshold = Int($0) }
                            ),
                            range: 5...50,
                            step: 5
                        ) { "\(Int($0))%" }
                    }

                    SettingsDivider()

                    SettingsRow(
                        title: "Power Adapter Alerts",
                        subtitle: "Notify when the charger is connected or removed.",
                        systemImage: "powerplug",
                        isEnabled: status.isPresent
                    ) {
                        SettingsToggle(isOn: $settings.battery.notifyOnPowerSourceChange)
                    }
                }

                AppEnergyCard(
                    stretch: environment.appEnergy.stretch,
                    ranking: environment.appEnergy.ranking,
                    isPluggedIn: status.isPluggedIn
                )
                .onAppear { environment.appEnergy.beginWatching() }
                .onDisappear { environment.appEnergy.endWatching() }
        }
    }

    private var moreCards: some View {
        @Bindable var settings = settings
        return Group {
                SettingsCard(
                    header: "Accessories",
                    footer: "Charge is read from devices that are paired and awake. Earbuds report each side and the case separately."
                ) {
                    SettingsRow(
                        title: "AirPods and Bluetooth Battery",
                        subtitle: "Show connected accessory charge in the System tab.",
                        systemImage: "airpodspro"
                    ) {
                        SettingsToggle(isOn: $settings.battery.showBluetoothDeviceBattery)
                    }
                }
        }
    }

    private var currentDescription: String {
        if status.isCharged && status.isPluggedIn { return "Fully charged" }
        if let description = status.timeRemainingDescription { return description }
        if status.isCharging { return "Charging" }
        if status.isPluggedIn { return "Plugged in" }
        return "On battery"
    }
}
