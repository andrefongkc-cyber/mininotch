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
final class ShelfService {
    private(set) var items: [ShelfItem] = []
    /// True while a drag is over the notch, so the surface can show it will accept the drop.
    var isDropTargeted = false

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
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    /// Called after an item has been dragged out.
    ///
    /// The setting decides whether the shelf keeps holding it. The file itself is never
    /// touched here: whether the destination copied or moved it is the destination's
    /// decision, and second-guessing that by deleting the original would lose data.
    func handleDragCompleted(_ item: ShelfItem) {
        guard let settings else { return }
        switch settings.shelf.dropBehavior {
        case .copy:
            break
        case .move:
            remove(item)
        case .ask:
            askWhetherToKeep(item)
        }
    }

    private func askWhetherToKeep(_ item: ShelfItem) {
        let alert = NSAlert()
        alert.messageText = "Keep \(item.name) on the shelf?"
        alert.informativeText = "The file itself has not been changed."
        alert.addButton(withTitle: "Keep")
        alert.addButton(withTitle: "Remove")
        alert.alertStyle = .informational

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            remove(item)
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
}
