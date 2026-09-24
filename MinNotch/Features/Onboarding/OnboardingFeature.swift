import SwiftUI

/// One feature the first-launch tutorial offers as a checkbox.
///
/// Each case reads and writes the real settings it stands for, so the tutorial never keeps a
/// second copy of the configuration that could disagree with Settings. Ticking a box here and
/// flipping the matching switch in Settings are the same act.
enum OnboardingFeature: String, CaseIterable, Identifiable {
    case nowPlaying
    case onlineLyrics
    case calendar
    case timer
    case systemStats
    case closedIndicators
    case clipboardHistory
    case linkShelf
    case shelf
    case ambientLighting
    case huds
    case gestures
    case floatingWindow
    case launchAtLogin
    case menuBarIcon

    var id: String { rawValue }

    enum Group: String, CaseIterable, Identifiable {
        case notch = "In the Notch"
        case extras = "Extras"
        case startup = "Starting Up"

        var id: String { rawValue }
    }

    var group: Group {
        switch self {
        case .nowPlaying, .onlineLyrics, .calendar, .timer, .systemStats, .closedIndicators:
            return .notch
        case .clipboardHistory, .linkShelf, .shelf, .ambientLighting, .huds, .gestures, .floatingWindow:
            return .extras
        case .launchAtLogin, .menuBarIcon:
            return .startup
        }
    }

    var title: String {
        switch self {
        case .nowPlaying: return "Now Playing"
        case .onlineLyrics: return "Synced Lyrics"
        case .calendar: return "Calendar and Reminders"
        case .timer: return "Timer and Pomodoro"
        case .systemStats: return "System Stats"
        case .closedIndicators: return "Show Indicators When Closed"
        case .clipboardHistory: return "Clipboard History"
        case .linkShelf: return "Link Shelf"
        case .shelf: return "File Shelf"
        case .ambientLighting: return "Ambient Lighting"
        case .huds: return "Volume and Brightness HUDs"
        case .gestures: return "Trackpad Gestures"
        case .floatingWindow: return "Floating Now Playing Window"
        case .launchAtLogin: return "Open at Login"
        case .menuBarIcon: return "Menu Bar Icon"
        }
    }

    /// What it does, in one or two plain sentences.
    var detail: String {
        switch self {
        case .nowPlaying:
            return "Album art, a scrubber, and play controls for Apple Music and Spotify."
        case .onlineLyrics:
            return "The line being sung, word by word, under the track."
        case .calendar:
            return "This week or month, with your next events and reminders you can tick off."
        case .timer:
            return "Countdowns and Pomodoro focus sessions. A running timer shows in the closed notch."
        case .systemStats:
            return "CPU, GPU, memory and network, plus AirPods and accessory battery."
        case .closedIndicators:
            return "Widens the closed notch to show battery, artwork and a running timer either side of the camera."
        case .clipboardHistory:
            return "Everything you copy, one click from being copied again."
        case .linkShelf:
            return "Drop or paste links onto the notch to keep them, then click one to open it."
        case .shelf:
            return "Drop files on the notch to hold them, then drag them out wherever they need to go."
        case .ambientLighting:
            return "A soft glow around the notch, coloured from the album cover."
        case .huds:
            return "Volume, brightness and keyboard backlight shown at the notch instead of mid-screen."
        case .gestures:
            return "Two-finger swipes on the notch to switch tabs or open and close it."
        case .floatingWindow:
            return "Now Playing in a small window you can put anywhere. Handy on a monitor with no notch."
        case .launchAtLogin:
            return "Start MinNotch when you log in, so the notch is always ready."
        case .menuBarIcon:
            return "An icon in the menu bar for Settings and quitting."
        }
    }

    /// Something worth knowing before ticking it: a permission, data leaving the Mac, a cost.
    ///
    /// Said up front because each of these is a thing people are annoyed to discover later.
    /// Nil when there is nothing to say.
    var caveat: String? {
        switch self {
        case .onlineLyrics:
            return "Sends the track's title, artist, album and length to lrclib.net."
        case .calendar:
            return "Asks for Calendar access the first time it opens."
        case .nowPlaying:
            return "macOS asks to let MinNotch control Music or Spotify the first time one plays."
        case .clipboardHistory:
            return "Kept in memory only. Copies an app marks as private, like passwords, are skipped."
        case .linkShelf:
            return "Reads each link's title and icon from its site when you add it."
        case .ambientLighting:
            return "Uses noticeably more power while it animates."
        case .huds:
            return "Hides Apple's own overlay, which needs Accessibility access."
        case .closedIndicators:
            return "Off keeps the closed notch hidden behind the camera."
        case .menuBarIcon:
            return "Without it, open Settings from the gear in the open notch."
        default:
            return nil
        }
    }

    var symbolName: String {
        switch self {
        case .nowPlaying: return "music.note"
        case .onlineLyrics: return "quote.bubble"
        case .calendar: return "calendar"
        case .timer: return "timer"
        case .systemStats: return "gauge.with.dots.needle.33percent"
        case .closedIndicators: return "rectangle.expand.vertical"
        case .clipboardHistory: return "doc.on.clipboard"
        case .linkShelf: return "link"
        case .shelf: return "tray.full"
        case .ambientLighting: return "light.beacon.max"
        case .huds: return "speaker.wave.2"
        case .gestures: return "hand.draw"
        case .floatingWindow: return "macwindow.on.rectangle"
        case .launchAtLogin: return "power"
        case .menuBarIcon: return "menubar.rectangle"
        }
    }

