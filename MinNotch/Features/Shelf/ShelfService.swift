import AppKit
import Observation
import UniformTypeIdentifiers

/// One file being held on the shelf.
///
/// The shelf stores a reference rather than a copy, so nothing is duplicated on disk and a
/// file edited elsewhere stays current. The bookmark is what survives a restart, and a
/// rename or a move, which a plain path would not.
struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    var url: URL
    var addedAt: Date

    var name: String { url.lastPathComponent }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    /// False once the file has been deleted or moved somewhere the bookmark cannot follow.
    var stillExists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    init(id: UUID = UUID(), url: URL, addedAt: Date = Date()) {
        self.id = id
        self.url = url
        self.addedAt = addedAt
    }
}

/// Holds files dropped onto the notch until they are dragged somewhere else.
///
/// Persisted as security-scoped bookmarks rather than paths, both because a bookmark follows
/// a file that is renamed or moved and because bookmarks are what a sandboxed build will
/// need in order to keep access across launches.
@Observable
@MainActor
final class ShelfService {
    private(set) var items: [ShelfItem] = []
    /// True while a drag is over the notch, so the surface can show it will accept the drop.
    var isDropTargeted = false
    /// Chips picked with a click, to drag or send several at once. Not saved: a selection is
    /// something you are in the middle of, not something to come back to.
    private(set) var selection: Set<ShelfItem.ID> = []

    private static let defaultsKey = "shelf.bookmarks"

    @ObservationIgnored private var settings: SettingsStore?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool { settings?.shelf.enabled ?? false }

    func start(settings: SettingsStore) {
        self.settings = settings
        load()
    }

    /// Called on quit. Honours the clear-on-quit setting rather than always persisting.
    func stop() {
        if settings?.shelf.clearOnQuit == true {
            items = []
        }
        save()
    }

    // MARK: Mutating

    @discardableResult
    func add(_ urls: [URL]) -> Int {
        guard isEnabled else { return 0 }

        var added = 0
        for url in urls {
            // Dropping the same file twice should refresh its position, not duplicate it.
            if let existing = items.firstIndex(where: { $0.url == url }) {
                items[existing].addedAt = Date()
                continue
            }
            items.append(ShelfItem(url: url))
            added += 1
        }

        prune()
        save()
        return added
    }

    func remove(_ item: ShelfItem) {
        remove([item])
    }

    func remove(_ removed: [ShelfItem]) {
        let ids = Set(removed.map(\.id))
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        save()
    }

    func clear() {
        items.removeAll()
        selection.removeAll()
        save()
    }

    // MARK: Selection

    enum SelectionGesture {
        /// A plain click: this chip alone, or nothing if it was already the only one.
        case only
        /// Command-click: in or out, leaving the rest.
        case toggle
        /// Shift-click: everything from the last chip picked to this one.
        case range
    }

    @ObservationIgnored private var anchor: ShelfItem.ID?

    func select(_ item: ShelfItem, _ gesture: SelectionGesture) {
        switch gesture {
        case .only:
            selection = selection == [item.id] ? [] : [item.id]
        case .toggle:
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
        case .range:
            guard let anchor, let from = items.firstIndex(where: { $0.id == anchor }),
                  let to = items.firstIndex(where: { $0.id == item.id }) else {
                selection = [item.id]
                break
            }
            selection.formUnion(items[min(from, to)...max(from, to)].map(\.id))
        }
        anchor = item.id
    }

    /// What a drag or a send that starts on `item` should carry: the whole selection when
    /// `item` is part of it, otherwise `item` alone. Starting on a chip outside the selection
    /// means that chip, which is what Finder does.
    func items(startingFrom item: ShelfItem) -> [ShelfItem] {
        guard selection.contains(item.id), selection.count > 1 else { return [item] }
        return items.filter { selection.contains($0.id) }
    }

    /// The selection, or everything when nothing is selected.
    var itemsToSend: [ShelfItem] {
        selection.isEmpty ? items : items.filter { selection.contains($0.id) }
    }

    /// Called after an item has been dragged out.
    ///
    /// The setting decides whether the shelf keeps holding it. The file itself is never
    /// touched here: whether the destination copied or moved it is the destination's
    /// decision, and second-guessing that by deleting the original would lose data.
    func handleDragCompleted(_ dragged: [ShelfItem]) {
        guard let settings, !dragged.isEmpty else { return }
        switch settings.shelf.dropBehavior {
        case .copy:
            break
        case .move:
            remove(dragged)
        case .ask:
            askWhetherToKeep(dragged)
        }
    }

    /// One question for everything that was dragged together, not one per file.
    private func askWhetherToKeep(_ dragged: [ShelfItem]) {
        let alert = NSAlert()
        alert.messageText = dragged.count == 1
            ? "Keep \(dragged[0].name) on the shelf?"
            : "Keep these \(dragged.count) files on the shelf?"
        alert.informativeText = "Nothing on disk has been changed."
        alert.addButton(withTitle: "Keep")
        alert.addButton(withTitle: "Remove")
        alert.alertStyle = .informational

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            remove(dragged)
        }
    }

    /// Drops the oldest items once the shelf is over its limit, and forgets anything whose
    /// file has gone away.
    private func prune() {
        items.removeAll { !$0.stillExists }

        let limit = max(1, settings?.shelf.maxItems ?? 12)
        guard items.count > limit else { return }
        items = items
            .sorted { $0.addedAt > $1.addedAt }
            .prefix(limit)
            .sorted { $0.addedAt < $1.addedAt }
    }

    /// Re-applies a changed item limit, and empties the shelf if the feature is switched off.
    func settingsChanged() {
        guard isEnabled else {
            if !items.isEmpty { items = [] }
            return
        }
        prune()
        save()
    }

    // MARK: Persistence

    private func save() {
        let bookmarks: [Data] = items.compactMap { item in
            try? item.url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        defaults.set(bookmarks, forKey: Self.defaultsKey)
    }

    private func load() {
        guard let bookmarks = defaults.array(forKey: Self.defaultsKey) as? [Data] else { return }

        items = bookmarks.compactMap { data in
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { return nil }
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return ShelfItem(url: url)
        }
    }

    #if DEBUG
    /// Three real files, the second selected, for `--capture-notch --tab shelf --sample-shelf`.
    /// Apps that ship with macOS, so they exist on every Mac and the stale-file pruning keeps them.
    func applySample() {
        let paths = ["/System/Applications/Notes.app", "/System/Applications/Calendar.app", "/System/Applications/Preview.app"]
        items = paths.map { ShelfItem(url: URL(fileURLWithPath: $0)) }
        selection = [items[1].id]
    }
    #endif
}
