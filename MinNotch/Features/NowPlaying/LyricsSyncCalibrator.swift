import Foundation

/// Works out how far a lyric file's timings sit from the audio that is actually playing, by
/// listening for where the singing starts.
///
/// **Why this is needed at all.** Lyric files are transcribed by hand and their timings differ
/// between sources by a second or more, which no amount of clock accuracy can fix: the player's
/// position is right and the file is wrong. LRCLIB alone has a dozen uploads of one popular song,
/// each a slightly different length.
///
/// **How it measures.** The audio tap reports the level of whatever is singing
/// (`SpectrumFrameAnalyzer.Frame.voiceLevel`: the centre of the stereo image in the voice's
/// range), placed on the track's own clock. Each moment's *rise* is how much louder the next
/// eighth of a second is than the quarter second before it, which is large where a voice comes in
/// and small elsewhere. Then every offset within `searchWindow` is tried at once: the score of an
/// offset is the rise found at every sung line's start, moved by that offset. The right offset
/// lines all of them up with the singer drawing breath and starting again; any other lands most
/// of them in the middle of a phrase.
///
/// **What it replaced, and why.** It used to wait for lines after a five second gap, take the
/// strongest jump in the 94 Hz to 1.5 kHz bands within two seconds of each, and use the median.
/// Those bands hold the kick, the snare and the bass as much as the voice, and after a break the
/// band usually comes back in before the singer does, so it locked onto the drums with
/// confidence. On a real song it moved well timed lyrics by a second or more, differently from one
/// song to the next: "sometimes accurate, sometimes behind, sometimes ahead". `--check-lyric-sync
/// --audio` runs a real song through both.
///
/// **It refuses rather than guesses.** No correction until `minimumMatches` sung lines have been
/// heard with the audio either side of them; none when the best offset does not stand clearly
/// above every other (`distinctness`); none when line starts are no more special than any other
/// moment of the track (`minimumSignificance`: an instrumental, or the wrong file); none when the
/// best offset is at the edge of the window, or something up to twelve seconds out fits better
/// (`isBestFarAndWide`), which both mean the truth lies beyond the window. A new answer must hold
/// while more lines are heard before it is applied. And a file that scores nearly as well where it
/// is, is left where it is: a well timed file must never be moved by noise.
struct LyricsSyncCalibrator {
    /// The furthest a file is ever moved, and so the range of offsets tried.
    static let searchWindow: TimeInterval = 2
    /// Offsets are tried this far apart, and the track's clock is kept in bins this wide.
    static let step: TimeInterval = 0.05
    /// Sung lines heard, with the audio across the whole search window around them, before any
    /// answer is given.
    static let minimumMatches = 8
    /// The best offset's score must beat every offset more than `peakWidth` from it by this many
    /// decibels of rise per line. A margin rather than a ratio, because breaks are a penalty and
    /// scores can go below zero, where a ratio says nothing.
    ///
    /// Set from a real song: the right answer stood 0.64 to 0.98 dB clear at every offset tried,
    /// and a file too far out to measure, at three different distances, at most 0.28.
    static let distinctness = 0.45
    /// The margin must also be this share of the rise itself, so a loud mix cannot clear the
    /// margin on loudness alone.
    static let relativeDistinctness = 0.15
    static let peakWidth: TimeInterval = 0.3
    /// Standard errors by which line starts must stand above random moments of the same track
    /// (`significance`). Below it nothing in the audio is starting where lines start, whatever
    /// the offset: there is no voice to match.
    ///
    /// Set from real audio. A sung song lined up with its own lyrics scored 3.9 at every offset it
    /// was moved by; the same lyrics against three instrumentals, at seven offsets each, at most
    /// 3.1, and against the song itself when too far out to measure, at most 2.6. An absolute bar
    /// on the rise was tried first and could not work: the instrumentals rose more than the song.
    static let minimumSignificance = 3.5
    /// How far either side of a moved line start its rise is looked for: a singer is not exact.
    /// Weighted down linearly to nothing at this distance, so the score still peaks where the
    /// rise is rather than across a flat top as wide as the tolerance, whose first edge is a
    /// tenth of a second out.
    static let lineTolerance: TimeInterval = 0.15
    /// The rise is the next `riseAhead` seconds against the `riseBehind` before. Short, so the
    /// rise peaks at the moment singing starts rather than across the half second around it: a
    /// broad peak scores offsets a third of a second out nearly as well as the right one.
    static let riseAhead: TimeInterval = 0.12
    static let riseBehind: TimeInterval = 0.25
    /// No single moment counts for more than this, so one loud entry cannot outvote the rest.
    static let maximumRise: Double = 18

