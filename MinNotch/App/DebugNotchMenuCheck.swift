#if DEBUG
import AppKit

/// Whether a menu opened over a window in the notch's own space (`NotchSpace`) can be seen.
///
/// Run with `MiniNotch --check-notch-menu out.png [--no-space]`. It puts a red window on the left
/// of the main screen, into the notch's space unless `--no-space`, opens a menu over it, and
/// captures exactly that window's rectangle with `screencapture -R`, so nothing else on screen is
/// in the picture. Red all over means the menu was hidden under the window. It is (2026-10-19),
/// which is why the notch draws its own menus (`NotchMenuOverlay`); moving the menu's window into
/// the notch's space by its window number did not show it either.
@MainActor
enum DebugNotchMenuCheck {
    static let flag = "--check-notch-menu"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return false }
        let output = arguments[index + 1]
        guard let screen = NSScreen.main else { exit(1) }

        NSApplication.shared.setActivationPolicy(.accessory)
        let frame = CGRect(x: screen.frame.minX + 80, y: screen.frame.midY - 100, width: 320, height: 200)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .systemRed
        window.level = .statusBar
        window.orderFrontRegardless()
        if !arguments.contains("--no-space") { NotchSpace.shared.pin(window) }

        // Top-left screen coordinates, as screencapture wants them.
        let top = (NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY) - frame.maxY
        let region = "\(Int(frame.minX)),\(Int(top)),\(Int(frame.width)),\(Int(frame.height))"

        let menu = NSMenu()
        for title in ["What's New", "Tutorial", "A third item"] {
            menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        }
        // While the menu tracks, capture the window's rectangle, then close the menu. The timer
        // fires on the main run loop, in the menu's tracking mode.
        nonisolated(unsafe) let tracked = menu
        let capture = Timer(timeInterval: 1.0, repeats: false) { _ in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-R", region, output]
            try? process.run()
            process.waitUntilExit()
            MainActor.assumeIsolated { tracked.cancelTracking() }
        }
        RunLoop.main.add(capture, forMode: .common)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        menu.popUp(positioning: nil, at: CGPoint(x: frame.minX + 40, y: frame.maxY - 30), in: nil)
        print("captured \(region) to \(output)")
        exit(0)
    }
}
#endif
