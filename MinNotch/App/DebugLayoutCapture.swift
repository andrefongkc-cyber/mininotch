#if DEBUG
import AppKit
import SwiftUI

/// Renders the Layout pane's editors to images, in both appearances.
///
/// Run with `MinNotch --capture-layout <dir> [--width 460]`.
///
/// The Settings window itself cannot be captured (its split view comes back blank), so the
/// editors are rendered on their own at the width a card gives them, over the card background.
/// They are plain shapes, images and text for exactly this reason. Nothing is written to the
/// real settings: the store is the throwaway one every debug tool uses.
@MainActor
enum DebugLayoutCapture {
    static let flag = "--capture-layout"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return false }
        let directory = arguments.indices.contains(index + 1) ? arguments[index + 1] : NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        var width: CGFloat = 460
        if let i = arguments.firstIndex(of: "--width"), arguments.indices.contains(i + 1),
           let value = Double(arguments[i + 1]) {
            width = value
        }

        LayoutEditorRendering.isStatic = true
        let environment = DebugSupport.makeEnvironment()
        let settings = environment.settings
        // Something in every tray, so the capture shows one.
        settings.general.extendPillForIndicators = true
        settings.general.pillLeading = [.artwork, .song]
        settings.general.pillTrailing = [.playing, .battery]
        settings.media.controlOrder = [.shuffle, .previous, .playPause, .next]
        settings.advanced.showDebugButtons = false
        // The sample song and battery, so the live miniature has something real to draw.
        environment.battery.applySampleStatus()
        environment.nowPlaying.applySample(settings: settings)

        let pages: [(String, AnyView)] = [
            ("pill", AnyView(IconLayoutEditor(
                surface: .closedPill,
                leading: binding(settings, \.general.pillLeading),
                trailing: binding(settings, \.general.pillTrailing),
                catalogue: PillIndicator.allCases
            ))),
            // What Settings draws: the pill's own indicators from the sample track, not symbols.
            ("pill-live", AnyView(IconLayoutEditor(
                surface: .closedPill,
                leading: binding(settings, \.general.pillLeading),
                trailing: binding(settings, \.general.pillTrailing),
                catalogue: PillIndicator.allCases,
                livePreview: { indicator in
                    let pill = CollapsedPillContent.live(environment: environment, settings: settings, isExtended: true)
                    guard pill.hasContent(indicator) else { return nil }
                    return AnyView(PillIndicatorView(indicator: indicator, content: pill))
                }
            ))),
            ("pill-off", AnyView(IconLayoutEditor(
                surface: .closedPill,
                leading: binding(settings, \.general.pillLeading),
                trailing: binding(settings, \.general.pillTrailing),
                catalogue: PillIndicator.allCases,
                inactiveCaption: "Indicators are off, so the closed pill shows nothing"
            ))),
            ("widgets", AnyView(WidgetTiles())),
            ("topbar", AnyView(IconLayoutEditor(
                surface: .topBar,
                leading: binding(settings, \.appearance.topStripLeading),
                trailing: binding(settings, \.appearance.topStripTrailing),
                catalogue: NotchWidgetRegistry.shownTabs(settings).map(TopStripItem.init) + [.settings, .battery],
                canRemove: { $0.tab == nil && !$0.isDebug }
            ))),
            ("controls", AnyView(IconLayoutEditor(
                surface: .controls,
                leading: binding(settings, \.media.controlOrder),
                trailing: nil,
                catalogue: MediaControl.allCases,
                isProminent: { $0 == .playPause }
            )))
        ]

        for (name, view) in pages {
            for (suffix, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
                    let renderer = ImageRenderer(
                        content: view
                            .frame(width: width)
                            .padding(14)
                            .background(Palette.cardBackground)
                            .environment(settings)
                            .environment(environment)
                            .environment(\.colorScheme, suffix == "dark" ? .dark : .light)
                    )
                    renderer.scale = 2
                    if let image = renderer.nsImage,
                       let tiff = image.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        let path = (directory as NSString).appendingPathComponent("layout-\(name)-\(suffix).png")
                        try? png.write(to: URL(fileURLWithPath: path))
                        FileHandle.standardError.write("Captured \(path)\n".data(using: .utf8)!)
                    }
                }
            }
        }
        return true
    }

    private static func binding<Value>(_ settings: SettingsStore, _ path: ReferenceWritableKeyPath<SettingsStore, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: path] }, set: { settings[keyPath: path] = $0 })
    }
}
#endif
