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
                footer: "Macs without a physical notch are fully supported. MinNotch draws a virtual one in the same place."
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
            }

            SettingsCard(
                header: "Clipboard",
                footer: "History is kept in memory only and is never written to disk. Anything an app marks as private, which is what password managers do, is skipped."
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

            SettingsCard(
                header: "System Stats",
                footer: "Sampling only runs while the System tab is open, so nothing is measured in the background."
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
                    title: "Show Onboarding Again",
                    subtitle: "Replay the first-launch permission explanations.",
                    systemImage: "sparkles"
                ) {
                    Button("Reset") { environment.onboarding.reset() }
                        .controlSize(.small)
                }
            }
        }
        .confirmationDialog(
            "Reset all MinNotch settings?",
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
                importError = "That file is too large to be a MinNotch settings file."
                return
            }
            try settings.importData(Data(contentsOf: url))
            importError = nil
        } catch {
            importError = "That file could not be read as MinNotch settings."
        }
    }
}
