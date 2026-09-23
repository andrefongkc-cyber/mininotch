import Foundation

/// Fetches time-synced lyrics from LRCLIB.
///
/// Apple Music's own synced lyrics are not exposed to AppleScript, and the `lyrics` property
/// of a streamed track is almost always empty, so reading the player locally only works for
/// files the user imported with lyrics already tagged. An online lookup is the only way the
/// feature works for streaming, which is what most people are doing.
///
/// LRCLIB was chosen because it needs no account, no API key, and no payload beyond the
/// track's title, artist, album, and length. It is still off by default: sending what
/// someone is listening to to a third party should be their decision, not a default.
final class LRCLIBClient: Sendable {
    static let shared = LRCLIBClient()

    private static let host = "lrclib.net"
    private let host = LRCLIBClient.host

    /// Locked to LRCLIB over HTTPS, with a ceiling on the reply.
    ///
    /// A lyrics query carries the title and artist of what is playing, so an off-host
    /// redirect would disclose that to somebody the user never agreed to tell. The size cap
    /// is generous for what a lyric sheet weighs and small enough that a hostile or broken
    /// reply cannot be buffered until the app runs out of memory.
    private let http = BoundedHTTPClient(
        maxBytes: 1_000_000,
        allowedHosts: [LRCLIBClient.host],
        timeout: 8
    )

    /// LRCLIB's documented response shape. Both lyric fields are nullable, and a track
    /// marked instrumental legitimately has neither.
    private struct Response: Decodable {
        var syncedLyrics: String?
        var plainLyrics: String?
        var instrumental: Bool?
        var duration: Double?
        var trackName: String?
        var artistName: String?
    }

    /// How far a candidate's length may differ from the playing track before its timings are
    /// assumed to belong to a different cut.
    ///
    /// A remix, a live take, or a radio edit carries the same title and artist and completely
    /// different timings, so accepting one produces lyrics that look right and scroll wrong.
    private static let durationTolerance: TimeInterval = 5

    /// Looks up `track`. The completion runs on the main queue, with nil for any failure,
    /// which is deliberately indistinguishable from "no lyrics exist": the caller shows the
    /// same thing either way and there is nothing useful a listener could do about a 503.
    ///
    /// Checks `LyricsCache` first, so a song played before costs no request at all, and a song
    /// LRCLIB recently had nothing for is not searched for again.
    func lyrics(for track: NowPlayingTrack, completion: @escaping @MainActor @Sendable (Lyrics?) -> Void) {
        guard !track.title.isEmpty, !track.artist.isEmpty else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        switch cache.lookup(track) {
        case .hit(let text):
            let parsed = LRCParser.parse(text)
            // A cached sheet that no longer parses to anything falls through to a fresh lookup
            // rather than being served as nothing.
            if !parsed.isEmpty {
                DispatchQueue.main.async { completion(parsed) }
                return
            }
        case .knownMissing:
            DispatchQueue.main.async { completion(nil) }
            return
        case .miss:
            break
        }

        fetchText(exactMatchURL(for: track)) { [weak self] text in
            guard let self else { completion(nil); return }
            if let text {
                self.cache.store(text, for: track)
                completion(LRCParser.parse(text))
                return
            }
            // The exact endpoint matches on duration within a couple of seconds, so a
            // remaster or a slightly different edit misses. Search is the wider net.
            self.fetchBestTextFromSearch(self.searchURL(for: track), targetDuration: track.duration) { outcome in
                switch outcome {
                case .found(let text):
                    self.cache.store(text, for: track)
                    completion(LRCParser.parse(text))
                case .noneFound:
                    self.cache.store(nil, for: track)
                    completion(nil)
                case .failed:
                    // Never cached: a dropped connection is not evidence the song has no
                    // lyrics, and remembering it as such would hide them for days.
                    completion(nil)
                }
            }
        }
    }

    private let cache = LyricsCache.shared

    /// How a search ended. Kept distinct from a plain optional because the cache has to tell
    /// "LRCLIB answered and had nothing" apart from "LRCLIB could not be reached".
    private enum SearchOutcome {
        case found(String)
        case noneFound
        case failed
    }

    // MARK: Requests

    private func exactMatchURL(for track: NowPlayingTrack) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/get"
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.duration.rounded())))
        ]
        return components.url
    }

    private func searchURL(for track: NowPlayingTrack) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/search"
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist)
        ]
        return components.url
    }

    /// LRCLIB asks clients to identify themselves so they can contact a misbehaving one.
    private var headers: [String: String] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return ["User-Agent": "MinNotch/\(version) (macOS notch utility)"]
    }

    /// Fetches the exact-match endpoint and returns the lyric text worth using, if any. Calls
    /// back on the main queue.
    private func fetchText(_ url: URL?, completion: @escaping @MainActor @Sendable (String?) -> Void) {
        guard let url else { DispatchQueue.main.async { completion(nil) }; return }

        http.fetch(url, headers: headers) { data in
            let text = Self.decode(data: data)
            DispatchQueue.main.async { completion(text) }
        }
    }

    /// Picks the search result closest in length to what is actually playing.
    ///
    /// Taking the first result is what made lyrics scroll out of step: a search for a popular
    /// song returns the album cut, the radio edit, live versions, and remixes, all with the
    /// same title and artist and none of them sharing timings. Length is the only thing in
    /// the response that distinguishes them.
    private func fetchBestTextFromSearch(
        _ url: URL?,
        targetDuration: TimeInterval,
        completion: @escaping @MainActor @Sendable (SearchOutcome) -> Void
    ) {
        guard let url else { DispatchQueue.main.async { completion(.failed) }; return }

        http.fetch(url, headers: headers) { data in
            guard let data,
                  let results = try? JSONDecoder().decode([Response].self, from: data)
            else {
                DispatchQueue.main.async { completion(.failed) }
                return
            }

            let ranked = results
                .compactMap { candidate -> (Response, TimeInterval)? in
                    guard let duration = candidate.duration else { return nil }
                    return (candidate, abs(duration - targetDuration))
                }
                .filter { $0.1 <= Self.durationTolerance }
                .sorted { $0.1 < $1.1 }

            // Better no lyrics than the wrong cut's. An unsynced sheet from a remix looks
            // fine and scrolls wrong, which is harder to notice than nothing at all.
            let text = ranked.lazy.compactMap { Self.text(from: $0.0) }.first
            DispatchQueue.main.async { completion(text.map(SearchOutcome.found) ?? .noneFound) }
        }
    }

    // MARK: Decoding

    /// The status code is checked by `BoundedHTTPClient`, which hands back nil for anything
    /// that is not a 200 within the size limit.
    private static func decode(data: Data?) -> String? {
        guard let data,
              let decoded = try? JSONDecoder().decode(Response.self, from: data)
        else { return nil }
        return text(from: decoded)
    }

    /// The lyric text worth keeping from one response: synced when it parses to something,
    /// otherwise plain, otherwise nothing.
    private static func text(from response: Response) -> String? {
        if response.instrumental == true { return nil }

        // Synced first: the whole point is highlighting the line being sung.
        if let synced = response.syncedLyrics, !synced.isEmpty, !LRCParser.parse(synced).isEmpty {
            return synced
        }
        if let plain = response.plainLyrics, !plain.isEmpty, !LRCParser.parse(plain).isEmpty {
            return plain
        }
        return nil
    }
}
