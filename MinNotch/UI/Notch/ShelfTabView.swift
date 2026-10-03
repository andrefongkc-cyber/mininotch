import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Shelf tab: files and links parked on the notch, in one place.
///
/// They were two tabs, the Shelf for files (with AirDrop) and Links for web links, and the user
/// asked for them together: both are things put down on the notch to be picked up again. Files
/// sit on top with the AirDrop tile, links underneath. The tab takes every drop and sends it to
/// the right half: a file to the shelf, a web link or text to the links. Paste does the same with
/// the clipboard, so ⌘V after copying files in Finder holds them, and after copying a link keeps
/// it. Each half is still its own feature with its own switch, and with one of them off the tab
/// is that half alone, drawn as it always was.
struct ShelfTabView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(SettingsStore.self) private var settings

    static func showsFiles(_ settings: SettingsStore) -> Bool {
        FeatureFlag.shelf.isEnabled && settings.shelf.enabled
    }

    static func showsLinks(_ settings: SettingsStore) -> Bool {
        FeatureFlag.linkShelf.isEnabled && settings.advanced.linkShelfEnabled
    }

    /// Fixed, whatever either half holds, so the panel never resizes under a drop.
    static let combinedHeight: CGFloat = ShelfView.combinedRowHeight + 4 + 14   // files and their footer
        + dividerSpacing * 2 + 1                                                   // the rule between
        + LinkShelfWidgetView.combinedListHeight + 4 + LinkShelfWidgetView.footerHeight
    private static let dividerSpacing: CGFloat = 6

    static func preferredHeight(settings: SettingsStore) -> CGFloat {
        switch (showsFiles(settings), showsLinks(settings)) {
        case (true, true): return combinedHeight
        case (false, true): return LinkShelfWidgetView.preferredHeight
        default: return ShelfView.preferredHeight
        }
    }

    var body: some View {
        if Self.showsFiles(settings), Self.showsLinks(settings) {
            VStack(spacing: 0) {
                ShelfView(isCombined: true)
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
                    .padding(.vertical, Self.dividerSpacing)
                LinkShelfWidgetView(isCombined: true, onPaste: paste)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onDrop(of: [.fileURL, .url, .plainText], delegate: ShelfTabDrop(
                shelf: environment.shelf,
                links: environment.linkShelf,
                settings: settings
            ))
        } else if Self.showsLinks(settings) {
            LinkShelfWidgetView()
        } else {
            ShelfView()
        }
    }

    /// Files copied in Finder go on the shelf; anything else is looked through for links.
    private func paste() {
        let pasteboard = NSPasteboard.general
        if let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !files.isEmpty {
            environment.shelf.add(files)
            Haptics.perform(enabled: settings.advanced.hapticFeedbackEnabled, strength: settings.advanced.hapticStrength)
            return
        }
        if environment.linkShelf.addFromPasteboard() == 0 {
            environment.linkShelf.flash("Nothing on the clipboard to keep")
        }
    }
}

/// One drop target for the whole Shelf tab, which decides where a drop goes.
///
/// Each half used to be its own target, and a file is also a URL, so a file let go over the
/// links would have been offered to the link shelf and refused there as not a web link. Here a
/// drop carrying files goes to the shelf wherever it lands, and anything else to the links, and
/// the half it will go to lights up while it is held. The AirDrop tile stays a target of its own
/// inside this one: the innermost target under the pointer wins, so files let go on it are sent.
private struct ShelfTabDrop: DropDelegate {
    let shelf: ShelfService
    let links: LinkShelfService
    let settings: SettingsStore

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL, .url, .plainText])
    }

    func dropEntered(info: DropInfo) {
        highlight(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        highlight(info)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        shelf.isDropTargeted = false
        links.isDropTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        let carriesFiles = info.hasItemsConforming(to: [.fileURL])
        dropExited(info: info)
        if carriesFiles {
            return ShelfView.accept(info.itemProviders(for: [.fileURL]), into: shelf, settings: settings)
        }
        return LinkShelfWidgetView.accept(info.itemProviders(for: [.url, .plainText]), into: links)
    }

    private func highlight(_ info: DropInfo) {
        let carriesFiles = info.hasItemsConforming(to: [.fileURL])
        if shelf.isDropTargeted != carriesFiles { shelf.isDropTargeted = carriesFiles }
        if links.isDropTargeted == carriesFiles { links.isDropTargeted = !carriesFiles }
    }
}