    /// Seconds to add to lyric timing, or nil while there is no trustworthy answer. Zero means
    /// the file was measured and found on time.
    private(set) var offset: TimeInterval?
    /// True while `offset` is one remembered from an earlier play rather than measured in this
    /// one. Early in a song the evidence is thin, so a remembered answer is not withdrawn for it;
    /// it is replaced only by a new answer measured and confirmed in this play.
    private(set) var isRestored = false
    /// Sung lines heard so far with the audio across the search window around them.
    private(set) var matchCount = 0
    /// How far the best offset stands above the next best, in decibels of rise per line, once
    /// there is a score.
    private(set) var confidence: Double?
    /// The average rise, in decibels, at the line starts under the best offset.
    private(set) var strength: Double?
    /// How far that average stands above the average of any moment in the track, in standard
    /// errors: how unlikely it is that line starts land on rises this large by chance.
    private(set) var significance: Double?

    /// Start times of the lines that have words, from the lyric file, with how much each one
    /// counts.
    private var lineStarts: [TimeInterval] = []
    private var lineWeights: [TimeInterval: Double] = [:]
    /// The instrumental breaks in the file: from a little after the last line before a long gap
    /// to just before the first line after it. Nobody should start singing in one.
    private var breaks: [(quiet: ClosedRange<TimeInterval>, lineAfter: TimeInterval)] = []
    /// The largest rise heard at each step of the track's clock, NaN where nothing was heard.
    private var rises: [Float] = []
    /// Recent levels on the wall clock, kept for working out each moment's rise.
    private var recent: [(time: TimeInterval, position: TimeInterval, level: Double)] = []
    private var samplesSinceDecision = 0
    /// An answer waiting to be confirmed, and how many lines had been heard when it was first given.
    private var pending: (offset: TimeInterval, since: Int)?
    /// Lines heard at the last wide check.
    private var lastWideCheck = 0

    // MARK: Lifecycle

    /// Starts again for a new lyric file. Everything measured for the previous one is dropped,
    /// because the offset belongs to the file, not to the listener.
    mutating func begin(lyrics: Lyrics) {
        reset()
        let stamps = lyrics.lines.compactMap(\.timestamp).sorted()
        lineStarts = lyrics.lines
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .compactMap(\.timestamp)
            .sorted()
        for start in lineStarts {
            let previous = stamps.last { $0 < start }
            lineWeights[start] = Self.weight(gapBefore: previous.map { start - $0 } ?? Self.entryGap)
        }
        for (previous, next) in zip(lineStarts, lineStarts.dropFirst()) where next - previous >= Self.entryGap {
            // The last line before a break is still being sung for a while after it starts.
            let quiet = (previous + Self.lastLineLength)...(next - 0.4)
            if quiet.upperBound - quiet.lowerBound >= 1 { breaks.append((quiet, next)) }
        }
    }

    /// How long the last line before a break is assumed to go on being sung.
    static let lastLineLength: TimeInterval = 2.5

    /// A line after a pause counts for more, up to `entryWeight` times as much.
    ///
    /// Singers start lines on the beat, often on every bar, so moving a file by one bar lines most
    /// line starts up with *some* line start, and on a real song that scored 85% of the right
    /// answer. A line after a pause does not repeat that way: one bar early is still the break,
    /// one bar late is the middle of singing, and neither rises. Weighting those lines is what
    /// separates the right offset from the bar either side of it.
    static func weight(gapBefore: TimeInterval) -> Double {
        let fraction = min(max((gapBefore - 2) / (entryGap - 2), 0), 1)
        return 1 + (entryWeight - 1) * fraction
    }

