import AppKit

/// Supplies lyrics for a track.
///
/// V1 reads whatever the player already has locally. Nothing is fetched from the network:
/// a lyrics API means an account, a rate limit, and a privacy story, all of which belong in
/// their own release. A network provider slots in behind this protocol later without the
/// view or the controller changing.
protocol LyricsProviding {
    func lyrics(for track: NowPlayingTrack) -> Lyrics?
}

/// Reads the lyrics field of the current Music.app track.
///
/// Apple Music stores unsynced lyrics in that field, but a good number of libraries carry
/// LRC-formatted text there because that is what most tagging tools write, so the parser
/// tries LRC first and falls back to plain lines.
struct AppleMusicLyricsProvider: LyricsProviding {
    func lyrics(for track: NowPlayingTrack) -> Lyrics? {
        guard track.sourceKind == .appleMusic else { return nil }
        guard AppleScriptRunner.isRunning(bundleIdentifier: "com.apple.Music") else { return nil }

        let script = "tell application \"Music\" to get lyrics of current track"
        guard let text = AppleScriptRunner.shared.runReturningString(script),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        return LRCParser.parse(text)
    }
}

/// Parses LRC text, falling back to unsynced lines when no timestamps are present.
///
/// Handles both the plain format, where each line carries one `[mm:ss.xx]` stamp, and the
/// enhanced format, where each word additionally carries a `<mm:ss.xx>` stamp. Enhanced LRC
/// is uncommon, so when it is absent the per-word timing is estimated instead: without that
/// estimate the karaoke highlight would only ever work on a small minority of tracks.
enum LRCParser {
    /// `[mm:ss.xx]` or `[mm:ss]` line stamp.
    private static let lineTag = try? NSRegularExpression(
        pattern: "\\[(\\d{1,2}):(\\d{2})(?:[.:](\\d{1,3}))?\\]"
    )
    /// `<mm:ss.xx>` word stamp used by enhanced LRC.
    private static let wordTag = try? NSRegularExpression(
        pattern: "<(\\d{1,2}):(\\d{2})(?:[.:](\\d{1,3}))?>"
    )

    /// How long the final line is assumed to last, since nothing follows it to bound it.
    private static let trailingLineDuration: TimeInterval = 4

    static func parse(_ text: String) -> Lyrics {
        var lines: [LyricLine] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let stamps = times(of: lineTag, in: line)
            let body = removing(lineTag, from: line).trimmingCharacters(in: .whitespaces)
            let plain = removing(wordTag, from: body)
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespaces)

            if stamps.isEmpty {
                // A metadata tag such as [ar:Artist] carries no lyric content.
                guard !line.hasPrefix("["), !plain.isEmpty else { continue }
                lines.append(LyricLine(timestamp: nil, text: plain))
                continue
            }

            guard !plain.isEmpty else { continue }
            let tagged = taggedWords(in: body)

            // One line can carry several stamps when a refrain repeats. Word stamps are
            // absolute times, so they only describe the first of those occurrences.
            for (index, stamp) in stamps.enumerated() {
                lines.append(
                    LyricLine(timestamp: stamp, text: plain, words: index == 0 ? tagged : [])
                )
            }
        }

        if lines.contains(where: { $0.timestamp != nil }) {
            lines.sort { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }
        }

        return Lyrics(lines: resolveWordTimings(lines))
    }

    // MARK: Word timing

    /// Splits a line on its `<mm:ss.xx>` stamps. Each stamp starts the text that follows it.
    ///
    /// Ends are left at zero here and filled in by `resolveWordTimings`, which is the only
    /// place that knows where the line stops.
    private static func taggedWords(in body: String) -> [LyricWord] {
        guard let wordTag else { return [] }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        let matches = wordTag.matches(in: body, range: range)
        guard !matches.isEmpty else { return [] }

        var words: [LyricWord] = []
        for (index, match) in matches.enumerated() {
            guard let start = time(from: match, in: body),
                  let tagRange = Range(match.range, in: body) else { continue }

            let textEnd = index + 1 < matches.count
                ? Range(matches[index + 1].range, in: body)?.lowerBound ?? body.endIndex
                : body.endIndex

            let text = String(body[tagRange.upperBound..<textEnd])
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            words.append(LyricWord(text: text, start: start, end: start))
        }
        return words
    }

    /// Bounds every line and gives each of its words a start and an end.
    ///
    /// A line ends when the next one begins. Words without real stamps are spread across
    /// that window in proportion to their length, which tracks singing closely enough that
    /// the highlight lands on the right word for normally paced vocals.
    private static func resolveWordTimings(_ lines: [LyricLine]) -> [LyricLine] {
        var result = lines

        for index in result.indices {
            guard let start = result[index].timestamp else { continue }

            let lineEnd = nextTimestamp(after: index, in: result) ?? (start + trailingLineDuration)
            guard lineEnd > start else { continue }

            if result[index].words.isEmpty {
                result[index].words = spread(result[index].text, from: start, to: lineEnd)
            } else {
                // Close each tagged word at the next one's start, and the last at the line end.
                for wordIndex in result[index].words.indices {
                    let next = wordIndex + 1 < result[index].words.count
                        ? result[index].words[wordIndex + 1].start
                        : lineEnd
                    result[index].words[wordIndex].end = max(next, result[index].words[wordIndex].start)
                }
            }
        }

        return result
    }

    private static func nextTimestamp(after index: Int, in lines: [LyricLine]) -> TimeInterval? {
        var cursor = index + 1
        while cursor < lines.count {
            if let timestamp = lines[cursor].timestamp, timestamp > (lines[index].timestamp ?? 0) {
                return timestamp
            }
            cursor += 1
        }
        return nil
    }

    private static func spread(_ text: String, from start: TimeInterval, to end: TimeInterval) -> [LyricWord] {
        let tokens = text.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return [] }

        // A one-character word still takes time to sing, so every token gets a floor.
        let weights = tokens.map { Double(max($0.count, 2)) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return [] }

        var words: [LyricWord] = []
        var cursor = start
        for (index, token) in tokens.enumerated() {
            let duration = (end - start) * weights[index] / total
            words.append(LyricWord(text: token, start: cursor, end: cursor + duration))
            cursor += duration
        }
        return words
    }

    // MARK: Regex helpers

    private static func times(of regex: NSRegularExpression?, in line: String) -> [TimeInterval] {
        guard let regex else { return [] }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.matches(in: line, range: range).compactMap { time(from: $0, in: line) }
    }

    private static func time(from match: NSTextCheckingResult, in line: String) -> TimeInterval? {
        func group(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: line) else { return nil }
            return String(line[range])
        }
        guard let minutes = group(1).flatMap(Double.init),
              let seconds = group(2).flatMap(Double.init) else { return nil }

        var fraction = 0.0
        if let raw = group(3), let value = Double(raw) {
            fraction = value / pow(10, Double(raw.count))
        }
        return minutes * 60 + seconds + fraction
    }

    private static func removing(_ regex: NSRegularExpression?, from line: String) -> String {
        guard let regex else { return line }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.stringByReplacingMatches(in: line, range: range, withTemplate: "")
    }
}
