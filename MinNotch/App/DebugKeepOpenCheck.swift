#if DEBUG
import AppKit

/// Checks Keep the Notch Open: that a kept panel survives the pointer leaving and a click, that
/// letting it go closes it, that its pin shows in the top bar while it is kept, and that a
/// settings file saved before the shortcut existed is given its default.
///
/// Run with `MiniNotch --check-keep-open`.
@MainActor
enum DebugKeepOpenCheck {
    static let flag = "--check-keep-open"

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains(flag) else { return false }
        var failures = 0
        func check(_ passed: Bool, _ what: String) {
            print((passed ? "ok   " : "FAIL ") + what)
            if !passed { failures += 1 }
        }
        func wait(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

        let environment = DebugSupport.makeEnvironment()
        let settings = environment.settings
        settings.general.closeOnMouseExit = true
        settings.general.clickToOpen = true

        // The real settings, decoded the way a launch decodes them.
        let combo = settings.shortcuts.combo(for: .keepOpen)
        check(combo != nil, "your saved shortcuts have Keep the Notch Open: \(combo.map { "\($0)" } ?? "none")")

        // A file from before the action existed gets the default; one that cleared it does not.
        let old = #"{"bindings":{},"globalHotkeysEnabled":true}"#
        let cleared = #"{"bindings":{},"globalHotkeysEnabled":true,"knownActions":["keepOpen"]}"#
        let decodedOld = try? JSONDecoder().decode(ShortcutSettings.self, from: Data(old.utf8))
        let decodedCleared = try? JSONDecoder().decode(ShortcutSettings.self, from: Data(cleared.utf8))
        check(decodedOld?.combo(for: .keepOpen) == HotkeyAction.defaultBindings["keepOpen"], "an older settings file is given ⌃⌥P")
        check(decodedCleared?.combo(for: .keepOpen) == nil, "a shortcut the user cleared stays cleared")

        guard let screen = NSScreen.main else { return true }
        let viewModel = NotchViewModel(settings: settings, geometry: NotchGeometry.make(for: screen, settings: settings))

        // Plain behaviour first, so the check proves the difference.
        viewModel.expand()
        viewModel.hoverChanged(true)
        viewModel.hoverChanged(false)
        wait(0.5)
        check(viewModel.state == .collapsed, "without it, the panel closes when the pointer leaves")

        viewModel.setKeptOpen(true)
        check(viewModel.state == .expanded, "keeping it open opens it")
        let layout = viewModel.topStripLayout(battery: environment.battery.status)
        check(layout.trailing.contains(.keepOpen), "its pin is in the top bar while kept: \(layout.trailing.map(\.rawValue))")
        viewModel.hoverChanged(true)
        viewModel.hoverChanged(false)
        wait(0.5)
        check(viewModel.state == .expanded, "kept, it stays open when the pointer leaves")
        viewModel.clicked()
        check(viewModel.state == .expanded, "kept, a click on the panel does not close it")

        viewModel.setKeptOpen(false)
        check(viewModel.state == .collapsed && !viewModel.isKeptOpen, "letting go closes it")
        let after = viewModel.topStripLayout(battery: environment.battery.status)
        check(!after.trailing.contains(.keepOpen), "and the pin leaves the top bar")

        viewModel.setKeptOpen(true)
        viewModel.collapse()
        check(!viewModel.isKeptOpen, "closing it on purpose lets it go")

        print(failures == 0 ? "ok   Keep the Notch Open behaves" : "FAIL \(failures) checks")
        return true
    }
}
#endif