    /// A gap before a line this long or longer makes it a phrase entry, at full weight.
    static let entryGap: TimeInterval = 5
    static let entryWeight: Double = 3

    /// Applies an answer measured on an earlier play of the same track and file.
    mutating func restore(offset remembered: TimeInterval) {
        offset = remembered
        isRestored = true
    }

    mutating func reset() {
        isRestored = false
        lineStarts.removeAll()
        lineWeights.removeAll()
        breaks.removeAll()
        rises.removeAll()
        recent.removeAll()
        offset = nil
        matchCount = 0
        confidence = nil
        strength = nil
        significance = nil
        pending = nil
        lastWideCheck = 0
        samplesSinceDecision = 0
    }

    /// True when there is a lyric file with enough sung lines to work with.
    var canMeasure: Bool { lineStarts.count >= Self.minimumMatches }

    // MARK: Measuring

    /// Records the voice level heard at `time` on the wall clock, when the track was at
    /// `position`. Called for every window the tap analyses, while a synced file plays.
    mutating func noteVoiceLevel(_ level: Double, at position: TimeInterval, time: TimeInterval) {
        guard !lineStarts.isEmpty else { return }

        // A seek, a pause or a stall breaks the link between the two clocks. A rise worked out
        // across one would compare two unrelated parts of the song, so start the window again.
        if let last = recent.last, abs((position - last.position) - (time - last.time)) > 0.3 || time < last.time {
            recent.removeAll()
        }
        recent.append((time, position, level))

        // The moment `riseAhead` ago now has both sides of its window.
        let judgedTime = time - Self.riseAhead
        if let judged = recent.lastIndex(where: { $0.time <= judgedTime }),
           recent[0].time <= judgedTime - Self.riseBehind {
            let moment = recent[judged]
            let before = recent.filter { $0.time < moment.time && $0.time >= moment.time - Self.riseBehind }
            let after = recent.filter { $0.time >= moment.time }
            if !before.isEmpty, !after.isEmpty {
                let rise = Self.mean(after.map(\.level)) - Self.mean(before.map(\.level))
                record(min(max(rise, 0), Self.maximumRise), at: moment.position)
            }
        }
        recent.removeAll { $0.time < time - Self.riseAhead - Self.riseBehind - 0.05 }

        // Deciding is a sweep over every line and offset, so it runs about once a second, not
        // for every window.
        samplesSinceDecision += 1
        if samplesSinceDecision >= 60 {
            samplesSinceDecision = 0
            decide()
        }
    }

    private mutating func record(_ rise: Double, at position: TimeInterval) {
        guard position >= 0 else { return }
        let bin = Int(position / Self.step)
        if bin >= rises.count {
            rises.append(contentsOf: [Float](repeating: .nan, count: bin - rises.count + 1))
        }
        rises[bin] = rises[bin].isNaN ? Float(rise) : max(rises[bin], Float(rise))
    }

