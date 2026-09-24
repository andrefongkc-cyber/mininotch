#if DEBUG
import AppKit
import SwiftUI

/// Renders what the lock screen window draws, with the sample song, without locking the screen.
///
/// Run with `MinNotch --capture-lock-screen <out.png> [--hud]`.
///
/// Locking is the only way to see the window in place, and a tool cannot lock the screen and
/// then unlock it. This draws the same `LockScreenView` at the size the window is given, so the
/// layout can be checked: the song strip by default, the volume HUD with `--hud`.
@MainActor
enum DebugLockScreenCapture {
    static let flag = "--capture-lock-screen"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return false }
        let path = arguments.indices.contains(index + 1) ? arguments[index + 1] : NSTemporaryDirectory() + "lock-screen.png"

        let environment = DebugSupport.makeEnvironment()
        let settings = environment.settings
        environment.nowPlaying.applySample(settings: settings)
        let showsHUD = arguments.contains("--hud")
        if showsHUD {
            settings.huds.replaceVolumeHUD = true
            environment.hud.start(settings: settings)
            environment.hud.preview(.volume)
        }

        guard let screen = NSScreen.screens.first(where: \.isBuiltIn) ?? NSScreen.main else { return true }
        let geometry = NotchGeometry.make(for: screen, settings: settings)
        let size = LockScreenView.windowSize(for: geometry)

        let renderer = ImageRenderer(
            content: LockScreenView(geometry: geometry, showsHUD: showsHUD, showsMedia: true)
                .frame(width: size.width, height: size.height)
                .background(Color(white: 0.25))
                .environment(environment)
                .environment(settings)
        )
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            print("render failed")
            return true
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path), \(Int(size.width))x\(Int(size.height)) points")
        return true
    }
}
#endif
