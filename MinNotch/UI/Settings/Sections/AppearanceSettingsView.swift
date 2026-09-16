import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        SettingsPane(
            title: "Appearance",
            subtitle: "MinNotch follows your Mac's light and dark appearance automatically."
        ) {
            SettingsCard(header: "Accent") {
                SettingsRow(
                    title: "Accent Color",
                    subtitle: "Used for active and selected states only.",
                    systemImage: "paintpalette"
                ) {
                    InlinePicker(selection: $settings.appearance.accentMode) {
                        ForEach(AccentMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }

                if settings.appearance.accentMode == .custom {
                    SettingsDivider()

                    SettingsRow(title: "Custom Color", systemImage: "eyedropper") {
                        ColorPicker(
                            "",
                            selection: Binding(
                                get: { settings.appearance.customAccent.color },
                                set: { settings.appearance.customAccent = RGBAColor($0) }
                            ),
                            supportsOpacity: false
                        )
                        .labelsHidden()
                    }
                }

                SettingsDivider()

                SettingsRow(
                    title: "Scrubber Color",
                    subtitle: "What tints the Now Playing progress bar.",
                    systemImage: "slider.horizontal.below.rectangle"
                ) {
                    InlinePicker(selection: $settings.appearance.sliderColor) {
                        ForEach(SliderColorStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                }
            }

            SettingsCard(
                header: "Materials",
                footer: "Solid black matches your Mac's notch exactly. Translucency makes the panel lighter than the hardware around it, which is more noticeable on a display with a physical notch."
            ) {
                SettingsRow(
                    title: "Translucent Panel",
                    subtitle: "Let the desktop tint the notch instead of filling it with solid black.",
                    systemImage: "square.stack.3d.up"
                ) {
                    SettingsToggle(isOn: $settings.appearance.useVibrancy)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Panel Shadow",
                    subtitle: "Useful on a display with no notch. On a notched Mac it shows as a halo around the panel as it opens.",
                    systemImage: "shadow"
                ) {
                    SettingsToggle(isOn: $settings.appearance.showPanelShadow)
                }
            }

            SettingsCard(header: "Panel Size") {
                SettingsRow(
                    title: "Width",
                    subtitle: "How wide the panel grows when it opens.",
                    systemImage: "arrow.left.and.right"
                ) {
                    ValueSlider(
                        value: $settings.appearance.expandedWidth,
                        range: 460...820,
                        step: 10
                    ) { "\(Int($0)) pt" }
                }

                SettingsDivider()

                SettingsRow(
                    title: "Corner Radius",
                    subtitle: "Match this to your display's physical notch for the cleanest join.",
                    systemImage: "rectangle.roundedbottom"
                ) {
                    ValueSlider(
                        value: $settings.appearance.panelCornerRadius,
                        range: 8...32,
                        step: 1
                    ) { "\(Int($0)) pt" }
                }

                SettingsDivider()

                SettingsRow(
                    title: "Top Bar",
                    subtitle: "Drag to arrange what the open panel shows either side of the notch. Anything that does not fit on its side moves to the other. Tabs can be moved but not removed; switch a feature off to hide its tab.",
                    systemImage: "rectangle.topthird.inset.filled"
                ) { EmptyView() }

                SlotLayoutEditor(
                    zones: [
                        .init(
                            id: "leading",
                            title: "Left of the notch",
                            items: shownItems($settings.appearance.topStripLeading),
                            emptyHint: "Nothing on the left"
                        ),
                        .init(
                            id: "trailing",
                            title: "Right of the notch",
                            items: shownItems($settings.appearance.topStripTrailing),
                            emptyHint: "Nothing on the right"
                        )
                    ],
                    catalogue: topBarCatalogue,
                    // Tabs and debug buttons go with their feature or setting, not with a drag.
                    canRemove: { $0.tab == nil && !$0.isDebug }
                )
                .padding(.horizontal, Metrics.cardHorizontalPadding)
                .padding(.bottom, 10)
            }

            AmbientLightingCard()

            SettingsCard(header: "Media Card") {
                SettingsRow(
                    title: "Card Style",
                    subtitle: "Only Classic is available in this version.",
                    systemImage: "rectangle.on.rectangle",
                    badge: .comingSoon
                ) {
                    InlinePicker(selection: $settings.media.cardStyle) {
                        ForEach(NowPlayingCardStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .comingSoon()
                }

                SettingsDivider()

                SettingsRow(
                    title: "Custom Visualizer",
                    subtitle: customVisualizerSubtitle,
                    systemImage: "waveform.path.ecg",
                    isEnabled: settings.media.showVisualizer
                ) {
                    HStack(spacing: 6) {
                        if settings.media.customVisualizerPath != nil {
                            Button("Clear") { settings.media.customVisualizerPath = nil }
                                .controlSize(.small)
                        }
                        Button("Choose…", action: chooseVisualizer)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    /// Tabs for features that are switched on, plus settings and battery, and the debug buttons
    /// while their setting is on.
    private var topBarCatalogue: [TopStripItem] {
        NotchWidgetRegistry.shownTabs(settings).map(TopStripItem.init)
            + [.settings, .battery]
            + (settings.advanced.showDebugButtons ? [.whatsNew, .tutorial] : [])
    }

    /// One side of the top bar with the tabs of switched-off features left out of the editor.
    ///
    /// They stay in the saved list, at the end, so switching the feature back on returns its tab
    /// to the side it was on rather than to the default.
    private func shownItems(_ items: Binding<[TopStripItem]>) -> Binding<[TopStripItem]> {
        let catalogue = topBarCatalogue
        return Binding(
            get: { items.wrappedValue.filter(catalogue.contains) },
            set: { shown in
                let hidden = items.wrappedValue.filter { !catalogue.contains($0) }
                items.wrappedValue = shown + hidden
            }
        )
    }

    private var customVisualizerSubtitle: String {
        guard let path = settings.media.customVisualizerPath else {
            return "Replace the bars with an animated image of your own. GIF and APNG animate; a still image is shown as-is."
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    /// An animated image rather than a Lottie file: `NSImageView` plays GIF and APNG with no
    /// third-party renderer, and people already have GIFs.
    private func chooseVisualizer() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.gif, .png, .image]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.media.customVisualizerPath = url.path
    }
}
