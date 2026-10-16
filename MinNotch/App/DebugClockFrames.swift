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
}
#endif
