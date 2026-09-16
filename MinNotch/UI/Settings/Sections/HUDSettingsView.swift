import SwiftUI

/// Settings > HUDs.
struct HUDSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppEnvironment.self) private var environment

    private var coordinator: HUDCoordinator { environment.hud }

    var body: some View {
        @Bindable var settings = settings

        SettingsPane(
            title: "HUDs",
            subtitle: "Show volume, brightness, and keyboard backlight in the notch instead of hunting for the overlay in the middle of the screen."
        ) {
            SettingsCard(
                header: "Show in the Notch",
                footer: "These add an indicator at the notch. Apple's own overlay appears too unless you hide it below."
            ) {
                SettingsRow(
                    title: "Volume",
                    subtitle: "Updates the moment the level changes, with no polling.",
                    systemImage: "speaker.wave.2",
                    badge: FeatureFlag.hud.badge
                ) {
                    SettingsToggle(isOn: $settings.huds.replaceVolumeHUD)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Brightness",
                    subtitle: brightnessSubtitle,
                    systemImage: "sun.max",
                    badge: FeatureFlag.hud.badge,
                    isEnabled: coordinator.isBrightnessSupported
                ) {
                    SettingsToggle(isOn: $settings.huds.replaceBrightnessHUD)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Keyboard Backlight",
                    subtitle: keyboardSubtitle,
                    systemImage: "keyboard",
                    badge: FeatureFlag.hud.badge,
                    isEnabled: coordinator.isKeyboardBacklightSupported
                ) {
                    SettingsToggle(isOn: $settings.huds.replaceKeyboardBacklightHUD)
                }
            }

            SettingsCard(
                header: "System Overlay",
                footer: "MinNotch takes the volume and brightness keys before macOS sees them, sets the level itself, and shows only its own indicator. This needs Accessibility access. Keyboard backlight keys are left to macOS. Quitting MinNotch gives the keys straight back."
            ) {
                SettingsRow(
                    title: "Hide the System Overlay",
                    subtitle: "Show only MinNotch's volume and brightness indicator instead of both. Works for whichever of those two is switched on above.",
                    systemImage: "rectangle.slash"
                ) {
                    SettingsToggle(isOn: $settings.huds.suppressSystemOverlay)
                }
                .onChange(of: settings.huds.suppressSystemOverlay) { _, isOn in
                    // Asked for here, when the user has just switched it on, and never at launch.
                    if isOn, !SystemKeyInterceptor.isTrusted { coordinator.requestAccessibility() }
                }

                if coordinator.needsAccessibility {
                    SettingsDivider()

                    SettingsRow(
                        title: "Accessibility Access Needed",
                        subtitle: "Turn on MinNotch in Privacy & Security > Accessibility. Until then Apple's overlay still appears. After installing a new copy of MinNotch, remove it from the list and add it again.",
                        systemImage: "exclamationmark.triangle"
                    ) {
                        Button("Open Settings") { SystemKeyInterceptor.openAccessibilitySettings() }
                            .controlSize(.small)
                    }
                }
            }

            SettingsCard(header: "Presentation") {
                SettingsRow(title: "Style", systemImage: "rectangle.on.rectangle") {
                    InlinePicker(selection: $settings.huds.style) {
                        ForEach(HUDStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                }

                SettingsDivider()

                SettingsRow(
                    title: "Dismiss After",
                    subtitle: "How long the indicator stays on screen after the last change.",
                    systemImage: "timer"
                ) {
                    ValueSlider(
                        value: $settings.huds.dismissDelay,
                        range: 0.5...4,
                        step: 0.25
                    ) { String(format: "%.2f s", $0) }
                }

                SettingsDivider()

                SettingsRow(title: "Show Numeric Value", systemImage: "number") {
                    SettingsToggle(isOn: $settings.huds.showNumericValue)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Preview",
                    subtitle: "Show an indicator now, so you can see the style without reaching for a key.",
                    systemImage: "eye"
                ) {
                    Button("Show") { coordinator.preview(.volume) }
                        .controlSize(.small)
                }
            }
        }
    }

    private var brightnessSubtitle: String {
        coordinator.isBrightnessSupported
            ? "Polled while this is on, because macOS does not announce brightness changes."
            : "This version of macOS does not expose display brightness to apps."
    }

    private var keyboardSubtitle: String {
        coordinator.isKeyboardBacklightSupported
            ? "Polled while this is on, because macOS does not announce backlight changes."
            : "This Mac's keyboard does not report a backlight level."
    }
}
