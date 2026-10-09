#if DEBUG
import AppKit
import SwiftUI

/// Renders what the lock screen window draws, with the sample song, without locking the screen.
///
/// Run with `MiniNotch --capture-lock-screen <out.png> [--hud]`, or for the large player
/// `MiniNotch --capture-lock-screen <out.png> --player [--lock-layout playerRight|stacked]
/// [--lock-background none|glow|artwork] [--no-lock-lyrics] [--no-lock-card]`.
///
/// Locking is the only way to see the window in place, and a tool cannot lock the screen and
/// then unlock it. This draws the same `LockScreenView` at the size the window is given, so the
/// layout can be checked: the song strip by default, the volume HUD with `--hud`, and
/// `LockScreenPlayerView` with `--player`, over a stand-in wallpaper.
@MainActor
enum DebugLockScreenCapture {
    static let flag = "--capture-lock-screen"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return false }
        let path = arguments.indices.contains(index + 1) ? arguments[index + 1] : NSTemporaryDirectory() + "lock-screen.png"

        let environment = DebugSupport.makeEnvironment()
        let settings = environment.settings
        DebugSupport.applyNotchStyle(arguments, to: settings)
        environment.nowPlaying.applySample(settings: settings)
        let showsHUD = arguments.contains("--hud")
        if showsHUD {
            settings.huds.replaceVolumeHUD = true
            environment.hud.start(settings: settings)
            environment.hud.preview(.volume)
        }

        guard let screen = NSScreen.screens.first(where: \.isBuiltIn) ?? NSScreen.main else { return true }

        if arguments.contains("--player") {
            return capturePlayer(arguments, environment: environment, screen: screen, path: path)
        }
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

    private static func capturePlayer(_ arguments: [String], environment: AppEnvironment, screen: NSScreen, path: String) -> Bool {
        let settings = environment.settings
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        settings.media.lockScreenLayout = value(after: "--lock-layout").flatMap(LockScreenMediaLayout.init(rawValue:)) ?? .playerLeft
        settings.media.lockScreenBackground = value(after: "--lock-background").flatMap(LockScreenBackground.init(rawValue:)) ?? .glow
        settings.media.lockScreenShowsLyrics = !arguments.contains("--no-lock-lyrics")
        settings.media.lockScreenShowsPlayer = !arguments.contains("--no-lock-card")
        settings.media.showLyrics = true

        let layout = settings.media.lockScreenLayout.isPlayer ? settings.media.lockScreenLayout : .playerLeft
        let metrics = LockScreenPlayerMetrics(screen: screen, layout: layout)
        let size = metrics.windowSize
        let renderer = ImageRenderer(
            content: LockScreenPlayerView(metrics: metrics)
                .background(
                    LinearGradient(colors: [Color(red: 0.1, green: 0.12, blue: 0.3), Color(red: 0.02, green: 0.03, blue: 0.1)], startPoint: .top, endPoint: .bottom)
                )
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
        print("wrote \(path), \(Int(size.width))x\(Int(size.height)) points, layout \(layout.rawValue)")
        return true
    }
}
#endif