    var tint: Color {
        switch self {
        case .nowPlaying, .onlineLyrics, .floatingWindow: return Color(nsColor: .systemRed)
        case .calendar: return Color(nsColor: .systemOrange)
        case .timer: return Color(nsColor: .systemYellow)
        case .systemStats: return Color(nsColor: .systemGreen)
        case .closedIndicators, .menuBarIcon, .launchAtLogin: return Color(nsColor: .systemGray)
        case .clipboardHistory: return Color(nsColor: .systemBlue)
        case .linkShelf: return Color(nsColor: .systemCyan)
        case .shelf: return Color(nsColor: .systemTeal)
        case .ambientLighting: return Color(nsColor: .systemPink)
        case .huds: return Color(nsColor: .systemPurple)
        case .gestures: return Color(nsColor: .systemIndigo)
        }
    }

    /// The flag that gates the feature, if one does. A feature whose flag is off is not
    /// offered at all, rather than offered as a box that ticks and does nothing.
    var flag: FeatureFlag? {
        switch self {
        case .nowPlaying, .floatingWindow: return .nowPlaying
        case .onlineLyrics: return .lyrics
        case .calendar: return .calendar
        case .timer: return .pomodoro
        case .systemStats: return .systemStats
        case .clipboardHistory: return .clipboardHistory
        case .linkShelf: return .linkShelf
        case .shelf: return .shelf
        case .huds: return .hud
        case .gestures: return .gestures
        case .closedIndicators, .ambientLighting, .launchAtLogin, .menuBarIcon: return nil
        }
    }

    var isAvailable: Bool { flag?.isEnabled ?? true }

    /// "Beta" where the flag says so, so an unfinished feature is not sold as a finished one.
    var badge: SettingsBadge? { flag?.badge }

    static var available: [OnboardingFeature] { allCases.filter(\.isAvailable) }

    // MARK: Settings

    /// Whether the feature is on in `settings` right now.
    @MainActor func isOn(in settings: SettingsStore) -> Bool {
        switch self {
        case .nowPlaying: return settings.media.enabled
        case .onlineLyrics: return settings.media.showLyrics && settings.media.lyricsSource.usesNetwork
        case .calendar: return settings.calendar.enabled
        case .timer: return settings.timer.enabled
        case .systemStats: return settings.advanced.showSystemStats
        case .closedIndicators: return settings.general.extendPillForIndicators
        case .clipboardHistory: return settings.advanced.clipboardHistoryEnabled
        case .linkShelf: return settings.advanced.linkShelfEnabled
        case .shelf: return settings.shelf.enabled
        case .ambientLighting: return settings.appearance.ambientGlow.isEnabled
        case .huds:
            return settings.huds.replaceVolumeHUD
                || settings.huds.replaceBrightnessHUD
                || settings.huds.replaceKeyboardBacklightHUD
        case .gestures: return settings.advanced.twoFingerGesturesEnabled
        case .floatingWindow: return settings.media.floatingWindow
        case .launchAtLogin: return settings.general.launchAtLogin
        case .menuBarIcon: return settings.general.showMenuBarIcon
        }
    }

    /// Switches the feature on or off by writing the settings it stands for.
    @MainActor func apply(_ isOn: Bool, to settings: SettingsStore) {
        switch self {
        case .nowPlaying:
            settings.media.enabled = isOn
        case .onlineLyrics:
            // Lyrics from the player alone find almost nothing for streamed music, so "on"
            // means the lookup that actually works, and "off" means no strip at all rather
            // than one that permanently says there are no lyrics.
            settings.media.showLyrics = isOn
            settings.media.lyricsSource = isOn ? .playerThenOnline : .playerOnly
        case .calendar:
            settings.calendar.enabled = isOn
        case .timer:
            settings.timer.enabled = isOn
        case .systemStats:
            settings.advanced.showSystemStats = isOn
        case .closedIndicators:
            settings.general.extendPillForIndicators = isOn
        case .clipboardHistory:
            settings.advanced.clipboardHistoryEnabled = isOn
        case .linkShelf:
            settings.advanced.linkShelfEnabled = isOn
        case .shelf:
            settings.shelf.enabled = isOn
        case .ambientLighting:
            settings.appearance.ambientGlow.isEnabled = isOn
        case .huds:
            settings.huds.replaceVolumeHUD = isOn
            settings.huds.replaceBrightnessHUD = isOn
            settings.huds.replaceKeyboardBacklightHUD = isOn
            // Without this, turning the HUDs on shows two indicators for every key press:
            // Apple's and MinNotch's. It needs Accessibility, which the permissions page offers
            // next, and until that is allowed Apple's overlay simply keeps showing.
            settings.huds.suppressSystemOverlay = isOn
        case .gestures:
            settings.advanced.twoFingerGesturesEnabled = isOn
        case .floatingWindow:
            settings.media.floatingWindow = isOn
        case .launchAtLogin:
            settings.general.launchAtLogin = isOn
        case .menuBarIcon:
            settings.general.showMenuBarIcon = isOn
        }
    }
}

/// A starting point for the checklist.
enum OnboardingPreset: String, CaseIterable, Identifiable {
    case recommended
    case everything
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommended: return "Recommended"
        case .everything: return "Everything"
        case .minimal: return "Minimal"
        }
    }

    /// The ticked set, restricted to what this build can actually do.
    ///
    /// Recommended leaves out anything that sends data off the Mac, watches the clipboard,
    /// or costs real power. Those are good features, but each is a choice someone should make
    /// on purpose rather than find already made.
    var features: Set<OnboardingFeature> {
        let chosen: Set<OnboardingFeature>
        switch self {
        case .recommended:
            chosen = [.nowPlaying, .calendar, .timer, .systemStats, .closedIndicators,
                      .launchAtLogin, .menuBarIcon]
        case .everything:
            chosen = Set(OnboardingFeature.allCases)
        case .minimal:
            chosen = [.nowPlaying, .menuBarIcon]
        }
        return chosen.filter(\.isAvailable)
    }
}
