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

    /// Remember what has been copied, and offer it back from the Clipboard tab.
    var clipboardHistoryEnabled: Bool = false

    /// Unpinned items kept before the oldest is dropped. Pinned items are not counted.
    var clipboardHistoryLimit: Int = 20

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

    // There is no `showOnLockScreen`. macOS gives third-party apps no way to draw on the
    // lock screen: no window level is composited there and there is no widget surface for it,
    // unlike iOS. The setting used to exist and did nothing, so it was removed rather than
    // left as a switch that could never work. Old settings files still carrying the key are
    // ignored by the lenient decode.

    /// Draw the notch's hit-test region so window placement problems are visible.
    var showDebugOverlay: Bool = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showOnNonNotchDisplays = c.value(.showOnNonNotchDisplays, true)
        displayTargeting = c.value(.displayTargeting, DisplayTargeting.activeDisplay)
        notchHeightMode = c.value(.notchHeightMode, NotchHeightMode.matchPhysical)
        nonNotchDefaultTab = c.value(.nonNotchDefaultTab, NotchTab.timer)
        clipboardHistoryEnabled = c.value(.clipboardHistoryEnabled, false)
        clipboardHistoryLimit = c.value(.clipboardHistoryLimit, 20, in: 5...100)
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
    }
}
