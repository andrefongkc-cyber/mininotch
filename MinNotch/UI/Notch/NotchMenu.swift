import AppKit
import SwiftUI

/// A short menu for a button that offers a choice.
///
/// In the notch it is drawn inside the panel (`NotchMenuOverlay`), hanging from the button that
/// opened it. An `NSMenu` cannot be used there: the notch lives in a window server space of its own
/// above every other (`NotchSpace`), and a menu window opens in the ordinary one, underneath the
/// panel, so the top bar's What's New button opened a menu nobody could see or click (the user's
/// report, 2026-10-19). Moving the menu's window into the notch's space did not show it either.
/// `--check-notch-menu` shows the hidden menu. Elsewhere (the pop-out windows) it is AppKit's menu
/// at the pointer, rather than SwiftUI's `Menu`, so the button keeps its own look: a SwiftUI menu
/// draws its own label in its own colours.
@MainActor
enum NotchMenu {
    struct Item {
        var title: String
        var symbol: String
        /// Ticked, for the choice that is in force.
        var isOn = false
        var action: () -> Void
    }

    /// A menu open in the panel: the anchor it hangs from (`notchMenuAnchor`) and its items.
    struct Open {
        let anchor: String
        let items: [Item]
    }

    /// The panel's coordinate space, which anchors are measured in.
    nonisolated static let space = "notchMenuSpace"

    /// In the notch (a view model), the panel's own menu, hanging from `anchor`; anywhere else,
    /// AppKit's at the pointer.
    static func show(_ items: [Item], anchor: String, in viewModel: NotchViewModel?) {
        if let viewModel {
            viewModel.menu = Open(anchor: anchor, items: items)
        } else {
            show(items)
        }
    }

    static func show(_ items: [Item]) {
        let menu = NSMenu()
        for item in items {
            let menuItem = ActionMenuItem(title: item.title, handler: item.action)
            menuItem.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)
            menuItem.state = item.isOn ? .on : .off
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

extension View {
    /// Records where this button sits in the panel, for a menu that hangs from it.
    func notchMenuAnchor(_ id: String, in viewModel: NotchViewModel?) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(NotchMenu.space))
        } action: { frame in
            viewModel?.menuAnchors[id] = frame
        }
    }
}

/// The open menu, over everything in the panel, under its anchor and kept inside the panel. A
/// click anywhere else in the panel closes it.
struct NotchMenuOverlay: View {
    @Environment(\.notchStyle) private var theme
    @Bindable var viewModel: NotchViewModel

    var body: some View {
        GeometryReader { proxy in
            if let open = viewModel.menu, let anchor = viewModel.menuAnchors[open.anchor] {
                let size = Self.size(for: open.items)
                // Under the anchor, its trailing edge on the anchor's when the anchor is in the
                // panel's right half, else its leading edge; inside the panel either way.
                let x = anchor.midX > proxy.size.width / 2 ? anchor.maxX - size.width : anchor.minX
                let y = min(anchor.maxY + 4, proxy.size.height - size.height - 6)
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.menu = nil }
                    NotchMenuPanel(items: open.items) { viewModel.menu = nil }
                        .frame(width: size.width)
                        .offset(x: min(max(x, 6), proxy.size.width - size.width - 6), y: max(y, 6))
                }
            }
        }
    }

    static let rowHeight: CGFloat = 24

    static func size(for items: [NotchMenu.Item]) -> CGSize {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize + 1)
        let widest = items.map { ($0.title as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        // Padding, icon and the gaps either side of it, with room to spare so a title is never
        // cut short; the tick's column when one is ticked.
        let ticks: CGFloat = items.contains(where: \.isOn) ? 22 : 0
        return CGSize(width: max(140, ceil(widest) + 76 + ticks),
                      height: CGFloat(items.count) * rowHeight + 8)
    }
}

private struct NotchMenuPanel: View {
    @Environment(\.notchStyle) private var theme
    let items: [NotchMenu.Item]
    let close: () -> Void

    var body: some View {
        let ticks = items.contains(where: \.isOn)
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                NotchMenuRow(item: item, showsTick: ticks) {
                    close()
                    item.action()
                }
            }
        }
        .padding(4)
        .background(
            NotchSurfaceView(style: theme.surface, isTranslucent: false,
                             edge: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.ink.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct NotchMenuRow: View {
    @Environment(\.notchStyle) private var theme
    let item: NotchMenu.Item
    let showsTick: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if showsTick {
                    TransportSymbol.image("checkmark", pointSize: 10)
                        .foregroundStyle(theme.ink.opacity(item.isOn ? 0.9 : 0))
                        .frame(width: 12)
                }
                TransportSymbol.image(item.symbol, pointSize: 11)
                    .foregroundStyle(theme.ink.opacity(0.75))
                    .frame(width: 16)
                Text(item.title)
                    .font(.system(size: NSFont.smallSystemFontSize + 1))
                    .foregroundStyle(theme.ink.opacity(0.92))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: NotchMenuOverlay.rowHeight)
            .background(NotchElementView(.button, shape: .rounded(6), emphasis: isHovering ? 0.16 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
