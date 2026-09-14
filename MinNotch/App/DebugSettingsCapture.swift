#if DEBUG
import AppKit

/// Prints what a Settings search matches, in ranked order.
///
/// Run with `MinNotch --check-settings-search pomodoro`.
///
/// Text rather than a screenshot on purpose. The Settings window cannot be captured here:
/// `NavigationSplitView` and the sidebar's material come back as an empty white rectangle
/// from both `ImageRenderer` and `cacheDisplay`, so an image check would pass while showing
/// nothing. The ranking is the part that can be wrong in a way that looks fine by eye, so it
/// is the part worth checking: a search whose obvious answer is not near the top is broken
/// even when the list renders.
@MainActor
enum DebugSettingsCapture {
    static let flag = "--check-settings-search"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return false }

        let queries = Array(arguments.dropFirst(index + 1)).filter { !$0.hasPrefix("--") }
        guard !queries.isEmpty else {
            report("usage: --check-settings-search <query> [<query> ...]")
            exit(1)
        }

        report("\(SettingsSearchIndex.all.count) searchable rows")
        for query in queries {
            let tabs = SettingsTab.allCases.filter { $0.matchesSearch(query) }
            let matches = SettingsSearchIndex.matches(query)
            report("")
            report("\"\(query)\": \(tabs.count) panes, \(matches.count) rows")
            for tab in tabs { report("  pane   \(tab.title)") }
            for entry in matches.prefix(6) {
                let pane = entry.tab.title.padding(toLength: 11, withPad: " ", startingAt: 0)
                report("  row    \(pane) \(entry.title)")
            }
        }
        exit(0)
    }

    private static func report(_ message: String) {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    }
}
#endif