    /// Scores every offset in the window over the lines heard so far, and settles on one only
    /// when the answer is clear.
    mutating func decide() {
        // Only lines whose whole window has been heard, so every offset is scored on the same
        // lines and none wins by being the only one with data.
        let lines = lines(heardWithin: Self.searchWindow)
        matchCount = lines.count
        guard lines.count >= Self.minimumMatches else { return }

        // An answer already given is checked again against the wider window as more of the song
        // is heard: the first check had fewer lines to go on, and a song's repeats can fool it.
        if let offset, offset != 0, !isRestored, matchCount >= lastWideCheck + Self.recheckEvery {
            lastWideCheck = matchCount
            // Withdrawn only when something out there now fits better outright, not merely when the
            // margin has narrowed, or the lyrics would hop back and forth across the threshold.
            if !isBestFarAndWide(at: -offset, margin: 0) {
                self.offset = nil
                pending = nil
                return
            }
        }

        guard let candidate = measure(lines) else {
            pending = nil
            // Unclear right now. An answer already given stands, because lyrics that jump back and
            // forth as the evidence wobbles are worse than lyrics that move once; unless the
            // singing has stopped standing out at the line starts at all, which means the answer
            // was a coincidence of the first lines heard.
            if offset != nil, !isRestored, (significance ?? 0) < Self.minimumSignificance * 0.8 { offset = nil }
            return
        }
        if let offset, abs(offset - candidate) <= 0.1 {
            pending = nil
            // Measured again in this play and still right: it is this play's answer now.
            isRestored = false
            return
        }
        // A new answer has to hold while more of the song is heard before the lyrics move to it.
        // Early on a handful of lines can line up with an offset by chance; on a real song the
        // first answer was a second and a half out on a file that was on time, and changed four
        // times before it settled.
        if let pending, abs(pending.offset - candidate) <= 0.1 {
            guard matchCount >= pending.since + Self.confirmations else { return }
            self.pending = nil
            // Checked once, as the answer is about to be applied, because it is a sweep over
            // twelve seconds either way rather than two.
            if candidate == 0 || isBestFarAndWide(at: -candidate) {
                offset = candidate
                isRestored = false
                lastWideCheck = matchCount
            }
        } else {
            pending = (candidate, matchCount)
        }
    }

    /// More lines heard, still agreeing, before an answer is applied.
    static let confirmations = 2
    /// An applied answer is checked against the wide window again after this many more lines.
    static let recheckEvery = 6
    /// Lines with the whole wide window heard around them, before the wide check will pass.
    static let minimumWideMatches = 14
    /// How far out a better match is looked for before an answer inside the window is trusted.
    static let wideWindow: TimeInterval = 12

    /// The offset these lines say to apply, zero for a file that is on time, or nil when they say
    /// nothing clearly.
    private mutating func measure(_ lines: [TimeInterval]) -> TimeInterval? {
        let offsets = Self.offsets
        let heard = Set(lines)
        let scores = offsets.map { score(lines, heard: heard, shiftedBy: $0) }
        guard let bestIndex = scores.indices.max(by: { scores[$0] < scores[$1] }) else { return nil }
        let best = scores[bestIndex]
        let bestOffset = offsets[bestIndex]
        let runnerUp = offsets.indices
            .filter { abs(offsets[$0] - bestOffset) > Self.peakWidth }
            .map { scores[$0] }
            .max() ?? best
        let totalWeight = lines.reduce(0) { $0 + (lineWeights[$1] ?? 1) }
        confidence = (best - runnerUp) / totalWeight
        strength = reward(lines, shiftedBy: bestOffset) / totalWeight
        significance = significance(of: strength ?? 0, lines: lines)

        let onTime = scores[offsets.firstIndex { abs($0) < Self.step / 2 } ?? bestIndex]
        let isClear = (confidence ?? 0) >= Self.distinctness
            && (confidence ?? 0) >= (strength ?? .infinity) * Self.relativeDistinctness
        let isVoice = (significance ?? 0) >= Self.minimumSignificance
        let isInside = abs(bestOffset) < Self.searchWindow - Self.step / 2

        guard isVoice else { return nil }
        // Within a tenth of the margin a clear answer needs, the file is as good as the best:
        // leave it where it is.
        let candidate: TimeInterval
        if best - onTime <= Self.distinctness * 0.1 * totalWeight, isClear {
            candidate = 0
        } else {
            guard isClear, isInside else { return nil }
            // Audio later than the file means the lines must come later, so the offset is the
            // other way round from the shift that lined them up.
            candidate = -bestOffset
        }
        return candidate
    }

