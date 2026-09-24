#if DEBUG
import AppKit

/// Checks the private window server calls behind the lock screen HUD, without locking.
///
/// Run with `MinNotch --check-lock-screen`.
///
/// Whether the HUD really appears over the lock screen can only be seen by locking the screen,
/// which a tool cannot do and then undo. What a tool can check is everything short of that:
/// that SkyLight has the functions, that a space is created, and that a window moved into it
/// is still on screen afterwards, rather than lost somewhere no space shows. A window that
/// survives the move and sits at the space's level is the same window the lock screen draws.
@MainActor
enum DebugLockScreenCheck {
    static let flag = "--check-lock-screen"

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains(flag) else { return false }

        let space = LockScreenSpace.shared
        print("SkyLight functions: \(space.isAvailable ? "found" : "MISSING")")
        guard space.isAvailable else { return true }

        let panel = NSPanel(
            contentRect: CGRect(x: 200, y: 200, width: 120, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .black
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        let number = CGWindowID(panel.windowNumber)
        print("window \(number) before: \(describe(number))")
        let adopted = space.adopt(panel)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        print("moved into the space above the lock screen: \(adopted ? "yes" : "NO")")
        print("window \(number) after:  \(describe(number))")

        panel.close()
        return true
    }

    private static func describe(_ number: CGWindowID) -> String {
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], number) as? [[String: Any]])?.first else {
            return "not in the window list"
        }
        let onscreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? false
        let layer = info[kCGWindowLayer as String] as? Int ?? -1
        return "on screen \(onscreen), layer \(layer)"
    }
}
#endif
