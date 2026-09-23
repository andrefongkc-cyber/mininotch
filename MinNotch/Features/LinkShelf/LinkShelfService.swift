import AppKit
import CryptoKit
import Observation

/// One link on the shelf.
struct LinkItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var url: URL
    /// The page's title, once it has been read. Nil until then, or if the page has none.
    var title: String?
    var addedAt = Date()

    /// What a row shows as its heading: the title when there is one, the host otherwise.
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return url.host ?? url.absoluteString
    }

    var host: String { url.host?.lowercased() ?? "" }
}

/// Links parked on the notch: dropped or pasted in, opened or copied back out.
///
/// The file shelf's idea, for URLs, and deliberately simpler than it: a URL is a value, not a
/// file, so there are no security-scoped bookmarks and the list persists as plain JSON.
///
/// Only `http` and `https` links are accepted, at the door. Everything else on the shelf is
/// eventually handed to `NSWorkspace.open`, which opens whatever a scheme is registered to, so
/// accepting `file:` or a custom app scheme would make "click a row" able to open local files
/// or launch arbitrary apps with arbitrary arguments.
///
/// Each link's title and icon are read from the page itself through `BoundedHTTPClient`:
/// HTTPS only, the first 256 KB of the page at most, and a timeout. That is a request to the
/// linked site, which is said plainly in Settings, since the user did not click the link yet.
@Observable
@MainActor
final class LinkShelfService {
    private(set) var items: [LinkItem] = []
    /// Site icons by host. Filled as they load; a host with no usable icon never appears.
    private(set) var icons: [String: NSImage] = [:]
    /// True while a drag carrying a link is over the drop zone, so the view can highlight it.
    var isDropTargeted = false

    @ObservationIgnored private var settings: SettingsStore?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private static let defaultsKey = "linkShelf.items"

    /// Enough of a page for its `<head>`, following redirects, since most short links redirect.
    @ObservationIgnored private let pageClient = BoundedHTTPClient(
        maxBytes: 256_000, timeout: 8, truncatesAtLimit: true, followsCrossHostRedirects: true
    )
    @ObservationIgnored private let iconClient = BoundedHTTPClient(
        maxBytes: 300_000, timeout: 8, followsCrossHostRedirects: true
    )
    @ObservationIgnored private var fetchingTitles: Set<UUID> = []
    @ObservationIgnored private var fetchingIcons: Set<String> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func start(settings: SettingsStore) {
        self.settings = settings
        load()
        items.forEach(fetchMetadataIfNeeded)
    }

    func stop() {
        save()
    }

    /// Re-applies the item limit after it changes in Settings.
    func settingsChanged() {
        enforceLimit()
    }

    // MARK: Adding

    /// Adds every web link found in `text`, keeping their order at the top. Returns how many.
    ///
    /// Found with `NSDataDetector` rather than by parsing the string as one URL, so a dragged
    /// text selection that merely contains a link, or several, still works, and a bare
    /// `example.com` is recognised the way it would be in Mail or Notes.
    @discardableResult
    func add(fromText text: String) -> Int {
        let links = Self.webLinks(in: text)
        links.reversed().forEach(add)
        return links.count
    }

    func add(_ url: URL) {
        guard let url = Self.normalised(url) else { return }

        // The same link again moves to the top rather than appearing twice.
        if let existing = items.firstIndex(where: { $0.url == url }) {
            var item = items.remove(at: existing)
            item.addedAt = Date()
            items.insert(item, at: 0)
        } else {
            items.insert(LinkItem(url: url), at: 0)
        }

        enforceLimit()
        save()
        if let item = items.first { fetchMetadataIfNeeded(item) }
    }

