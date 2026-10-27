import AppKit

/// The optional `NSStatusItem`.
///
/// The item can be hidden entirely, which is why the global shortcut is registered
/// unconditionally: hiding the icon must never leave the user without a way back into
/// Settings. Its menu is built each time it opens, so the settings pinned to it
/// (`GeneralSettings.menuBarPins`) show how they are set now.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private unowned let environment: AppEnvironment
    private var statusItem: NSStatusItem?

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
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
            accessibilityDescription: "MiniNotch"
        )
        item.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func remove() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        fill(menu)
    }

    private func fill(_ menu: NSMenu) {

        let toggle = NSMenuItem(
            title: "Show or Hide Notch",
            action: #selector(toggleNotch),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        // Settings pinned here from Settings > General > Menu Bar, ticked while on.
        let pins = environment.settings.general.menuBarPins
        if !pins.isEmpty {
            menu.addItem(.separator())
            for pin in pins {
                let item = NSMenuItem(title: pin.title, action: #selector(togglePin(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = pin.rawValue
                item.state = environment.settings[keyPath: pin.keyPath] ? .on : .off
                menu.addItem(item)
            }
        }

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

        if environment.updates.isAvailable {
            let update = NSMenuItem(
                title: "Check for Updates…",
                action: #selector(checkForUpdates),
                keyEquivalent: ""
            )
            update.target = self
            menu.addItem(update)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit MiniNotch", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func togglePin(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let pin = MenuBarPin(rawValue: raw) else { return }
        environment.settings[keyPath: pin.keyPath].toggle()
    }

    @objc private func toggleNotch() { environment.notchWindows.toggleFrontmost() }
    @objc private func openSettings() { environment.openSettings() }
    @objc private func openWhatsNew() { environment.whatsNew.present() }
    @objc private func checkForUpdates() { environment.updates.checkForUpdates() }
    @objc private func quit() { environment.quit() }
}
