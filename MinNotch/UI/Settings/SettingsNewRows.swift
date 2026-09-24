import Foundation

/// Which Settings rows arrived in which release, so the rows new in this one can say so.
///
/// Settings marks every row introduced in the current release with a "New" badge, and the
/// sidebar marks the panes that contain one, so someone who has just updated can find what the
/// release notes told them about without hunting. Keyed by row title, which is unique across
/// Settings (the search index depends on that too), against `ReleaseNotes.version`, so the
/// badges move on by themselves when the release notes do. `Scripts/audit-search.sh` checks
/// that every title here is still a real row: a renamed row would otherwise quietly lose its
/// badge.
///
/// When a release adds or renames a row, add it here under that release.
enum SettingsNewRows {
    static let introduced: [String: String] = [
        // 0.3
        "Arrangement": "0.3",
        "Downloads": "0.3",
        "Devices Connecting": "0.3",
        "Widgets": "0.3",
        "Top Bar": "0.3",
        "Controls": "0.3",
        "Show Which App Is Playing": "0.3",
        "Card Style": "0.3",
        "Tempo": "0.3",
        "Beats per Minute": "0.3",
        "What It Is Hearing": "0.3",
        "Show Reminders Without a Date": "0.3",

        // 0.4
        "Fix Timing Automatically": "0.4",
        "Song Shows": "0.4",
        "Sneak Peek Length": "0.4",
        "Show Lyrics When Closed": "0.4",
        "Show on the Lock Screen": "0.4",
        "Upcoming Meetings": "0.4",
        "Minutes Before": "0.4",
        "Show Output Button": "0.4",
        "Controls on the Lock Screen": "0.4",
    ]

    static func isNew(_ title: String) -> Bool {
        introduced[title] == ReleaseNotes.latest.version
    }

    /// True when a pane holds at least one new row.
    static func hasNew(_ tab: SettingsTab) -> Bool {
        SettingsSearchIndex.all.contains { $0.tab == tab && isNew($0.title) }
    }
}
