#if DEBUG
import AppKit
import SwiftUI

/// Renders key views to PNG files and exits.
///
/// Run with `MinNotch --render-previews <directory>`. This exists because the notch is a
/// borderless overlay panel: it cannot be captured with the normal screenshot tooling
/// without granting Screen Recording, and it has no window to point a preview at. Rendering
/// offscreen gives a fast, permission-free way to review layout after a change, in both
/// appearances, without touching the running app.
///
/// Only the notch views are rendered. The Settings window is built from `NavigationSplitView`
/// and a sidebar `List`, both of which are AppKit-backed and cannot be drawn by
/// `ImageRenderer`; review that window by opening it in the running app.
@MainActor
enum DebugPreviewRenderer {
    static let flag = "--render-previews"

    /// Handles the flag if present. Returns true when the process should not continue to
    /// normal startup.
    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return false }

        let directory = arguments.indices.contains(index + 1)
            ? URL(fileURLWithPath: arguments[index + 1])
            : FileManager.default.temporaryDirectory

        render(into: directory)
        return true
    }

    private static func render(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let environment = DebugSupport.makeEnvironment()
        let settings = environment.settings

        // `ImageRenderer` cannot draw an `NSViewRepresentable`, and paints a placeholder
        // over anything containing one. Vibrancy is therefore turned off for the render,
        // which is also the code path used when Reduce Transparency is on, so the output
        // still reflects a real appearance the app ships.
        settings.appearance.useVibrancy = false
        settings.media.showLyrics = true

        environment.battery.applySampleStatus()
        environment.nowPlaying.applySample()
        environment.calendarService.applySampleItems(settings: settings)

        let geometry = NSScreen.main.map { NotchGeometry.make(for: $0, settings: settings) }
            ?? NotchGeometry(
                displayID: 0,
                screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
                hasPhysicalNotch: true,
                collapsedSize: CGSize(width: 179, height: 32),
                expandedSize: CGSize(width: 420, height: 340),
                windowFrame: CGRect(x: 495, y: 556, width: 480, height: 400)
            )

        for appearance in [NSAppearance(named: .darkAqua), NSAppearance(named: .aqua)] {
            guard let appearance else { continue }
            let suffix = appearance.name == .darkAqua ? "dark" : "light"

            // Collapsed and expanded notch, drawn over a mid-grey stand-in for the desktop
            // so the black pill and its shoulders are actually visible in the output.
            for tab in NotchTab.allCases {
                let model = NotchViewModel(settings: settings, geometry: geometry)
                model.selectedTab = tab
                model.expand()

                write(
                    notchStage(NotchRootView(viewModel: model), environment: environment, size: geometry.windowFrame.size),
                    appearance: appearance,
                    to: directory.appendingPathComponent("notch-expanded-\(tab.rawValue)-\(suffix).png")
                )
            }

            // Both closed-pill modes: seamless (exactly the hardware notch) and extended.
            for extended in [false, true] {
                settings.general.extendPillForIndicators = extended
                let collapsedModel = NotchViewModel(settings: settings, geometry: geometry)
                let name = extended ? "notch-collapsed-extended" : "notch-collapsed-seamless"
                write(
                    notchStage(NotchRootView(viewModel: collapsedModel), environment: environment, size: geometry.windowFrame.size),
                    appearance: appearance,
                    to: directory.appendingPathComponent("\(name)-\(suffix).png")
                )
            }
            settings.general.extendPillForIndicators = false

            // Clip check: force the panel narrower than its content needs. Nothing may be
            // drawn outside the black shape, which is what keeps the open and close
            // transitions from trailing pale text as the box changes size.
            let fullWidth = settings.appearance.expandedWidth
            settings.appearance.expandedWidth = 240
            let clipModel = NotchViewModel(settings: settings, geometry: geometry)
            clipModel.selectedTab = .media
            clipModel.expand()
            write(
                notchStage(NotchRootView(viewModel: clipModel), environment: environment, size: geometry.windowFrame.size),
                appearance: appearance,
                to: directory.appendingPathComponent("notch-clip-check-\(suffix).png")
            )
            settings.appearance.expandedWidth = fullWidth

        }

        FileHandle.standardError.write("Rendered previews into \(directory.path)\n".data(using: .utf8)!)
        exit(0)
    }

    /// Puts the notch view on a backdrop that is light on one side and dark on the other,
    /// so an edge artifact is visible whichever way it errs.
    private static func notchStage(
        _ view: NotchRootView,
        environment: AppEnvironment,
        size: CGSize
    ) -> AnyView {
        AnyView(
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [Color(white: 0.92), Color(white: 0.12)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                view
                    .environment(environment)
                    .environment(environment.settings)
            }
            .frame(width: size.width, height: size.height)
        )
    }

    private static func write(_ view: AnyView, appearance: NSAppearance, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2

        var image: NSImage?
        appearance.performAsCurrentDrawingAppearance {
            image = renderer.nsImage
        }

        guard let image,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write("Failed to render \(url.lastPathComponent)\n".data(using: .utf8)!)
            return
        }

        try? png.write(to: url)
    }
}
#endif
