import AppKit

/// The optional `NSStatusItem`.
///
/// The item can be hidden entirely, which is why the global shortcut is registered
/// unconditionally: hiding the icon must never leave the user without a way back into
/// Settings.
@MainActor
final class MenuBarController {
    private unowned let environment: AppEnvironment
    private var statusItem: NSStatusItem?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// Creates or removes the item to match the current setting.
    func update() {
        if environment.settings.general.showMenuBarIcon {
            install()
        } else {
            remove()
        }
    }

    private func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "MinNotch"
        )
        item.button?.image?.isTemplate = true
        item.menu = makeMenu()
        statusItem = item
    }

    private func remove() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: "Show or Hide Notch",
            action: #selector(toggleNotch),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        let whatsNew = NSMenuItem(
            title: "What's New…",
            action: #selector(openWhatsNew),
            keyEquivalent: ""
        )
        whatsNew.target = self
        menu.addItem(whatsNew)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit MinNotch", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func toggleNotch() { environment.notchWindows.toggleFrontmost() }
    @objc private func openSettings() { environment.openSettings() }
    @objc private func openWhatsNew() { environment.whatsNew.present() }
    @objc private func quit() { environment.quit() }
}
