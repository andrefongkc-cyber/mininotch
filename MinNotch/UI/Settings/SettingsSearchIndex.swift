import SwiftUI

/// One row somewhere in Settings, as far as search is concerned.
struct SettingsSearchEntry: Identifiable, Hashable {
    let tab: SettingsTab
    /// The header of the card the row sits in. Searched, because it is often the word people
    /// actually have in mind: "Pomodoro" appears in no row's title, only above the rows.
    let section: String
    let title: String
    let subtitle: String
    let symbolName: String

    var id: String { "\(tab.rawValue)/\(section)/\(title)" }
}

/// Everything Settings can be searched for.
///
/// A flat list rather than something derived from the panes, because SwiftUI offers no way to
/// walk a view tree and ask what rows it contains. That means this can drift from the panes,
/// so it is generated from them rather than typed, and there is an audit in CLAUDE.md under
/// "Settings search" that reports any row present in a pane and missing from here. Run it
/// after adding a row.
enum SettingsSearchIndex {
    static let all: [SettingsSearchEntry] = [
        .init(tab: .general, section: "Startup", title: "Launch at Login", subtitle: "Start MinNotch automatically when you log in.", symbolName: "power"),
        .init(tab: .general, section: "Startup", title: "Show Menu Bar Icon", subtitle: "Turn this off to run from the notch alone. The keyboard shortcut keeps working either way.", symbolName: "menubar.rectangle"),
        .init(tab: .general, section: "Opening the Notch", title: "Open on Hover", subtitle: "Expand the panel when the pointer rests over the notch.", symbolName: "cursorarrow"),
        .init(tab: .general, section: "Opening the Notch", title: "Hover Delay", subtitle: "How long the pointer has to rest before the panel opens.", symbolName: "clock"),
        .init(tab: .general, section: "Opening the Notch", title: "Open on Click", subtitle: "Click the pill to expand it.", symbolName: "hand.tap"),
        .init(tab: .general, section: "Opening the Notch", title: "Close When the Pointer Leaves", subtitle: "", symbolName: "arrow.up.left.and.arrow.down.right"),
        .init(tab: .general, section: "Tabs", title: "Remember Last Tab", subtitle: "Reopen on whichever widget you used last.", symbolName: "arrow.uturn.backward"),
        .init(tab: .general, section: "Tabs", title: "Default Tab", subtitle: "", symbolName: "square.grid.2x2"),
        .init(tab: .general, section: "Permissions", title: "Login Items", subtitle: "Review which apps macOS allows to start at login.", symbolName: "list.bullet.rectangle"),
        .init(tab: .appearance, section: "Accent", title: "Accent Color", subtitle: "Used for active and selected states only.", symbolName: "paintpalette"),
        .init(tab: .appearance, section: "Accent", title: "Custom Color", subtitle: "", symbolName: "eyedropper"),
        .init(tab: .appearance, section: "Accent", title: "Scrubber Color", subtitle: "What tints the Now Playing progress bar.", symbolName: "slider.horizontal.below.rectangle"),
        .init(tab: .appearance, section: "Materials", title: "Translucent Panel", subtitle: "Let the desktop tint the notch instead of filling it with solid black.", symbolName: "square.stack.3d.up"),
        .init(tab: .appearance, section: "Materials", title: "Panel Shadow", subtitle: "Useful on a display with no notch. On a notched Mac it shows as a halo around the panel as it opens.", symbolName: "shadow"),
        .init(tab: .appearance, section: "Panel Size", title: "Width", subtitle: "How wide the panel grows when it opens.", symbolName: "arrow.left.and.right"),
        .init(tab: .appearance, section: "Panel Size", title: "Corner Radius", subtitle: "Match this to your display's physical notch for the cleanest join.", symbolName: "rectangle.roundedbottom"),
        .init(tab: .appearance, section: "Media Card", title: "Card Style", subtitle: "Classic, Compact, or Full Artwork.", symbolName: "rectangle.on.rectangle"),
        .init(tab: .appearance, section: "Media Card", title: "Custom Visualizer", subtitle: "", symbolName: "waveform.path.ecg"),
        .init(tab: .layout, section: "Closed Pill", title: "Show Indicators When Closed", subtitle: "Widen the pill either side of the notch to show battery and what is playing.", symbolName: "rectangle.expand.vertical"),
        .init(tab: .layout, section: "Closed Pill", title: "Arrangement", subtitle: "What the closed pill shows either side of the notch. Album art and the song appear while a song is loaded, the playing indicator only while it plays, and a live activity is a timer, a download or a device connecting.", symbolName: "rectangle.split.3x1"),
        .init(tab: .layout, section: "Closed Pill", title: "Song Shows", subtitle: "What the Song in the closed pill says. Long names are cut short.", symbolName: "textformat"),
        .init(tab: .layout, section: "Live Activities", title: "Downloads", subtitle: "Show how far along a download is, from Safari, Chrome, Firefox and most other browsers. Reads your Downloads folder.", symbolName: "arrow.down.circle"),
        .init(tab: .layout, section: "Live Activities", title: "Devices Connecting", subtitle: "Show the charge of AirPods and other accessories for a few seconds when they connect.", symbolName: "airpodspro"),
        .init(tab: .layout, section: "Live Activities", title: "Upcoming Meetings", subtitle: "Count down to your next calendar event. Zoom, Meet, Teams, Webex and FaceTime links get a Join button in the Calendar tab.", symbolName: "video"),
        .init(tab: .layout, section: "Live Activities", title: "Minutes Before", subtitle: "How long before a meeting the countdown appears.", symbolName: "clock.badge"),
        .init(tab: .layout, section: "Open Panel", title: "Widgets", subtitle: "Click to switch a widget on or off. Each one that is on gets a tab in the top bar.", symbolName: "square.grid.2x2"),
        .init(tab: .layout, section: "Open Panel", title: "Top Bar", subtitle: "What the open panel shows either side of the notch.", symbolName: "rectangle.topthird.inset.filled"),
        .init(tab: .layout, section: "Now Playing Controls", title: "Controls", subtitle: "The buttons under the scrubber, left to right.", symbolName: "playpause"),
        .init(tab: .media, section: "Source", title: "Show Now Playing", subtitle: "", symbolName: "music.note"),
        .init(tab: .media, section: "Source", title: "Player", subtitle: "Automatic follows whichever supported player is active.", symbolName: "app.badge"),
        .init(tab: .media, section: "Source", title: "System Now Playing", subtitle: "", symbolName: "waveform"),
        .init(tab: .media, section: "Source", title: "Automation Permission", subtitle: "macOS is blocking MinNotch from controlling Music and Spotify.", symbolName: "exclamationmark.triangle"),
        .init(tab: .media, section: "Lyrics", title: "Show Lyrics", subtitle: "Display the current line under the track info when lyrics are available.", symbolName: "quote.bubble"),
        .init(tab: .media, section: "Lyrics", title: "Show Lyrics When Closed", subtitle: "The line being sung, under the closed notch, while a song with synced lyrics plays.", symbolName: "text.below.photo"),
        .init(tab: .media, section: "Lyrics", title: "Timing Offset", subtitle: "Shift lyrics earlier or later. Lyric files are timed by hand and disagree between sources.", symbolName: "timer"),
        .init(tab: .media, section: "Lyrics", title: "Use Audio Clock", subtitle: "", symbolName: "waveform.badge.magnifyingglass"),
        .init(tab: .media, section: "Lyrics", title: "Fix Timing Automatically", subtitle: "For lyrics that run early or late: listens for where the singing starts and moves the lyrics to match. Lyrics only; the glow's Follow the Beat is separate. Uses the system audio permission.", symbolName: "waveform.and.person.filled"),
        .init(tab: .media, section: "Lyrics", title: "Lyrics Source", subtitle: "Where to look when your player has no lyrics stored.", symbolName: "magnifyingglass"),
        .init(tab: .media, section: "Display", title: "Floating Window", subtitle: "Also show Now Playing in a small window above other apps. Drag it anywhere; it remembers where you put it. The pop-out button on the Now Playing card does the same.", symbolName: "macwindow.on.rectangle"),
        .init(tab: .media, section: "Display", title: "Sneak Peek on Track Change", subtitle: "When a new song starts, the closed notch drops down for a moment to show what it is.", symbolName: "rectangle.expand.vertical"),
        .init(tab: .media, section: "Display", title: "Sneak Peek Length", subtitle: "How long the song stays on screen after it changes.", symbolName: "timer"),
        .init(tab: .media, section: "Display", title: "Show Up Next", subtitle: "Off for now. Music tells other apps a playlist is shuffling when it is playing in order, so the list was wrong too often to be worth showing.", symbolName: "text.line.first.and.arrowtriangle.forward"),
        .init(tab: .media, section: "Display", title: "Show Elapsed and Remaining Time", subtitle: "", symbolName: "clock"),
        .init(tab: .media, section: "Display", title: "Show Which App Is Playing", subtitle: "A small icon of the app on the corner of the artwork.", symbolName: "app.badge"),
        .init(tab: .media, section: "Display", title: "Tint From Artwork", subtitle: "Wash the panel with the album's dominant colour.", symbolName: "photo"),
        .init(tab: .media, section: "Display", title: "Refresh Interval", subtitle: "How often the position is re-read. Track changes update instantly regardless.", symbolName: "arrow.clockwise"),
        .init(tab: .media, section: "Visualizer", title: "Show Visualizer", subtitle: "Animated bars over the artwork, coloured from the album.", symbolName: "waveform.path"),
        .init(tab: .calendar, section: "Access", title: "Calendar Access", subtitle: "", symbolName: "lock"),
        .init(tab: .calendar, section: "Widget", title: "Show Calendar", subtitle: "", symbolName: "calendar"),
        .init(tab: .calendar, section: "Widget", title: "Grid", subtitle: "Show the current week or the whole month.", symbolName: "square.grid.3x3"),
        .init(tab: .calendar, section: "Widget", title: "Start Week on Monday", subtitle: "Otherwise MinNotch follows your region's first weekday.", symbolName: "calendar.day.timeline.left"),
        .init(tab: .calendar, section: "Events", title: "Show All-Day Events", subtitle: "", symbolName: "sun.max"),
        .init(tab: .calendar, section: "Events", title: "Look Ahead", subtitle: "How far into the future the upcoming list reaches.", symbolName: "arrow.forward.to.line"),
        .init(tab: .calendar, section: "Events", title: "Rows Shown", subtitle: "Anything beyond this scrolls inside the panel.", symbolName: "list.bullet"),
        .init(tab: .calendar, section: "Reminders", title: "Show Reminders", subtitle: "Mix reminders that are due into the upcoming list.", symbolName: "checklist"),
        .init(tab: .calendar, section: "Reminders", title: "Hide Completed Reminders", subtitle: "", symbolName: "checkmark.circle"),
        .init(tab: .calendar, section: "Reminders", title: "Show Reminders Without a Date", subtitle: "List them after everything that is due.", symbolName: "tray"),
        .init(tab: .calendar, section: "Reminders", title: "Reminders Access", subtitle: "MinNotch needs permission before it can show your reminders.", symbolName: "lock"),
        .init(tab: .calendar, section: "Quick Add", title: "Quick Add Field", subtitle: "Create an event or reminder straight from the notch.", symbolName: "plus.circle"),
        .init(tab: .huds, section: "Show in the Notch", title: "Volume", subtitle: "Updates the moment the level changes, with no polling.", symbolName: "speaker.wave.2"),
        .init(tab: .huds, section: "Show in the Notch", title: "Brightness", subtitle: "", symbolName: "sun.max"),
        .init(tab: .huds, section: "Show in the Notch", title: "Keyboard Backlight", subtitle: "", symbolName: "keyboard"),
        .init(tab: .huds, section: "System Overlay", title: "Hide the System Overlay", subtitle: "Show only MinNotch's volume and brightness indicator instead of both. Works for whichever of those two is switched on above.", symbolName: "rectangle.slash"),
        .init(tab: .huds, section: "System Overlay", title: "Accessibility Access Needed", subtitle: "Turn on MinNotch in Privacy & Security > Accessibility. Until then Apple's overlay still appears. After installing a new copy of MinNotch, remove it from the list and add it again.", symbolName: "exclamationmark.triangle"),
        .init(tab: .huds, section: "Presentation", title: "Show on the Lock Screen", subtitle: "Volume and brightness over the lock screen too. Uses a private part of macOS, so a future version may stop it working.", symbolName: "lock.display"),
        .init(tab: .huds, section: "Presentation", title: "Style", subtitle: "", symbolName: "rectangle.on.rectangle"),
        .init(tab: .huds, section: "Presentation", title: "Dismiss After", subtitle: "How long the indicator stays on screen after the last change.", symbolName: "timer"),
        .init(tab: .huds, section: "Presentation", title: "Show Numeric Value", subtitle: "", symbolName: "number"),
        .init(tab: .huds, section: "Presentation", title: "Preview", subtitle: "Show an indicator now, so you can see the style without reaching for a key.", symbolName: "eye"),
        .init(tab: .battery, section: "In the Notch", title: "Show Percentage", subtitle: "Otherwise only the battery glyph is shown. Whether the battery appears at all, and where, is arranged in General and Appearance.", symbolName: "percent"),
        .init(tab: .battery, section: "In the Notch", title: "Show Time Remaining", subtitle: "In the expanded System panel.", symbolName: "clock.arrow.circlepath"),
        .init(tab: .battery, section: "Notifications", title: "Low Battery Alert", subtitle: "", symbolName: "exclamationmark.triangle"),
        .init(tab: .battery, section: "Notifications", title: "Alert Threshold", subtitle: "Notify once the charge drops to this level.", symbolName: "gauge.with.dots.needle.33percent"),
        .init(tab: .battery, section: "Notifications", title: "Power Adapter Alerts", subtitle: "Notify when the charger is connected or removed.", symbolName: "powerplug"),
        .init(tab: .battery, section: "Accessories", title: "AirPods and Bluetooth Battery", subtitle: "Show connected accessory charge in the System tab.", symbolName: "airpodspro"),
        .init(tab: .shelf, section: "Shelf", title: "Enable Shelf", subtitle: "", symbolName: "tray.full"),
        .init(tab: .shelf, section: "Shelf", title: "Dragging Out", subtitle: "What the drag advertises. Move makes the destination move the original file; Ask lets the modifier keys decide.", symbolName: "arrow.up.doc"),
        .init(tab: .shelf, section: "Shelf", title: "Open on Drag", subtitle: "Expand the notch when you drag a file over it.", symbolName: "hand.draw"),
        .init(tab: .shelf, section: "Storage", title: "Item Limit", subtitle: "The oldest item is dropped once the shelf is full.", symbolName: "square.stack"),
        .init(tab: .shelf, section: "Storage", title: "Clear on Quit", subtitle: "", symbolName: "trash"),
        .init(tab: .timer, section: "Timer", title: "Enable Timer", subtitle: "Adds the Timer tab, and shows a running countdown in the closed pill.", symbolName: "timer"),
        .init(tab: .timer, section: "Timer", title: "Countdown Length", subtitle: "Where a plain countdown starts. The Timer tab also offers a few quick lengths.", symbolName: "clock"),
        .init(tab: .timer, section: "Timer", title: "Notify on Completion", subtitle: "Post a notification when an interval ends. The first one asks for permission.", symbolName: "bell"),
        .init(tab: .timer, section: "Pomodoro", title: "Rhythm", subtitle: "", symbolName: "metronome"),
        .init(tab: .timer, section: "Pomodoro", title: "Focus Length", subtitle: "", symbolName: "brain.head.profile"),
        .init(tab: .timer, section: "Pomodoro", title: "Break Length", subtitle: "", symbolName: "cup.and.saucer"),
        .init(tab: .timer, section: "Pomodoro", title: "Long Break Length", subtitle: "", symbolName: "figure.walk"),
        .init(tab: .timer, section: "Pomodoro", title: "Intervals Before a Long Break", subtitle: "", symbolName: "repeat"),
        .init(tab: .timer, section: "Pomodoro", title: "Start the Next Interval Automatically", subtitle: "Off means each interval waits for you. On is the point of the technique: it keeps going while you are concentrating.", symbolName: "play.circle"),
        .init(tab: .shortcuts, section: "Global Shortcuts", title: "Enable Global Shortcuts", subtitle: "Turn this off to silence every shortcut without losing what you recorded.", symbolName: "command"),
        .init(tab: .advanced, section: "Displays", title: "Show on Displays Without a Notch", subtitle: "", symbolName: "display.2"),
        .init(tab: .advanced, section: "Displays", title: "Show On", subtitle: "Which display carries the notch when several are connected.", symbolName: "rectangle.on.rectangle"),
        .init(tab: .advanced, section: "Displays", title: "Opens On Without a Notch", subtitle: "Which tab a virtual notch starts on. A real notch hides behind the camera housing; one on an external monitor does not, so it may as well be showing something.", symbolName: "rectangle.topthird.inset.filled"),
        .init(tab: .advanced, section: "Link Shelf", title: "Link Shelf", subtitle: "Keep links on the notch in a Links tab. Opening one uses your default browser.", symbolName: "link"),
        .init(tab: .advanced, section: "Link Shelf", title: "Links Kept", subtitle: "The oldest link is dropped once the shelf is full.", symbolName: "list.bullet"),
        .init(tab: .advanced, section: "Clipboard", title: "Clipboard History", subtitle: "Remember what you copy and offer it back from the Clipboard tab.", symbolName: "doc.on.clipboard"),
        .init(tab: .advanced, section: "Clipboard", title: "Items Kept", subtitle: "The oldest is dropped once the history is full. Pinned items do not count towards this.", symbolName: "list.bullet"),
        .init(tab: .advanced, section: "Size", title: "Height", subtitle: "Match the hardware cutout, or pin a fixed height everywhere.", symbolName: "arrow.up.and.down"),
        .init(tab: .advanced, section: "Size", title: "Virtual Notch Height", subtitle: "Used on displays with no physical notch.", symbolName: "ruler"),
        .init(tab: .advanced, section: "Size", title: "Virtual Notch Width", subtitle: "", symbolName: "ruler"),
        .init(tab: .advanced, section: "System Stats", title: "Show CPU, GPU, Memory and Network", subtitle: "In the System tab of the notch.", symbolName: "gauge.with.dots.needle.33percent"),
        .init(tab: .advanced, section: "System Stats", title: "Refresh Interval", subtitle: "How often the readout updates while it is on screen.", symbolName: "arrow.clockwise"),
        .init(tab: .advanced, section: "Interaction", title: "Two-Finger Gestures", subtitle: "Swipe sideways over the notch to change tab, or up and down to close and open it.", symbolName: "hand.draw"),
        .init(tab: .advanced, section: "Interaction", title: "Gesture Sensitivity", subtitle: "", symbolName: "dial.medium"),
        .init(tab: .advanced, section: "Interaction", title: "Reverse Swipe Direction", subtitle: "Swap which way a sideways swipe moves through the tabs.", symbolName: "arrow.left.arrow.right"),
        .init(tab: .advanced, section: "Interaction", title: "Haptic Feedback", subtitle: "A small tap from the trackpad when the notch opens, closes, or changes tab. Force Touch trackpads only.", symbolName: "hand.tap"),
        .init(tab: .advanced, section: "Settings File", title: "Export Settings", subtitle: "Save every preference to a single file.", symbolName: "square.and.arrow.up"),
        .init(tab: .advanced, section: "Settings File", title: "Import Settings", subtitle: "", symbolName: "square.and.arrow.down"),
        .init(tab: .advanced, section: "Settings File", title: "Reset All Settings", subtitle: "Return every preference to its default.", symbolName: "arrow.counterclockwise"),
        .init(tab: .advanced, section: "Diagnostics", title: "Show Layout Overlay", subtitle: "Outline the notch's interactive area to debug placement.", symbolName: "square.dashed"),
        .init(tab: .advanced, section: "Diagnostics", title: "Debug Buttons in Top Bar", subtitle: "Add What's New and Tutorial buttons to the open notch's top bar, to check both quickly. On by default only in Debug builds.", symbolName: "ladybug"),
        .init(tab: .advanced, section: "Diagnostics", title: "Show Welcome Again", subtitle: "Open the first-launch tutorial again. Its checklist starts from what is switched on now, so nothing changes unless you change it.", symbolName: "sparkles"),
        .init(tab: .about, section: "What's New", title: "Release Notes", subtitle: "What changed in this version, and where to find it. Also shown once after each update.", symbolName: "sparkles"),
        .init(tab: .about, section: "System", title: "macOS", subtitle: "", symbolName: "desktopcomputer"),
        .init(tab: .about, section: "System", title: "Displays", subtitle: "", symbolName: "display"),
        .init(tab: .about, section: "MinNotch", title: "Quit MinNotch", subtitle: "The notch and the menu bar icon both disappear until you launch it again.", symbolName: "power"),
        .init(tab: .appearance, section: "Ambient Lighting", title: "Enable Ambient Glow", subtitle: "The Now Playing card cycles this with the visualizer, and its menu switches style.", symbolName: "light.beacon.max"),
        .init(tab: .appearance, section: "Ambient Lighting", title: "Style", subtitle: "", symbolName: "sparkles"),
        .init(tab: .appearance, section: "Ambient Lighting", title: "Color", subtitle: "", symbolName: "paintpalette"),
        .init(tab: .appearance, section: "Ambient Lighting", title: "Static Color", subtitle: "", symbolName: "eyedropper"),
        .init(tab: .appearance, section: "Ambient Lighting", title: "Where It Shows", subtitle: "Any combination. Only the one currently on screen is drawn.", symbolName: "square.on.square"),
        .init(tab: .appearance, section: "Ambient Lighting", title: "Intensity", subtitle: "", symbolName: "sun.max"),
        .init(tab: .appearance, section: "Ambient Lighting", title: "Speed", subtitle: "", symbolName: "hare"),
        .init(tab: .appearance, section: "Ambient Lighting", title: "Tempo", subtitle: "Used while the glow is not following the beat: the Speed slider, a tempo set by hand or tapped, or the song's own BPM.", symbolName: "metronome"),
        .init(tab: .appearance, section: "Ambient Lighting", title: "Beats per Minute", subtitle: "Or tap along to the music; the beats then land on your taps.", symbolName: "hand.tap"),
        .init(tab: .appearance, section: "Ambient Lighting", title: "Glow Radius", subtitle: "Capped automatically on the closed pill, which is too thin to take a wide blur.", symbolName: "circle.dashed"),
        .init(tab: .appearance, section: "Ambient Lighting", title: "Follow the Beat", subtitle: "Analyse what is playing so the light tracks the music instead of animating on its own.", symbolName: "waveform.badge.magnifyingglass"),
        .init(tab: .appearance, section: "Ambient Lighting", title: "What It Is Hearing", subtitle: "Live, from the system audio. Play something and these move; in silence they stay down.", symbolName: "waveform"),
        .init(tab: .appearance, section: "Ambient Lighting", title: "Try Again", subtitle: "Ask for the system audio permission once more.", symbolName: "arrow.clockwise"),
        .init(tab: .appearance, section: "Ambient Lighting", title: "Pause in Low Power Mode", subtitle: "", symbolName: "battery.25percent"),
    ]

