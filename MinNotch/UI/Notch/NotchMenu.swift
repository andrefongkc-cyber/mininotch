import AppKit

/// A short menu at the pointer, for a top bar button that offers a choice.
///
/// An `NSMenu` rather than SwiftUI's `Menu`, so the button keeps `NotchIconButton`'s look: a
/// SwiftUI menu draws its own label, in its own colours, which on the notch's black came out as a
/// system control rather than one of the bar's icons. A menu tracks the pointer by itself, so the
/// non-activating panel needs no focus to show it.
@MainActor
enum NotchMenu {
    struct Item {
        var title: String
        var symbol: String
        var action: () -> Void
    }

    static func show(_ items: [Item]) {
        let menu = NSMenu()
        for item in items {
            let menuItem = ActionMenuItem(title: item.title, handler: item.action)
            menuItem.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
            menu.addItem(menuItem)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// A menu item that runs a closure, since `NSMenuItem` wants a target and a selector.
private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("Not used from a nib")
    }

    @objc private func run() {
        handler()
    }
}
