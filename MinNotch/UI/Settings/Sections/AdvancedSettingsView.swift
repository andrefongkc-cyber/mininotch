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
