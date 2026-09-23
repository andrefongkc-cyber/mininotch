import Foundation

/// A file arriving in the Downloads folder.
struct DownloadItem: Identifiable, Equatable {
    /// Path of the browser's temporary file, which is what identifies the download while it runs.
    let id: String
    /// What the file will be called once it is done.
    var name: String
    /// 0...1 when the browser says how far along it is, nil when it does not.
    var fraction: Double?
    var isFinished = false
}

/// Watches the Downloads folder for files that are still arriving.
///
/// Browsers write a download to a temporary name and rename it when it completes: Safari to a
/// `.download` bundle, Chrome and the browsers built on it to `.crdownload`, Firefox to `.part`.
/// That rename is the whole signal, so this is a folder watch, not a browser integration: it
/// works for every browser that follows the pattern and needs no extension or permission from
/// any of them. Progress comes from the same place Finder's progress bars do, the `NSProgress`
/// a browser publishes for the file, with Safari's own bookkeeping as a fallback.
///
/// The folder is only watched while the feature is on. Reading it is a privacy permission
/// (Files and Folders > Downloads), asked for from the foreground when the feature is first
/// switched on, which is the only moment the reason is obvious.
@MainActor
final class DownloadsMonitor {
    /// Raised on the main queue whenever a download starts, moves, finishes, or goes away.
    var onChange: (([DownloadItem]) -> Void)?

    /// False once reading the folder has been refused.
    private(set) var hasAccess = true

    private let folder: URL?
    private let asksFromForeground: Bool

    /// `folder` is the Downloads folder unless a check points it somewhere else, in which case
    /// there is no permission to ask for and no app to bring forward.
    init(
        folder: URL? = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
        asksFromForeground: Bool = true
    ) {
        self.folder = folder
        self.asksFromForeground = asksFromForeground
    }
    private var source: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private var items: [String: DownloadItem] = [:]
    /// Progress published for each temporary file, kept so a subscription can be ended.
    private var subscriptions: [String: Any] = [:]
    /// Written from whatever queue a browser publishes progress on, read on main.
    private let published = PublishedProgress()

    /// Temporary extensions, as each browser family names them.
    static let temporaryExtensions: Set<String> = ["download", "crdownload", "part", "partial", "opdownload"]

    var isRunning: Bool { source != nil }

    func start() {
        guard source == nil, let folder else { return }

        // Opening the folder is what asks for access, so it is done with the app frontmost.
        if asksFromForeground { ForegroundPrompt.begin(timeout: 30) }
        let descriptor = open(folder.path, O_EVTONLY)
        let readable = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil
        if asksFromForeground { ForegroundPrompt.end() }

        guard descriptor >= 0, readable else {
            if descriptor >= 0 { close(descriptor) }
            hasAccess = false
            AppLog.app.error("Downloads folder is not readable; download activities are off")
            return
        }
        hasAccess = true

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.rescan() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        rescan()
    }

    func stop() {
        source?.cancel()
        source = nil
        pollTimer?.invalidate()
        pollTimer = nil
        for key in Array(subscriptions.keys) { unsubscribe(key) }
        let hadItems = !items.isEmpty
        items.removeAll()
        if hadItems { onChange?([]) }
    }

    // MARK: Scanning

    /// Re-reads the folder. Cheap: one shallow listing, with nothing opened but Safari's plist.
    private func rescan() {
        guard let folder else { return }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let temporary = Set(names.filter { Self.temporaryExtensions.contains(($0 as NSString).pathExtension.lowercased()) })

        var changed = false

        // New downloads.
        for name in temporary {
            let path = folder.appendingPathComponent(name).path
            if items[path] == nil {
                items[path] = DownloadItem(id: path, name: Self.finalName(for: name))
                subscribe(path)
                changed = true
            }
        }

        // Downloads whose temporary file has gone: finished if the real file is there now,
        // cancelled if it is not.
        for (path, item) in items where !item.isFinished && !temporary.contains((path as NSString).lastPathComponent) {
            unsubscribe(path)
            let finalPath = folder.appendingPathComponent(item.name).path
            if FileManager.default.fileExists(atPath: finalPath) {
                items[path]?.isFinished = true
                items[path]?.fraction = 1
            } else {
                items[path] = nil
            }
            changed = true
        }

        // Progress.
        for (path, item) in items where !item.isFinished {
            let fraction = published.fraction(for: path) ?? Self.safariFraction(at: path)
            if fraction != item.fraction {
                items[path]?.fraction = fraction
                changed = true
            }
        }

        updatePolling()
        if changed { publish() }
    }

