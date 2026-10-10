import SwiftUI
import UniformTypeIdentifiers

struct AdvancedSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppEnvironment.self) private var environment

    @State private var importError: String?
    @State private var isConfirmingReset = false

    var body: some View {
        @Bindable var settings = settings

        SettingsPane(title: "Advanced") {
            SettingsCard(
                header: "Displays",
                footer: "Macs without a physical notch are fully supported. MiniNotch draws a virtual one in the same place."
            ) {
                SettingsRow(
                    title: "Show on Displays Without a Notch",
                    systemImage: "display.2"
                ) {
                    SettingsToggle(isOn: $settings.advanced.showOnNonNotchDisplays)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Show On",
                    subtitle: "Which display carries the notch when several are connected.",
                    systemImage: "rectangle.on.rectangle"
                ) {
                    InlinePicker(selection: $settings.advanced.displayTargeting) {
                        ForEach(DisplayTargeting.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }

                SettingsDivider()

                SettingsRow(
                    title: "Opens On Without a Notch",
                    subtitle: "Which tab a virtual notch starts on. A real notch hides behind the camera housing; one on an external monitor does not, so it may as well be showing something.",
                    systemImage: "rectangle.topthird.inset.filled",
                    isEnabled: settings.advanced.showOnNonNotchDisplays
                ) {
                    InlinePicker(selection: $settings.advanced.nonNotchDefaultTab) {
                        ForEach(NotchTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                }

                SettingsDivider()

                SettingsRow(
                    title: "Hide Until Hovered",
                    subtitle: "On displays without a notch, draw nothing until the pointer reaches the top middle of the screen, then open as usual. Volume and brightness still show. Needs Open on Hover, or click there instead.",
                    systemImage: "eye.slash",
                    isEnabled: settings.advanced.showOnNonNotchDisplays
                ) {
                    SettingsToggle(isOn: $settings.advanced.hideVirtualNotchUntilHover)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Keep the Notch Still Between Desktops",
                    subtitle: NotchSpace.shared.isAvailable
                        ? "Without it the notch slides away and back when you swipe between desktops. Uses a private part of macOS, so a future version may stop it working."
                        : "Not available on this version of macOS.",
                    systemImage: "rectangle.on.rectangle.slash",
                    isEnabled: NotchSpace.shared.isAvailable
                ) {
                    SettingsToggle(isOn: $settings.advanced.keepNotchStillBetweenDesktops)
                }
            }

            SettingsCard(header: "Size") {
                SettingsRow(
                    title: "Height",
                    subtitle: "Match the hardware cutout, or pin a fixed height everywhere.",
                    systemImage: "arrow.up.and.down"
                ) {
                    InlinePicker(selection: $settings.advanced.notchHeightMode) {
                        ForEach(NotchHeightMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }

                SettingsDivider()

                SettingsRow(
                    title: "Virtual Notch Height",
                    subtitle: "Used on displays with no physical notch.",
                    systemImage: "ruler"
                ) {
                    ValueSlider(
                        value: $settings.advanced.virtualNotchHeight,
                        range: 22...48,
                        step: 1
                    ) { "\(Int($0)) pt" }
                }

                SettingsDivider()

                SettingsRow(
                    title: "Virtual Notch Width",
                    systemImage: "ruler"
                ) {
                    ValueSlider(
                        value: $settings.advanced.virtualNotchWidth,
                        range: 120...320,
                        step: 5
                    ) { "\(Int($0)) pt" }
                }
            }

            SettingsCard(header: "Interaction") {
                SettingsRow(
                    title: "Two-Finger Gestures",
                    subtitle: "Swipe sideways over the notch to change tab, or up and down to close and open it.",
                    systemImage: "hand.draw",
                    badge: FeatureFlag.gestures.badge
                ) {
                    SettingsToggle(isOn: $settings.advanced.twoFingerGesturesEnabled)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Gesture Sensitivity",
                    systemImage: "dial.medium",
                    badge: FeatureFlag.gestures.badge,
                    isEnabled: settings.advanced.twoFingerGesturesEnabled
                ) {
                    ValueSlider(
                        value: $settings.advanced.gestureSensitivity,
                        range: 0...1,
                        step: 0.05
                    ) { String(format: "%.0f%%", $0 * 100) }
                }

                SettingsDivider()

                SettingsRow(
                    title: "Reverse Swipe Direction",
                    subtitle: "Swap which way a sideways swipe moves through the tabs.",
                    systemImage: "arrow.left.arrow.right",
                    isEnabled: settings.advanced.twoFingerGesturesEnabled
                ) {
                    SettingsToggle(isOn: $settings.advanced.invertGestureDirection)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Haptic Feedback",
                    subtitle: "A small tap from the trackpad when the notch opens, closes, or changes tab. Force Touch trackpads only.",
                    systemImage: "hand.tap",
                    badge: FeatureFlag.haptics.badge
                ) {
                    SettingsToggle(isOn: $settings.advanced.hapticFeedbackEnabled)
                }

            }

            SettingsCard(
                header: "Settings File",
                footer: importError
            ) {
                SettingsRow(
                    title: "Export Settings",
                    subtitle: "Save every preference to a single file.",
                    systemImage: "square.and.arrow.up"
                ) {
                    Button("Export…", action: exportSettings).controlSize(.small)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Import Settings",
                    systemImage: "square.and.arrow.down"
                ) {
                    Button("Import…", action: importSettings).controlSize(.small)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Reset All Settings",
                    subtitle: "Return every preference to its default.",
                    systemImage: "arrow.counterclockwise"
                ) {
                    Button("Reset…") { isConfirmingReset = true }
                        .controlSize(.small)
                }
            }

            SettingsCard(header: "Diagnostics") {
                SettingsRow(
                    title: "Show Layout Overlay",
                    subtitle: "Outline the notch's interactive area to debug placement.",
                    systemImage: "square.dashed"
                ) {
                    SettingsToggle(isOn: $settings.advanced.showDebugOverlay)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Debug Buttons in Top Bar",
                    subtitle: "Add What's New and Tutorial buttons to the open notch's top bar, to check both quickly. On by default only in Debug builds.",
                    systemImage: "ladybug"
                ) {
                    SettingsToggle(isOn: $settings.advanced.showDebugButtons)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Show Welcome Again",
                    subtitle: "Open the first-launch tutorial again. Its checklist starts from what is switched on now, so nothing changes unless you change it.",
                    systemImage: "sparkles"
                ) {
                    Button("Show") { environment.onboarding.present(isRerun: true) }
                        .controlSize(.small)
                }
            }
        }
        .confirmationDialog(
            "Reset all MiniNotch settings?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { settings.resetToDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every preference returns to its default. This cannot be undone.")
        }
    }

    // MARK: Export and import

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = settings.exportFilename
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.exportData().write(to: url)
            importError = nil
        } catch {
            importError = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Generous for a settings file, which exports at a few kilobytes.
    private static let maxImportBytes = 2_000_000

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json, .data]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Read the size before the contents. A settings file is a few kilobytes; there
            // is no reason to pull an arbitrarily large one into memory to discover it was
            // never going to decode, and the picker cannot stop someone choosing a disk image.
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= Self.maxImportBytes else {
                importError = "That file is too large to be a MiniNotch settings file."
                return
            }
            try settings.importData(Data(contentsOf: url))
            importError = nil
        } catch {
            importError = "That file could not be read as MiniNotch settings."
        }
    }
}
