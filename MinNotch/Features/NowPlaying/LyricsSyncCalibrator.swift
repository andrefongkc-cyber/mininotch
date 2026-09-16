import Foundation

/// Works out how far a lyric file's timings sit from the audio that is actually playing, by
/// listening for the moment a voice comes in.
///
/// **Why this is needed at all.** Lyric files are transcribed by hand and their timings differ
/// between sources by a second or more, which no amount of clock accuracy can fix: the player's
/// position is right and the file is wrong. Until now the only answer was the manual offset
/// slider, which the user has to re-dial for every badly timed file.
///
/// **Why it only looks at phrase entries.** Matching lyric lines to onsets in general does not
/// work: a busy mix has an onset every beat, so a search over a two second window finds several
/// candidates and locks onto whichever the scoring likes, which is usually the drums. A line
/// that starts after a long gap in the lyrics is different: something enters there that was not
/// there a moment ago, and it is a voice. So only those lines are used, only the strongest
/// mid-band onset near each counts, and the answer is the median across several of them.
///
/// **It refuses rather than guesses.** With fewer than `minimumMatches` phrase entries matched,
/// or with the matches disagreeing by more than `maximumSpread`, there is no offset: an
/// instrumental track, a wrong lyric file, or a mix with no clear entries all land here, and all
/// of them should leave the timing alone rather than dragging it somewhere confident and wrong.
/// The correction is clamped to `limit` for the same reason.
struct LyricsSyncCalibrator {
    /// A pause in the lyrics this long means whatever starts next is a phrase entry.
    ///
    /// Five seconds, not two: ordinary lines in a sung verse are two to four seconds apart, so a
    /// shorter threshold calls every line an entry, and matching every line is exactly the
    /// drum-following that this avoids. A gap this long is an intro, a bridge, or an
    /// instrumental break, and what follows one is a voice coming back in. `--check-lyric-sync`
    /// caught the two second version treating all thirty-two of its test lines as entries.
    static let gapBeforeEntry: TimeInterval = 5
    /// How far either side of a phrase entry an onset may be and still be taken for that entry.
    /// Matches the clamp below, so a file that is off by nearly the maximum can still be measured.
    static let searchWindow: TimeInterval = 2
    /// Matched entries needed before any correction is applied.
    static let minimumMatches = 3
    /// Median absolute deviation allowed across the matches. Above this they disagree, which
    /// means the matching found noise rather than voices.
    static let maximumSpread: TimeInterval = 0.25
    /// Nothing is ever corrected by more than this, however confident the numbers look.
    static let limit: TimeInterval = 2

    /// Seconds to add to lyric timing, or nil while there is no trustworthy answer.
    private(set) var offset: TimeInterval?
    /// Phrase entries matched to an onset so far.
    private(set) var matchCount = 0
    /// How much the matches disagree, for the UI to show. Nil before there are any.
    private(set) var spread: TimeInterval?

    /// Phrase entry times from the lyric file, in seconds.
    private var entries: [TimeInterval] = []
    /// The strongest onset seen near each entry, by entry index.
    private var matches: [Int: (position: TimeInterval, strength: Double)] = [:]

    // MARK: Lifecycle

    /// Starts again for a new lyric file. Everything measured for the previous one is dropped,
    /// because the offset belongs to the file, not to the listener.
    mutating func begin(lyrics: Lyrics) {
        entries = Self.phraseEntries(of: lyrics)
        matches.removeAll()
        offset = nil
        matchCount = 0
        spread = nil
    }

    mutating func reset() {
        entries.removeAll()
        matches.removeAll()
        offset = nil
        matchCount = 0
        spread = nil
    }

    /// True when there is a lyric file with enough phrase entries to work with.
    var canMeasure: Bool { entries.count >= Self.minimumMatches }

    // MARK: Measuring

    /// Records an onset heard at `position` in the track, `strength` being how sharply the mid
    /// frequencies rose.
    mutating func noteOnset(at position: TimeInterval, strength: Double) {
        guard !entries.isEmpty else { return }

        // The nearest phrase entry, and only if the onset is close enough to be that entry.
        var bestIndex: Int?
        var bestDistance = Self.searchWindow
        for (index, entry) in entries.enumerated() {
            let distance = abs(position - entry)
            if distance <= bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        guard let index = bestIndex else { return }

        // A voice entering is the loudest new thing near its own entry, so the strongest onset
        // in the window is the one to keep. Taking the closest instead would just pick whichever
        // beat happened to land nearest the file's own timing, which is the thing being measured.
        if let existing = matches[index], existing.strength >= strength { return }
        matches[index] = (position, strength)
        recompute()
    }

    private mutating func recompute() {
        let deltas = matches.map { index, match in match.position - entries[index] }.sorted()
        matchCount = deltas.count
        guard deltas.count >= Self.minimumMatches else {
            offset = nil
            spread = nil
            return
        }

        let middle = Self.median(of: deltas)
        let deviation = Self.median(of: deltas.map { abs($0 - middle) }.sorted())
        spread = deviation

        guard deviation <= Self.maximumSpread else {
            offset = nil
            return
        }
        // The file is `middle` seconds early when the audio arrives later than it says, so the
        // correction is the other way round.
        offset = min(max(-middle, -Self.limit), Self.limit)
    }

    // MARK: Helpers

    /// Lines that start after a long enough pause in the lyrics, including the first line.
    static func phraseEntries(of lyrics: Lyrics) -> [TimeInterval] {
        let stamps = lyrics.lines.compactMap(\.timestamp).sorted()
        guard let first = stamps.first else { return [] }

        var entries = [first]
        for (previous, current) in zip(stamps, stamps.dropFirst()) where current - previous >= gapBeforeEntry {
            entries.append(current)
        }
        return entries
    }

    static func median(of sorted: [TimeInterval]) -> TimeInterval {
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[middle] }
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
}
