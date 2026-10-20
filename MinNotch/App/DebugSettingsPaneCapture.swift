#if DEBUG
import AppKit
import SwiftUI

/// Draws each Settings pane on its own, in a real window, and saves it as a picture.
///
/// Run with `MiniNotch --capture-settings <dir> [--expanded] [--tab music] [--search "Timing Offset"]`.
/// `--search` points the pane at a row as a search result does, which is how a folded row opening
/// its fold is checked; it remembers that fold as open, as a real search would.
///
/// The whole Settings window cannot be captured (its sidebar comes back blank; see
/// `DebugSettingsCapture`), but a pane is a plain scroll view of cards, which `cacheDisplay`
/// draws, as it does the lock screen's lyrics. `--expanded` draws the More Options folds open,
/// without touching whether they are open in the real window.
@MainActor
enum DebugSettingsPaneCapture {
    static let flag = "--capture-settings"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return false }
        let directory = arguments.indices.contains(index + 1) ? arguments[index + 1] : NSTemporaryDirectory()
        let expanded = arguments.contains("--expanded")
        let only = arguments.firstIndex(of: "--tab").flatMap { arguments.indices.contains($0 + 1) ? SettingsTab(rawValue: arguments[$0 + 1]) : nil }

        let search = arguments.firstIndex(of: "--search").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let environment = DebugSupport.makeEnvironment()
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        for tab in only.map({ [$0] }) ?? SettingsTab.allCases {
            let size = CGSize(width: 600, height: expanded ? 3000 : 1500)
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: 0), size: size), styleMask: .borderless, backing: .buffered, defer: false)
            let host = NSHostingView(
                rootView: SettingsPanes(tab: tab)
                    .environment(\.settingsMoreOptionsForcedOpen, expanded)
                    .environment(\.settingsSearchTarget, search.map { SettingsSearchTarget(tab: tab, title: $0) })
                    .frame(width: size.width, height: size.height)
                    .environment(environment)
                    .environment(environment.settings)
            )
            window.contentView = host
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            let path = (directory as NSString).appendingPathComponent("\(tab.rawValue)\(expanded ? "-expanded" : "").png")
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            window.close()
            print("wrote \(path)")
        }
        return true
    }
}
#endif
