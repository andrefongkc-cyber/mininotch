#if DEBUG
import AppKit
import SwiftUI

/// Puts `ClockFaceDebugFrames` in a window on screen for a few seconds and prints its window
/// number, for `screencapture -l <number>`, which reads back only that window.
///
/// Run with `MiniNotch --clock-frames [seconds]`.
@MainActor
enum DebugClockFrames {
    static let flag = "--clock-frames"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        if arguments.contains("--check-flip") { checkFlip() }
        guard let index = arguments.firstIndex(of: flag) else { return false }
        let seconds = index + 1 < arguments.count ? Double(arguments[index + 1]) ?? 6 : 6

        let hosting = NSHostingView(rootView: ClockFaceDebugFrames())
        hosting.frame.size = hosting.fittingSize
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 60, y: 120), size: hosting.fittingSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.level = .floating
        window.orderFrontRegardless()
        FileHandle.standardError.write("window \(window.windowNumber)\n".data(using: .utf8)!)

        NSApplication.shared.setActivationPolicy(.accessory)
        _ = Timer.onMain(every: seconds) { exit(0) }
        NSApplication.shared.run()
        return true
    }

    /// `--check-flip`: one flip-clock card turning 5 into 6, in a real window and run loop, with
    /// what it shows recorded on every frame. A flip must go 5 whole, the new top over the old
    /// bottom, 6 whole, and nothing else: the card used to flash the 6 whole before the flap fell.
    private static func checkFlip() -> Never {
        var seen: [String] = []
        FlipDigitDebugHost.record { shown in
            if seen.last != shown { seen.append(shown) }
        }
        let hosting = NSHostingView(rootView: FlipDigitDebugHost())
        hosting.frame.size = hosting.fittingSize
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 60, y: 120), size: hosting.fittingSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        NSApplication.shared.setActivationPolicy(.accessory)
        _ = Timer.onMain(every: 1.6) {
            let passed = seen == ["55", "65", "66"]
            print("frames showed: \(seen.joined(separator: " → "))")
            print(passed ? "ok   5 turns into 6 with no flash of either" : "FAIL expected 55 → 65 → 66")
            exit(passed ? 0 : 1)
        }
        NSApplication.shared.run()
        exit(1)
    }
}
#endif