    /// True when nothing up to `wideWindow` away fits better than `shift`.
    ///
    /// A song repeats itself: on a real one, every four bars, about nine seconds. So a file that
    /// far out lines up with the wrong phrase somewhere inside the window, nearly as well as the
    /// right offset would. The right offset, out beyond the window, still fits better than that,
    /// and finding it there means the file is too far out to correct, not that the alias is
    /// right. Only lines heard with the whole wide window around them are used, or a large shift
    /// would score nothing simply for reaching past what has been heard yet; until there are
    /// enough of them this says no, which waits.
    private func isBestFarAndWide(at shift: TimeInterval, margin marginPerLine: Double = distinctness * 0.5) -> Bool {
        let lines = lines(heardWithin: Self.wideWindow)
        guard lines.count >= Self.minimumWideMatches else { return false }
        let heard = Set(lines)
        let here = score(lines, heard: heard, shiftedBy: shift)
        // Clear of everything else by half the margin a clear answer needs in the window. The
        // whole margin was too much: a song's four bar repeat is close to the real thing by
        // nature, and right answers waited till the last minute of the song and were then
        // withdrawn. Half still refused a file nine seconds out, whose real offset, out beyond
        // the window, scored 103 to the 65 of the repeat inside it.
        let margin = marginPerLine * lines.reduce(0) { $0 + (lineWeights[$1] ?? 1) }
        let count = Int((Self.wideWindow / Self.step).rounded())
        for index in -count...count {
            let other = Double(index) * Self.step
            guard abs(other - shift) > Self.peakWidth else { continue }
            if score(lines, heard: heard, shiftedBy: other) > here - margin { return false }
        }
        return true
    }

    #if DEBUG
    /// The score at every offset up to `window` either way, for `--check-lyric-sync`.
    func debugScores(window: TimeInterval) -> [(offset: TimeInterval, score: Double)] {
        let lines = lines(heardWithin: window)
        let heard = Set(lines)
        let count = Int((window / Self.step).rounded())
        return (-count...count).map { index in
            let shift = Double(index) * Self.step
            return (shift, score(lines, heard: heard, shiftedBy: shift))
        }
    }
    #endif

    /// Standard errors by which `average` stands above what a line start scores when it lands on
    /// any moment of the track at random.
    ///
    /// Electronic music, with its stabs and leads in the middle of the mix, jumps in the voice's
    /// range far more than a sung track does, so an absolute bar on the rise passed instrumentals
    /// and refused songs. What a voice does that a synth does not is start where the lines start,
    /// so the test is whether line starts are any more special than moments taken at random from
    /// the same audio.
    private func significance(of average: Double, lines: [TimeInterval]) -> Double? {
        let reach = Int((Self.lineTolerance / Self.step).rounded(.up))
        var values: [Double] = []
        values.reserveCapacity(rises.count)
        for centre in rises.indices where !rises[centre].isNaN {
            var largest: Double = 0
            for bin in max(0, centre - reach)...min(rises.count - 1, centre + reach) where !rises[bin].isNaN {
                let weight = max(0, 1 - abs(Double(bin - centre)) * Self.step / Self.lineTolerance)
                largest = max(largest, Double(rises[bin]) * weight)
            }
            values.append(largest)
        }
        guard values.count > 100 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
        // Weighted lines count as fewer independent ones.
        let weights = lines.map { lineWeights[$0] ?? 1 }
        let effective = pow(weights.reduce(0, +), 2) / max(weights.reduce(0) { $0 + $1 * $1 }, 1)
        guard variance > 0 else { return nil }
        return (average - mean) / (variance.squareRoot() / effective.squareRoot())
    }

    private func lines(heardWithin window: TimeInterval) -> [TimeInterval] {
        let reach = window + Self.lineTolerance
        return lineStarts.filter { heardFraction(from: $0 - reach, to: $0 + reach) >= 0.9 }
    }

    /// The sum, over `lines`, of the largest rise near each line start moved by `shift`, each
    /// weighted by how near it is; less the largest rise inside each instrumental break moved the
    /// same way.
    ///
    /// The breaks are what rule out the bar after the right answer. Moved one bar late, most line
    /// starts land on the next line's start and still score, but the first line after each break
    /// is then really sung a bar before the file says, which is inside the break as moved.
    private func score(_ lines: [TimeInterval], shiftedBy shift: TimeInterval) -> Double {
        score(lines, heard: Set(lines), shiftedBy: shift)
    }

