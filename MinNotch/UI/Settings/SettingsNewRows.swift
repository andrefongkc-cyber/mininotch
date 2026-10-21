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
/// When a release adds or renames a row, add it here under that release, once: a title listed
/// twice crashes the app as soon as Settings opens (a Swift dictionary literal with a repeated
/// key traps), which is what 0.7.1 shipped with. `Scripts/audit-search.sh` refuses duplicates.
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
        "Volume and Brightness": "0.4",
        "Upcoming Meetings": "0.4",
        "Minutes Before": "0.4",
        "Show Output Button": "0.4",
        "Show Weather": "0.4",
        "Temperature Units": "0.4",
        "Use My Location": "0.4",
        "City": "0.4",

        // 0.5
        "Hide Until Hovered": "0.5",
        "Show Temperatures": "0.5",
        "Show Charging Power": "0.5",

        // 0.6
        "Show Notes": "0.6",

        // 0.7
        "Check for Updates": "0.7",
        "Check Automatically": "0.7",
        "Blur Until Unlocked": "0.7",
        "Light or Dark": "0.7",
        "Background": "0.7",
        "Glass Opacity": "0.7",

        // 0.7.1, badged as 0.7.2: most people come straight from 0.7.0, past the 0.7.1 that crashed
        "Lock Screen Layout": "0.7.2",
        "Lock Screen Background": "0.7.2",
        "Background Strength": "0.7.2",
        "Show Player": "0.7.2",
        "Show Synced Lyrics": "0.7.2",
        "Size": "0.7.2",
        "Keep the Notch Still Between Desktops": "0.7.2",
        "Song on the Lock Screen": "0.7.2",
        "How Often": "0.7.2",

        // 0.7.3
        "Focus Timer": "0.7.3",

        // 0.7.4
        "New Versions": "0.7.4",
        "Apps Using the Battery": "0.7.4",

        // 0.8
        "Spotify Client ID": "0.8",
        "Spotify Account": "0.8",
        "Clock Shows": "0.8",
    ]

    static func isNew(_ title: String) -> Bool {
        introduced[title] == ReleaseNotes.latest.version
    }

    /// True when a pane holds at least one new row.
    static func hasNew(_ tab: SettingsTab) -> Bool {
        SettingsSearchIndex.all.contains { $0.tab == tab && isNew($0.title) }
    }
}
