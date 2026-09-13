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
        }
    }
}
