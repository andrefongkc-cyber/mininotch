import CryptoKit
import Foundation

/// Remembers what LRCLIB returned for a track, so replaying a song does not look it up again.
///
/// Stores the raw lyric text rather than the parsed `Lyrics`, and parses on the way out.
/// Parsing is cheap, and keeping the text means a change to the parser, such as better word
/// timing, applies to cached songs as well as new ones instead of being frozen at whatever the
/// parser did the day the song was first played.
///
/// Also remembers a genuine "LRCLIB has nothing for this", for a few days, so a track with no
/// lyrics is not searched for on every replay. Only a *successful* search that finds no match
/// counts. A dropped connection or a server error is never cached, or one flaky moment would
/// hide a song's lyrics for days.
///
/// Files live in the Caches directory, which macOS may clear on its own, and each is named by
/// a hash of the track rather than its title, so the folder listing does not read as a
/// listening history. The whole cache is deleted when the online lookup is switched off.
final class LyricsCache {
    static let shared = LyricsCache()

    enum Lookup: Equatable {
        /// Lyric text was stored for this track.
        case hit(String)
        /// LRCLIB was asked recently and had nothing.
        case knownMissing
        /// Never asked, or the answer has expired.
        case miss
    }

    /// Found lyrics are kept a long time: a song's words do not change.
    static let foundLifetime: TimeInterval = 180 * 24 * 3600
    /// "Nothing found" is kept briefly, because someone may upload lyrics next week.
    static let missingLifetime: TimeInterval = 3 * 24 * 3600
    /// Above this many files the oldest are removed, so the folder cannot grow without bound.
    static let maximumEntries = 1500

    private struct Entry: Codable {
        /// Nil records a successful lookup that found nothing.
        var text: String?
        var fetchedAt: Date
    }

    private let directory: URL
    private let queue = DispatchQueue(label: "com.minnotch.lyrics-cache")
    private let fileManager = FileManager.default

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let bundle = Bundle.main.bundleIdentifier ?? "com.minnotch.MinNotch"
            self.directory = caches.appendingPathComponent(bundle).appendingPathComponent("Lyrics")
        }
    }

    // MARK: Reading and writing

    func lookup(_ track: NowPlayingTrack) -> Lookup {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL(for: track)),
                  let entry = try? JSONDecoder().decode(Entry.self, from: data)
            else { return .miss }

            let age = Date().timeIntervalSince(entry.fetchedAt)
            if let text = entry.text {
                return age < Self.foundLifetime ? .hit(text) : .miss
            }
            return age < Self.missingLifetime ? .knownMissing : .miss
        }
    }

    /// Records a lookup's answer. `nil` means LRCLIB answered and had nothing.
    func store(_ text: String?, for track: NowPlayingTrack) {
        queue.async { [self] in
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(Entry(text: text, fetchedAt: Date()))
                try data.write(to: fileURL(for: track), options: .atomic)
                pruneIfNeeded()
            } catch {
                AppLog.media.error("Lyrics cache write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Deletes every cached answer.
    func removeAll() {
        queue.sync {
            guard fileManager.fileExists(atPath: directory.path) else { return }
            try? fileManager.removeItem(at: directory)
        }
    }

    /// Number of stored answers, found and missing together. For the debug check.
    var count: Int {
        queue.sync {
            (try? fileManager.contentsOfDirectory(atPath: directory.path).count) ?? 0
        }
    }

    // MARK: Internals

    /// Everything that identifies a particular recording, including its length rounded to the
    /// second, so a radio edit and the album cut are cached separately just as LRCLIB matches
    /// them separately.
    static func key(for track: NowPlayingTrack) -> String {
        [track.artist, track.title, track.album]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "\u{1F}") + "\u{1F}\(Int(track.duration.rounded()))"
    }

    private func fileURL(for track: NowPlayingTrack) -> URL {
        let digest = SHA256.hash(data: Data(Self.key(for: track).utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("json")
    }

    /// Removes the oldest fifth once the folder passes its cap. Runs on the cache queue.
    private func pruneIfNeeded() {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path),
              names.count > Self.maximumEntries else { return }

        let dated = names.compactMap { name -> (URL, Date)? in
            let url = directory.appendingPathComponent(name)
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return date.map { (url, $0) }
        }
        .sorted { $0.1 < $1.1 }

        for (url, _) in dated.prefix(names.count / 5) {
            try? fileManager.removeItem(at: url)
        }
    }
}