    private func score(_ lines: [TimeInterval], heard heardLines: Set<TimeInterval>, shiftedBy shift: TimeInterval) -> Double {
        var penalty: Double = 0
        for (quiet, after) in breaks {
            // Only breaks whose following line is scored, so every offset pays for the same ones.
            guard heardLines.contains(after) else { continue }
            let first = max(0, Int(((quiet.lowerBound + shift) / Self.step).rounded()))
            let last = Int(((quiet.upperBound + shift) / Self.step).rounded())
            var largest: Float = 0
            if last >= first {
                for bin in first...last where bin < rises.count && !rises[bin].isNaN {
                    largest = max(largest, rises[bin])
                }
            }
            penalty += Double(largest) * Self.entryWeight
        }
        return reward(lines, shiftedBy: shift) - penalty
    }

    private func reward(_ lines: [TimeInterval], shiftedBy shift: TimeInterval) -> Double {
        let reach = Int((Self.lineTolerance / Self.step).rounded(.up))
        return lines.reduce(0) { total, start in
            let target = (start + shift) / Self.step
            let centre = Int(target.rounded())
            var largest: Double = 0
            for bin in (centre - reach)...(centre + reach) where bin >= 0 && bin < rises.count && !rises[bin].isNaN {
                // A bin holds the moments from its start to the next, so its middle is half a step on.
                let distance = abs(Double(bin) + 0.5 - target) * Self.step
                let weight = max(0, 1 - distance / Self.lineTolerance)
                largest = max(largest, Double(rises[bin]) * weight)
            }
            return total + largest * (lineWeights[start] ?? 1)
        }
    }

    private func heardFraction(from start: TimeInterval, to end: TimeInterval) -> Double {
        let first = max(0, Int(start / Self.step))
        let last = Int(end / Self.step)
        guard last >= first else { return 0 }
        let heard = (first...last).filter { $0 < rises.count && !rises[$0].isNaN }.count
        return Double(heard) / Double(last - first + 1)
    }

    /// Every offset tried, from one end of the window to the other.
    private static let offsets: [TimeInterval] = {
        let count = Int((searchWindow / step).rounded())
        return (-count...count).map { Double($0) * step }
    }()

    private static func mean(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(max(values.count, 1))
    }
}

/// What the lyric measurement says, for views: the answer and how much it has heard. Published
/// separately from the calibrator, which changes ninety times a second as it listens; views
/// watching it directly redrew at that rate.
struct LyricsSyncSummary: Equatable {
    var offset: TimeInterval?
    var matchCount = 0
}

/// Measured lyric offsets, remembered per track and lyric file, so a song played again is right
/// from its first line instead of from two minutes in.
///
/// Keyed by a hash of the track and every timing in the file, so a different file for the same
/// track, or the same file under another track, starts afresh; and so the store holds numbers,
/// not a list of what has been played. Kept to the most recent `limit`.
enum LyricsSyncMemory {
    private static let defaultsKey = "lyricsSync.offsets"
    static let limit = 500

    static func key(track: String, lyrics: Lyrics) -> String {
        let timings = lyrics.lines.compactMap(\.timestamp).map { String(Int(($0 * 100).rounded())) }
        // FNV-1a, because Swift's own hash is seeded differently on every launch.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in (track + "|" + timings.joined(separator: ",")).utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    static func offset(for key: String, defaults: UserDefaults = .standard) -> TimeInterval? {
        guard let entry = (defaults.dictionary(forKey: defaultsKey) as? [String: [Double]])?[key], let first = entry.first else { return nil }
        return first
    }

    /// Remembers an answer, or forgets one that was withdrawn.
    static func store(_ offset: TimeInterval?, for key: String, defaults: UserDefaults = .standard) {
        var entries = (defaults.dictionary(forKey: defaultsKey) as? [String: [Double]]) ?? [:]
        if let offset {
            entries[key] = [offset, Date().timeIntervalSinceReferenceDate]
        } else {
            entries.removeValue(forKey: key)
        }
        if entries.count > limit {
            let oldest = entries.sorted { ($0.value.last ?? 0) < ($1.value.last ?? 0) }.prefix(entries.count - limit)
            for (key, _) in oldest { entries.removeValue(forKey: key) }
        }
        defaults.set(entries, forKey: defaultsKey)
    }
}
