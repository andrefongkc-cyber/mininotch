#if DEBUG
import AppKit

/// Checks that swiping between tabs goes in the order the top bar draws them.
///
/// Run with `MiniNotch --check-tab-order`.
///
/// Rearranges the top bar the way someone might in Settings > Layout, tabs moved around and one
/// across the cutout, then walks the tabs with the same `tabsInOrder` the swipe uses and compares
/// it with the bar's own left-to-right reading. The swipe once stepped through the registry's
/// fixed order instead, so a moved tab was skipped and visited out of place.
@MainActor
enum DebugTabOrderCheck {
    static let flag = "--check-tab-order"

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains(flag) else { return false }

        let environment = DebugSupport.makeEnvironment()
        let settings = environment.settings
        settings.media.enabled = true
        settings.calendar.enabled = true
        settings.timer.enabled = true
        settings.advanced.linkShelfEnabled = true
        settings.advanced.showDebugButtons = false
        // Out of registry order on purpose, with the timer across the cutout.
        settings.appearance.topStripLeading = [.links, .calendar, .media, .system]
        settings.appearance.topStripTrailing = [.timer, .settings, .battery]

        guard let screen = NSScreen.main else { return true }
        let geometry = NotchGeometry.make(for: screen, settings: settings)
        let viewModel = NotchViewModel(settings: settings, geometry: geometry)
        let layout = viewModel.topStripLayout(battery: environment.battery.status)

        let drawn = (layout.leading + layout.trailing).map(\.rawValue)
        let swipe = layout.tabsInOrder.map(\.rawValue)
        let registry = viewModel.availableTabs.map(\.rawValue)
        print("bar, left to right: \(drawn.joined(separator: " "))")
        print("swipe order:        \(swipe.joined(separator: " "))")
        print("registry order:     \(registry.joined(separator: " "))")

        let expected = drawn.filter { raw in NotchTab(rawValue: raw) != nil }
        let passed = swipe == expected && swipe != registry
        print(passed ? "ok   the swipe follows the bar" : "FAIL the swipe does not follow the bar")
        return true
    }
}
#endif