    /// Adds whatever links are on the general pasteboard. Returns how many were found.
    @discardableResult
    func addFromPasteboard() -> Int {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: false]) as? [URL] {
            let web = urls.compactMap(Self.normalised)
            if !web.isEmpty {
                web.reversed().forEach(add)
                return web.count
            }
        }
        guard let string = pasteboard.string(forType: .string) else { return 0 }
        return add(fromText: string)
    }

    // MARK: Actions

    func open(_ item: LinkItem) {
        NSWorkspace.shared.open(item.url)
    }

    func copy(_ item: LinkItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item.url as NSURL])
        pasteboard.setString(item.url.absoluteString, forType: .string)
    }

    func remove(_ item: LinkItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clearAll() {
        items.removeAll()
        save()
    }

    // MARK: Validation

    /// Only web links, with a host. Anything else is refused before it can be stored or opened.
    static func normalised(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    static func webLinks(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen = Set<URL>()
        return detector.matches(in: text, range: range).compactMap { match in
            guard var url = match.url.flatMap(normalised) else { return nil }
            // A bare "example.com" comes back from the detector as `http://`. Nobody typed that
            // scheme, and nearly every site is served over HTTPS, so the shelf keeps the secure
            // form rather than a link that has to be redirected before it loads.
            if let written = Range(match.range, in: text),
               !text[written].lowercased().hasPrefix("http"),
               var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                components.scheme = "https"
                url = components.url ?? url
            }
            guard seen.insert(url).inserted else { return nil }
            return url
        }
    }

    // MARK: Metadata

    /// Reads the page once for both its title and the icon it declares.
    ///
    /// One request per link, not one for the title and another for the icon: every request is
    /// the site learning someone has its link, so there should be as few as the preview needs.
    /// A cached icon or an existing title skips the part it covers, and an `http` link is read
    /// over HTTPS, since the client refuses plain HTTP; the link itself still opens as dropped.
    private func fetchMetadataIfNeeded(_ item: LinkItem) {
        let host = item.host
        if icons[host] == nil, let cached = IconCache.image(forHost: host) {
            icons[host] = cached
        }

        let needsTitle = item.title == nil && !fetchingTitles.contains(item.id)
        let needsIcon = !host.isEmpty && icons[host] == nil && !fetchingIcons.contains(host)
        guard needsTitle || needsIcon, let pageURL = Self.secure(item.url) else { return }

        if needsTitle { fetchingTitles.insert(item.id) }
        if needsIcon { fetchingIcons.insert(host) }

        pageClient.fetch(pageURL, headers: Self.headers) { data in
            let title = data.flatMap(PageMetadata.title(fromHTML:))
            let declaredIcon = data.flatMap { PageMetadata.iconURL(fromHTML: $0, page: pageURL) }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if needsTitle {
                    self.fetchingTitles.remove(item.id)
                    if let title, let index = self.items.firstIndex(where: { $0.id == item.id }) {
                        self.items[index].title = title
                        self.save()
                    }
                }
                if needsIcon {
                    let candidates = [declaredIcon, URL(string: "https://\(host)/favicon.ico")].compactMap { $0 }
                    self.fetchFirstIcon(candidates, host: host)
                }
            }
        }
    }

    private func fetchFirstIcon(_ candidates: [URL], host: String) {
        guard let url = candidates.first else {
            fetchingIcons.remove(host)
            return
        }
        iconClient.fetch(url, headers: Self.headers) { data in
            if let data, let image = NSImage(data: data), image.isValid {
                IconCache.store(data, forHost: host)
                DispatchQueue.main.async { [weak self] in
                    self?.icons[host] = image
                    self?.fetchingIcons.remove(host)
                }
            } else {
                DispatchQueue.main.async { [weak self] in self?.fetchFirstIcon(Array(candidates.dropFirst()), host: host) }
            }
        }
    }

    private static func secure(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "https"
        return components.url
    }

    private static var headers: [String: String] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return ["User-Agent": "MinNotch/\(version) (macOS; link preview)", "Accept": "text/html,image/*"]
    }

    // MARK: Persistence

    private var limit: Int { settings?.advanced.linkShelfLimit ?? 25 }

    private func enforceLimit() {
        guard items.count > limit else { return }
        items.removeLast(items.count - limit)
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([LinkItem].self, from: data) else { return }
        // Re-validated on the way in, since the stored list is a file on disk like any other.
        items = decoded.filter { Self.normalised($0.url) != nil }
        enforceLimit()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

/// Reads a title and an icon link out of the start of an HTML page, without a browser engine.
///
/// `NSAttributedString`'s HTML import would do it in one line, but it runs WebKit on the main
/// thread and loads the page's subresources, which is a lot of machinery and network for one
/// string. The head of a page is regular enough for a couple of patterns.
enum PageMetadata {
    static func title(fromHTML data: Data) -> String? {
        let html = decode(data)
        let candidates = [
            firstMatch(#"<meta[^>]+property=["']og:title["'][^>]*content=["']([^"']+)["']"#, in: html),
            firstMatch(#"<meta[^>]+content=["']([^"']+)["'][^>]*property=["']og:title["']"#, in: html),
            firstMatch(#"<title[^>]*>([^<]+)</title>"#, in: html)
        ]
        guard let raw = candidates.compactMap({ $0 }).first else { return nil }
        let title = decodeEntities(raw)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : String(title.prefix(200))
    }

    static func iconURL(fromHTML data: Data, page: URL) -> URL? {
        let html = decode(data)
        let patterns = [
            #"<link[^>]+rel=["'](?:apple-touch-icon|icon|shortcut icon)["'][^>]*href=["']([^"']+)["']"#,
            #"<link[^>]+href=["']([^"']+)["'][^>]*rel=["'](?:apple-touch-icon|icon|shortcut icon)["']"#
        ]
        for pattern in patterns {
            if let href = firstMatch(pattern, in: html),
               let url = URL(string: decodeEntities(href), relativeTo: page)?.absoluteURL,
               url.scheme?.lowercased() == "https" {
                return url
            }
        }
        return nil
    }

    private static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    static func decodeEntities(_ text: String) -> String {
        var result = text
        let named = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "]
        for (entity, character) in named { result = result.replacingOccurrences(of: entity, with: character) }

        guard let regex = try? NSRegularExpression(pattern: #"&#(x?)([0-9a-fA-F]+);"#) else { return result }
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..<result.endIndex, in: result))
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result),
                  let flag = Range(match.range(at: 1), in: result),
                  let digits = Range(match.range(at: 2), in: result),
                  let value = UInt32(result[digits], radix: result[flag].isEmpty ? 10 : 16),
                  let scalar = Unicode.Scalar(value) else { continue }
            result.replaceSubrange(whole, with: String(Character(scalar)))
        }
        return result
    }
}

/// Site icons on disk in Caches, named by a hash of the host.
enum IconCache {
    private static var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let bundle = Bundle.main.bundleIdentifier ?? "com.minnotch.MinNotch"
        return caches.appendingPathComponent(bundle).appendingPathComponent("LinkIcons")
    }

    private static func file(forHost host: String) -> URL {
        let digest = SHA256.hash(data: Data(host.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest)
    }

    static func image(forHost host: String) -> NSImage? {
        // A path this app built under its own Caches folder, not a URL from anywhere else,
        // which is the case `BoundedHTTPClient` exists for.
        guard let data = try? Data(contentsOf: file(forHost: host)) else { return nil }
        return NSImage(data: data)
    }

    static func store(_ data: Data, forHost host: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file(forHost: host), options: .atomic)
    }
}

#if DEBUG
extension LinkShelfService {
    /// Fixed links for a capture, with titles already filled in so nothing is fetched.
    func applySample() {
        items = [
            LinkItem(url: URL(string: "https://github.com/andrefongkc-cyber/mininotch")!, title: "GitHub - andrefongkc-cyber/mininotch"),
            LinkItem(url: URL(string: "https://lrclib.net/docs")!, title: "LRCLIB API Documentation"),
            LinkItem(url: URL(string: "https://en.wikipedia.org/wiki/Notch_(engineering)")!, title: "Notch (engineering) - Wikipedia"),
            LinkItem(url: URL(string: "https://developer.apple.com/documentation/swiftui/timelineview")!, title: nil)
        ]
    }
}
#endif
