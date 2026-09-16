#if DEBUG
import AppKit
import SwiftUI

/// Captures the What's New window from a real window, scrolled to the top and to the bottom.
///
/// Run with `MinNotch --capture-whats-new <dir>`. Writes nothing to settings or defaults, so
/// looking at the window does not mark the release as seen.
@MainActor
enum DebugWhatsNewCapture {
    static let flag = "--capture-whats-new"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return false }
        let directory = arguments.indices.contains(index + 1) ? arguments[index + 1] : NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let window = WhatsNewCoordinator.makeWindow(onClose: {})
        window.setFrameOrigin(CGPoint(x: 80, y: 80))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        write(window, to: (directory as NSString).appendingPathComponent("whats-new-top.png"))

        // The window capture shows the frame and the button but not the scrolling notes, so the
        // notes are rendered on their own, at the window's width, in both appearances.
        for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
                let renderer = ImageRenderer(
                    content: WhatsNewContent(notes: .latest)
                        .background(Palette.paneBackground)
                        .environment(\.colorScheme, name == "dark" ? .dark : .light)
                )
                renderer.scale = 2
                if let image = renderer.nsImage,
                   let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    let path = (directory as NSString).appendingPathComponent("whats-new-notes-\(name).png")
                    try? png.write(to: URL(fileURLWithPath: path))
                    FileHandle.standardError.write("Captured \(path)\n".data(using: .utf8)!)
                }
            }
        }
        return true
    }

    private static func write(_ window: NSWindow, to path: String) {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        FileHandle.standardError.write("Captured \(path)\n".data(using: .utf8)!)
    }
}
#endif
