import SwiftUI

/// Settings > Shelf.
struct ShelfSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    private var isBuilt: Bool { FeatureFlag.shelf.isEnabled }

    var body: some View {
        @Bindable var settings = settings

        SettingsPane(
            title: "Shelf",
            subtitle: "A drop zone in the notch for files on their way somewhere else."
        ) {
            SettingsCard(header: "Shelf") {
                SettingsRow(title: "Enable Shelf", systemImage: "tray.full") {
                    SettingsToggle(isOn: $settings.shelf.enabled)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Dragging Out",
                    subtitle: "What the drag advertises. Move makes the destination move the original file; Ask lets the modifier keys decide.",
                    systemImage: "arrow.up.doc"
                ) {
                    InlinePicker(selection: $settings.shelf.dropBehavior) {
                        ForEach(ShelfDropBehavior.allCases) { behavior in
                            Text(behavior.title).tag(behavior)
                        }
                    }
                    
                }

                SettingsDivider()

                SettingsRow(
                    title: "Open on Drag",
                    subtitle: "Expand the notch when you drag a file over it.",
                    systemImage: "hand.draw"
                ) {
                    SettingsToggle(isOn: $settings.shelf.expandOnDragEnter)
                }
            }

            SettingsCard(header: "Storage") {
                SettingsRow(
                    title: "Item Limit",
                    subtitle: "The oldest item is dropped once the shelf is full.",
                    systemImage: "square.stack"
                ) {
                    ValueSlider(
                        value: Binding(
                            get: { Double(settings.shelf.maxItems) },
                            set: { settings.shelf.maxItems = Int($0) }
                        ),
                        range: 4...40,
                        step: 1
                    ) { "\(Int($0))" }
                    
                }

                SettingsDivider()

                SettingsRow(title: "Clear on Quit", systemImage: "trash") {
                    SettingsToggle(isOn: $settings.shelf.clearOnQuit)
                }
            }

            SettingsCard(
                header: "Link Shelf",
                footer: "Each link's title and icon are read from the site itself when you add it, which means a request to that site. Links are kept between launches."
            ) {
                SettingsRow(
                    title: "Link Shelf",
                    subtitle: "Keep links on the notch, in the Shelf tab under any files. Opening one uses your default browser.",
                    systemImage: "link"
                ) {
                    SettingsToggle(isOn: $settings.advanced.linkShelfEnabled)
                }

                SettingsDivider()

                SettingsRow(
                    title: "Links Kept",
                    subtitle: "The oldest link is dropped once the shelf is full.",
                    systemImage: "list.bullet",
                    isEnabled: settings.advanced.linkShelfEnabled
                ) {
                    ValueSlider(
                        value: Binding(
                            get: { Double(settings.advanced.linkShelfLimit) },
                            set: { settings.advanced.linkShelfLimit = Int($0) }
                        ),
                        range: 5...100,
                        step: 5
                    ) { "\(Int($0))" }
                }
            }
        }
    }
}