    /// Removes a finished download, once it has been shown as done for long enough.
    func forget(_ id: String) {
        guard items[id]?.isFinished == true else { return }
        items[id] = nil
        publish()
    }

    private func publish() {
        onChange?(items.values.sorted { $0.name < $1.name })
    }

    /// The folder only reports that something changed, not that a file grew, so progress is
    /// re-read on a slow timer while anything is still arriving, and not at all otherwise.
    private func updatePolling() {
        let isDownloading = items.values.contains { !$0.isFinished }
        if isDownloading, pollTimer == nil {
            let timer = Timer.onMain(every: 1) { [weak self] in self?.rescan() }
            pollTimer = timer
        } else if !isDownloading {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    // MARK: Progress

    /// Subscribes to the progress a browser publishes for the file, as Finder does. The folder
    /// poll reads the latest value, so nothing here has to reach back to the main queue.
    private func subscribe(_ path: String) {
        let url = URL(fileURLWithPath: path)
        let store = published
        // `@Sendable`, so it does not inherit this class's main-actor isolation: the system
        // calls it on a queue of its own, and in Swift 6 an inherited isolation is checked on
        // entry and stops the app.
        let subscriber = Progress.addSubscriber(forFileURL: url) { @Sendable progress in
            let observation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { progress, _ in
                store.set(progress.fractionCompleted, for: path)
            }
            store.keep(observation, for: path)
            return { store.clear(path) }
        }
        subscriptions[path] = subscriber
    }

    private func unsubscribe(_ path: String) {
        if let subscriber = subscriptions.removeValue(forKey: path) {
            Progress.removeSubscriber(subscriber)
        }
        published.clear(path)
    }

    /// Safari keeps its byte counts in the bundle's `Info.plist`.
    private static func safariFraction(at path: String) -> Double? {
        guard (path as NSString).pathExtension.lowercased() == "download" else { return nil }
        let plist = (path as NSString).appendingPathComponent("Info.plist")
        guard let info = NSDictionary(contentsOfFile: plist),
              let done = (info["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.doubleValue,
              let total = (info["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.doubleValue,
              total > 0 else { return nil }
        return min(max(done / total, 0), 1)
    }

    /// `report.pdf.crdownload` becomes `report.pdf`. Chrome's unnamed `Unconfirmed 123.crdownload`
    /// stays as it is, which is also what Finder shows for it.
    static func finalName(for temporaryName: String) -> String {
        let stripped = (temporaryName as NSString).deletingPathExtension
        return stripped.isEmpty ? temporaryName : stripped
    }
}

/// The latest published fraction per file, and the observations producing them, behind a lock
/// because a browser publishes on its own queue.
private final class PublishedProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var fractions: [String: Double] = [:]
    private var observations: [String: NSKeyValueObservation] = [:]

    func set(_ fraction: Double, for path: String) {
        lock.withLock { fractions[path] = fraction }
    }

    func fraction(for path: String) -> Double? {
        lock.withLock { fractions[path] }
    }

    func keep(_ observation: NSKeyValueObservation, for path: String) {
        lock.withLock { observations[path] = observation }
    }

    func clear(_ path: String) {
        lock.withLock {
            fractions[path] = nil
            observations[path] = nil
        }
    }
}