    /// Rows matching `query`, best first.
    ///
    /// Ranked rather than merely filtered: someone typing "lyr" wants the Lyrics rows above a
    /// row whose subtitle mentions lyrics in passing, and an unranked substring match buries
    /// the obvious answer under the incidental ones.
    static func matches(_ query: String) -> [SettingsSearchEntry] {
        let needle = fold(query).trimmingCharacters(in: .whitespaces)
        // One letter matches most of the list, which is noise rather than a search.
        guard needle.count >= 2 else { return [] }

        return all.compactMap { entry -> (SettingsSearchEntry, Int)? in
            guard let rank = rank(of: entry, matching: needle) else { return nil }
            return (entry, rank)
        }
        .sorted { $0.1 == $1.1 ? $0.0.title < $1.0.title : $0.1 < $1.1 }
        .map(\.0)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    /// True when any word in `text` starts with `needle`. "glow" should find "Enable Ambient
    /// Glow" as readily as "Glow Radius"; ranking only whole-title prefixes above it put the
    /// less important row first on a technicality.
    static func hasWordPrefix(_ text: String, _ needle: String) -> Bool {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains { $0.hasPrefix(needle) }
    }

    /// Lower is better. Nil when nothing about the entry matches.
    private static func rank(of entry: SettingsSearchEntry, matching needle: String) -> Int? {
        let title = fold(entry.title)
        if hasWordPrefix(title, needle) { return 0 }
        if title.contains(needle) { return 1 }
        if fold(entry.section).contains(needle) { return 2 }
        if fold(entry.subtitle).contains(needle) { return 3 }
        // Deliberately not the pane's name or its keywords. Those match every row in the
        // pane at once, so "monitor" returned all nineteen Advanced rows alphabetically and
        // the display ones were buried under Clipboard History. A pane-level match is offered
        // as the pane itself, above the rows, which is where it is useful.
        return nil
    }
}

extension SettingsTab {
    /// Words someone might type for this pane that are not its name.
    var searchKeywords: [String] {
        switch self {
        case .general: return ["startup", "login", "hover", "click", "menu bar"]
        case .appearance: return ["theme", "look", "colour", "color", "glow", "lighting", "width", "corner"]
        case .layout: return ["arrange", "rearrange", "reorder", "customise", "customize", "icons", "tabs", "toolbar",
                              "top bar", "pill", "indicators", "widgets", "buttons", "controls", "order"]
        case .media: return ["music", "spotify", "song", "track", "now playing", "lyrics", "controls"]
        case .calendar: return ["events", "reminders", "schedule", "agenda"]
        case .huds: return ["volume", "brightness", "keyboard backlight", "overlay"]
        case .battery: return ["charge", "power", "airpods", "bluetooth"]
        case .shelf: return ["files", "drag", "drop", "tray"]
        case .timer: return ["pomodoro", "countdown", "focus", "break"]
        case .shortcuts: return ["hotkey", "keyboard", "keys"]
        case .advanced: return ["display", "monitor", "external", "clipboard", "debug", "export", "import", "reset",
                                "welcome", "tutorial", "onboarding", "tour", "links", "bookmarks", "url"]
        case .about: return ["version", "quit", "changelog", "what's new", "release notes", "update"]
        }
    }

    /// True when the pane's name, or one of its keywords, contains the query.
    func matchesSearch(_ query: String) -> Bool {
        let needle = SettingsSearchIndex.fold(query).trimmingCharacters(in: .whitespaces)
        guard needle.count >= 2 else { return false }
        return SettingsSearchIndex.fold(title).contains(needle)
            || searchKeywords.contains { SettingsSearchIndex.fold($0).contains(needle) }
    }
}
