#if DEBUG
import Foundation

/// Checks that matching lyrics to the audio recovers an offset it is given, and refuses one it
/// is not.
///
/// Run with `MinNotch --check-lyric-sync [--out f]`.
///
/// The measurement cannot be judged by playing a song and squinting at the strip: the thing being
/// measured is exactly the thing a human cannot time by eye. So it is fed synthetic audio instead,
/// where the right answer is known: onsets placed a known distance from each phrase entry, drums
/// on the beat throughout as the distraction they are in a real mix, and jitter on the vocal
/// entries because a singer is not a metronome. The cases that must *fail* matter as much: a
/// track with no voice in it, and a lyric file with too few entries to be sure, both have to come
/// back with no correction rather than a confident wrong one.
@MainActor
enum DebugLyricSyncCheck {
    static let flag = "--check-lyric-sync"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard arguments.contains(flag) else { return false }

        var lines: [String] = []
        var failures = 0
        func say(_ line: String) { lines.append(line) }
        func check(_ label: String, _ passed: Bool, _ detail: String) {
            if !passed { failures += 1 }
            say("\(passed ? "ok  " : "FAIL") \(label): \(detail)")
        }

        // A file with eight phrase entries, each after a gap, with filler lines between them.
        let lyrics = makeLyrics(entryTimes: [12, 30, 48, 66, 84, 102, 120, 138])
        let entries = LyricsSyncCalibrator.phraseEntries(of: lyrics)
        check(
            "phrase entries",
            entries.count == 8,
            "found \(entries.count) of 8 (lines between them are not entries)"
        )

        for shift in [-0.8, -0.35, 0.0, 0.45, 1.1] {
            var calibrator = LyricsSyncCalibrator()
            calibrator.begin(lyrics: lyrics)
            var random = Random(seed: 20260916)
            feed(&calibrator, entries: entries, shift: shift, jitter: 0.1, random: &random)

            let measured = calibrator.offset
            let expected = -shift
            let passed = measured.map { abs($0 - expected) <= 0.15 } ?? false
            check(
                String(format: "audio %+.2fs from the file", shift),
                passed,
                measured.map { String(format: "corrects %+.2f s, wanted %+.2f, from %d entries, spread %.2f", $0, expected, calibrator.matchCount, calibrator.spread ?? 0) }
                    ?? "no correction, wanted \(String(format: "%+.2f", expected))"
            )
        }

        // An instrumental: onsets all over, none of them a voice entering.
        var instrumental = LyricsSyncCalibrator()
        instrumental.begin(lyrics: lyrics)
        var random = Random(seed: 7)
        for entry in entries {
            for _ in 0..<6 {
                let position = entry + (random.next() * 3 - 1.5)
                instrumental.noteOnset(at: position, strength: random.next())
            }
        }
        check(
            "instrumental",
            instrumental.offset == nil,
            instrumental.offset.map { String(format: "corrected by %+.2f s, which it should not have", $0) }
                ?? "refused, spread \(String(format: "%.2f", instrumental.spread ?? 0))"
        )

        // A file with two entries: too few to be sure, whatever the audio does.
        let sparse = makeLyrics(entryTimes: [10, 40])
        var thin = LyricsSyncCalibrator()
        thin.begin(lyrics: sparse)
        var thinRandom = Random(seed: 3)
        feed(&thin, entries: LyricsSyncCalibrator.phraseEntries(of: sparse), shift: 0.5, jitter: 0, random: &thinRandom)
        check("too few entries", thin.offset == nil, thin.offset == nil ? "refused, \(thin.matchCount) matches" : "corrected on \(thin.matchCount) matches")

        // Nothing at all: no audio, no correction.
        var silent = LyricsSyncCalibrator()
        silent.begin(lyrics: lyrics)
        check("no audio", silent.offset == nil, silent.offset == nil ? "refused" : "corrected from nothing")

        say(failures == 0 ? "all checks passed" : "\(failures) check(s) failed")

        let output = lines.joined(separator: "\n") + "\n"
        if let index = arguments.firstIndex(of: "--out"), arguments.indices.contains(index + 1) {
            try? output.write(toFile: arguments[index + 1], atomically: true, encoding: .utf8)
        }
        FileHandle.standardError.write(output.data(using: .utf8)!)
        return true
    }

    /// Plays the track: a drum on every half second, and a voice at each phrase entry, shifted by
    /// `shift` and wobbled by `jitter`. The voice is the stronger onset, as it is in a real mix.
    private static func feed(
        _ calibrator: inout LyricsSyncCalibrator,
        entries: [TimeInterval],
        shift: TimeInterval,
        jitter: TimeInterval,
        random: inout Random
    ) {
        guard let last = entries.last else { return }
        var position: TimeInterval = 0
        while position < last + 5 {
            calibrator.noteOnset(at: position, strength: 0.2 + random.next() * 0.3)
            position += 0.5
        }
        for entry in entries {
            let wobble = jitter == 0 ? 0 : (random.next() * 2 - 1) * jitter
            calibrator.noteOnset(at: entry + shift + wobble, strength: 0.8 + random.next() * 0.2)
        }
    }

    /// Lines every three seconds inside a phrase, so the gaps between phrases are the only
    /// thing that makes an entry an entry.
    private static func makeLyrics(entryTimes: [TimeInterval]) -> Lyrics {
        var lines: [LyricLine] = []
        for entry in entryTimes {
            for step in 0..<4 {
                lines.append(LyricLine(timestamp: entry + Double(step) * 3, text: "line"))
            }
        }
        return Lyrics(lines: lines)
    }

    /// Repeatable pseudo-random numbers, so a failing run can be re-run and read.
    private struct Random {
        private var state: UInt64
        init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
        }
    }
}
#endif
