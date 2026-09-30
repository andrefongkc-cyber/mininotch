import Foundation

/// Which displays get a notch surface.
enum DisplayTargeting: String, Codable, CaseIterable, Identifiable {
    /// Follow the pointer: the notch appears on whichever display is active.
    case activeDisplay
    /// Only the built-in display.
    case builtInOnly
    /// Every connected display at once.
    case allDisplays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activeDisplay: return "Display With Pointer"
        case .builtInOnly: return "Built-in Display Only"
        case .allDisplays: return "All Displays"
        }
    }
}

/// How tall the collapsed pill is on a display without a physical notch.
enum NotchHeightMode: String, Codable, CaseIterable, Identifiable {
    /// Match the real notch when there is one, otherwise use `fixedHeight`.
    case matchPhysical
    /// Always use `fixedHeight`.
    case fixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .matchPhysical: return "Match Physical Notch"
        case .fixed: return "Fixed Height"
        }
    }
}

/// Settings > Advanced.
struct AdvancedSettings: Codable, Equatable {
    /// Draw a virtual notch on displays with no physical one. This is a first-class case,
    /// not a fallback: most external monitors and every Mac mini or Studio hits this path.
    var showOnNonNotchDisplays: Bool = true

    var displayTargeting: DisplayTargeting = .activeDisplay
    var notchHeightMode: NotchHeightMode = .matchPhysical

    /// Collapsed height in points when `notchHeightMode` is `.fixed`, or when the display
    /// has no physical notch to match.
    var virtualNotchHeight: Double = 32

    /// Collapsed width in points on a display with no physical notch.
    var virtualNotchWidth: Double = 190

    /// Which tab a display with no physical notch opens on.
    ///
    /// Separate from `general.defaultTab` because the two surfaces are not the same thing. A
    /// real notch is hiding behind a camera housing and an idle pill there is invisible; a
    /// virtual notch on an external monitor is a black tab stuck to the top of the screen
    /// with nothing to blend into, so it should be showing something worth the space.
    var nonNotchDefaultTab: NotchTab = .timer

    /// On a display with no physical notch, draw nothing while closed, and open as usual when the
    /// pointer reaches the spot the notch would be in.
    ///
    /// For an external monitor where a black tab at the top is unwanted but the notch is not.
    /// Only the virtual notch: a real one already hides behind the camera housing. Hidden means
    /// the resting pill, its glow, the sneak peek and the lyrics strip; a volume or brightness HUD
    /// still shows, because it answers something the user just did.
    var hideVirtualNotchUntilHover: Bool = false

    /// Remember what has been copied, and offer it back from the Clipboard tab.
    var clipboardHistoryEnabled: Bool = false

    /// Unpinned items kept before the oldest is dropped. Pinned items are not counted.
    var clipboardHistoryLimit: Int = 20

    /// Keep links on the notch, in the Links tab.
    var linkShelfEnabled: Bool = false

    /// Links kept before the oldest is dropped.
    var linkShelfLimit: Int = 25

    /// Show the CPU, GPU, memory, and network readout in the System tab.
    var showSystemStats: Bool = true

    /// Seconds between samples while the readout is on screen. Sampling stops entirely when
    /// it is not.
    var statsRefreshInterval: Double = 2

    // MARK: V2 scaffolding

    var twoFingerGesturesEnabled: Bool = false
    var gestureSensitivity: Double = 0.5

    /// Swaps which way a sideways swipe moves through the tabs.
    ///
    /// There is no right answer: some people read a swipe as pushing the content, others as
    /// pointing at where they want to go, and the system's own natural-scrolling setting does
    /// not cover this gesture.
    var invertGestureDirection: Bool = false
    var hapticFeedbackEnabled: Bool = false

    /// How firm the tap is. macOS has no amplitude control, only different patterns.
    var hapticStrength: HapticStrength = .firm

    // Drawing on the lock screen lives in `HUDSettings.showOnLockScreen` and
    // `MediaSettings.showOnLockScreen`, through `LockScreenSpace`. An older `showOnLockScreen`
    // key here, from when it was wrongly thought impossible, is ignored by the lenient decode.

    /// Draw the notch's hit-test region so window placement problems are visible.
    var showDebugOverlay: Bool = false

    /// Put What's New and Tutorial buttons in the open panel's top bar, for checking both
    /// without hunting through menus.
    ///
    /// On by default in a Debug build, which is what `Scripts/run.sh` produces and what the
    /// person working on the app looks at; off in a Release build, so people it is shared with
    /// do not get two buttons they have no use for.
    var showDebugButtons: Bool = AdvancedSettings.debugButtonsDefault

    static let debugButtonsDefault: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showOnNonNotchDisplays = c.value(.showOnNonNotchDisplays, true)
        displayTargeting = c.value(.displayTargeting, DisplayTargeting.activeDisplay)
        notchHeightMode = c.value(.notchHeightMode, NotchHeightMode.matchPhysical)
        nonNotchDefaultTab = c.value(.nonNotchDefaultTab, NotchTab.timer)
        hideVirtualNotchUntilHover = c.value(.hideVirtualNotchUntilHover, false)
        clipboardHistoryEnabled = c.value(.clipboardHistoryEnabled, false)
        clipboardHistoryLimit = c.value(.clipboardHistoryLimit, 20, in: 5...100)
        linkShelfEnabled = c.value(.linkShelfEnabled, false)
        linkShelfLimit = c.value(.linkShelfLimit, 25, in: 5...100)
        showSystemStats = c.value(.showSystemStats, true)
        statsRefreshInterval = c.value(.statsRefreshInterval, 2, in: 0.5...5)
        virtualNotchHeight = c.value(.virtualNotchHeight, 32, in: 22...48)
        virtualNotchWidth = c.value(.virtualNotchWidth, 190, in: 120...320)
        twoFingerGesturesEnabled = c.value(.twoFingerGesturesEnabled, false)
        gestureSensitivity = c.value(.gestureSensitivity, 0.5, in: 0...1)
        invertGestureDirection = c.value(.invertGestureDirection, false)
        hapticFeedbackEnabled = c.value(.hapticFeedbackEnabled, false)
        hapticStrength = c.value(.hapticStrength, HapticStrength.firm)
        showDebugOverlay = c.value(.showDebugOverlay, false)
        showDebugButtons = c.value(.showDebugButtons, AdvancedSettings.debugButtonsDefault)
    }
}
