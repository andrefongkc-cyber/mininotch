#if DEBUG
import AVFoundation
import Foundation

/// Checks that matching lyrics to the audio recovers an offset it is given, and refuses one it is
/// not.
///
/// Run with `MiniNotch --check-lyric-sync [--out f]` for the synthetic cases, or against a real
/// song with `MiniNotch --check-lyric-sync --audio song.mp3 --lrc song.lrc --shifts 0,0.5,-1`.
///
/// The measurement cannot be judged by playing a song and squinting at the strip: the thing being
/// measured is exactly the thing a human cannot time by eye. So it is fed signals where the right
/// answer is known. Synthetic first: a voice that comes in at each line, a known distance from the
/// file's timing, over drums throughout. Then a real song, decoded and run through the same
/// `SpectrumFrameAnalyzer` the live tap uses, with the lyric file moved by known amounts: whatever
/// the song's true offset is, moving the file by half a second must move the answer by half a
/// second. The cases that must *fail* matter as much: an instrumental, and a file too far out to
/// measure, have to come back with no correction rather than a confident wrong one.
///
/// The real song is also run through the method this replaced, so the difference is a number.
@MainActor
enum DebugLyricSyncCheck {
    static let flag = "--check-lyric-sync"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard arguments.contains(flag) else { return false }

        var output: [String] = []
        func say(_ line: String) {
            output.append(line)
            print(line)
        }

        if let audio = value(after: "--audio"), let lrc = value(after: "--lrc") {
            let shifts = (value(after: "--shifts") ?? "0").split(separator: ",").compactMap { Double($0) }
            realSong(audio: audio, lrc: lrc, shifts: shifts, say: say)
        } else {
            synthetic(say: say)
        }

        if let path = value(after: "--out") {
            try? (output.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
        return true
    }

    private static func value(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    // MARK: Synthetic

    private static func synthetic(say: (String) -> Void) {
        var failures = 0
        func check(_ label: String, _ passed: Bool, _ detail: String) {
            if !passed { failures += 1 }
            say("\(passed ? "ok  " : "FAIL") \(label): \(detail)")
        }

        let lyrics = makeLyrics()
        for shift in [-1.4, -0.6, -0.25, 0.0, 0.35, 0.8, 1.5] {
            let calibrator = play(lyrics: lyrics, voiceShift: shift, hasVoice: true)
            let expected = shift == 0 ? 0 : -shift
            let passed = calibrator.offset.map { abs($0 - expected) <= 0.1 } ?? false
            check(
                String(format: "voice %+.2fs from the file", shift),
                passed,
                describe(calibrator) + String(format: ", wanted %+.2f", expected)
            )
        }

        let instrumental = play(lyrics: lyrics, voiceShift: 0, hasVoice: false)
        check("instrumental", instrumental.offset == nil, describe(instrumental))

        let tooFar = play(lyrics: lyrics, voiceShift: 6, hasVoice: true)
        check("file six seconds out", tooFar.offset == nil, describe(tooFar))

        var silent = LyricsSyncCalibrator()
        silent.begin(lyrics: lyrics)
        silent.decide()
        check("no audio", silent.offset == nil, describe(silent))

        say(failures == 0 ? "all checks passed" : "\(failures) check(s) failed")
    }

    /// A voice level at 100 readings a second: a quiet bed with a drum every half second, and,
    /// when `hasVoice`, singing that starts `voiceShift` after each line's time and stops for a
    /// breath before the next, with a little wobble because a singer is not a metronome.
    private static func play(lyrics: Lyrics, voiceShift: TimeInterval, hasVoice: Bool) -> LyricsSyncCalibrator {
        var calibrator = LyricsSyncCalibrator()
        calibrator.begin(lyrics: lyrics)
        let starts = lyrics.lines.compactMap(\.timestamp)
        var random = Random(seed: 20261002)
        let wobbles = starts.map { _ in (random.next() * 2 - 1) * 0.06 }
        let end = (starts.last ?? 0) + 8

        var time: TimeInterval = 0
        while time < end {
            // The band under the singer, eight decibels down, with a snare on every half second.
            var level = -34.0 + random.next() * 2
            if time.truncatingRemainder(dividingBy: 0.5) < 0.05 { level += 7 }
            if hasVoice {
                for (index, start) in starts.enumerated() {
                    let sung = start + voiceShift + wobbles[index]
                    let next = index + 1 < starts.count ? starts[index + 1] + voiceShift : sung + 3
                    if time >= sung && time < next - 0.3 { level = max(level, -26 + random.next() * 3) }
                }
            }
            calibrator.noteVoiceLevel(level, at: time, time: time)
            time += 0.01
        }
        calibrator.decide()
        return calibrator
    }

    /// Verses of lines two to four seconds apart, unevenly as real lines are, with an
    /// instrumental break between verses.
    private static func makeLyrics() -> Lyrics {
        var lines: [LyricLine] = []
        var random = Random(seed: 11)
        for verse in [12.0, 40, 68, 96] {
            var time = verse
            for _ in 0..<6 {
                lines.append(LyricLine(timestamp: time, text: "line"))
                time += 2 + random.next() * 2
            }
        }
        return Lyrics(lines: lines)
    }

    private static func describe(_ calibrator: LyricsSyncCalibrator) -> String {
        let confidence = (calibrator.confidence.map { String(format: ", margin %.2f dB", $0) } ?? "")
            + (calibrator.strength.map { String(format: ", rise %.1f dB", $0) } ?? "")
            + (calibrator.significance.map { String(format: ", z %.1f", $0) } ?? "")
        guard let offset = calibrator.offset else {
            return "no correction, \(calibrator.matchCount) lines heard\(confidence)"
        }
        return String(format: "corrects %+.2f s from %d lines", offset, calibrator.matchCount) + confidence
    }

    // MARK: A real song

    private static func realSong(audio: String, lrc: String, shifts: [Double], say: (String) -> Void) {
        guard let text = try? String(contentsOfFile: lrc, encoding: .utf8) else {
            say("could not read \(lrc)")
            return
        }
        let original = LRCParser.parse(text)
        guard original.isSynced else {
            say("\(lrc) has no timings")
            return
        }
        guard let (levels, onsets, duration) = analyse(audio: audio) else {
            say("could not decode \(audio)")
            return
        }
        say(String(format: "%@: %.1f s, %d voice readings, %d onsets for the old method", (audio as NSString).lastPathComponent, duration, levels.count, onsets.count))
        say("shift  expected   new method                                old method")

        for shift in shifts {
            let lyrics = Lyrics(lines: original.lines.map { line in
                var moved = line
                moved.timestamp = line.timestamp.map { $0 + shift }
                return moved
            })

            var calibrator = LyricsSyncCalibrator()
            calibrator.begin(lyrics: lyrics)
            var firstAnswer: (time: TimeInterval, offset: TimeInterval)?
            var answers: [TimeInterval?] = []
            for reading in levels {
                calibrator.noteVoiceLevel(reading.level, at: reading.time, time: reading.time)
                if firstAnswer == nil, let offset = calibrator.offset { firstAnswer = (reading.time, offset) }
                if answers.last.map({ $0 != calibrator.offset }) ?? true { answers.append(calibrator.offset) }
            }
            // How often the answer changed on the way, which the strip shows as the lyrics jumping.
            let changes = max(0, answers.count - 2)
            calibrator.decide()

            var old = OldCalibrator(lyrics: lyrics)
            for onset in onsets { old.note(position: onset.time, strength: onset.strength) }

            let new = describe(calibrator)
                + (firstAnswer.map { String(format: ", first %+.2f at %.0f s", $0.offset, $0.time) } ?? "")
                + (changes > 0 ? ", changed \(changes)x" : "")
            let oldText = old.offset.map { String(format: "corrects %+.2f s from %d entries", $0, old.matchCount) }
                ?? "no correction, \(old.matchCount) entries"
            say(String(format: "%+5.2f  ", shift) + pad(new, 58) + oldText)
            if CommandLine.arguments.contains("--peaks") {
                let scores = calibrator.debugScores(window: LyricsSyncCalibrator.wideWindow)
                let peaks = scores.indices.filter { index in
                    (index == 0 || scores[index].score >= scores[index - 1].score)
                        && (index == scores.count - 1 || scores[index].score > scores[index + 1].score)
                }
                .sorted { scores[$0].score > scores[$1].score }
                .prefix(6)
                .map { String(format: "%+.2f:%.0f", scores[$0].offset, scores[$0].score) }
                say("       wide peaks (audio later than file by: score) " + peaks.joined(separator: " "))
            }
        }
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }

    /// Decodes a file and runs it through the live analysis, a window every 512 frames, which is
    /// about as often as the tap delivers. Also finds the onsets the old method used: a jump in
    /// the 94 Hz to 1.5 kHz bands of more than 0.045, at least 0.2 s after the last.
    private static func analyse(audio: String) -> (levels: [(time: TimeInterval, level: Double)], onsets: [(time: TimeInterval, strength: Double)], duration: TimeInterval)? {
        guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: audio)),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let channels = buffer.floatChannelData else { return nil }

        let count = Int(buffer.frameLength)
        let rate = file.processingFormat.sampleRate
        let left = Array(UnsafeBufferPointer(start: channels[0], count: count))
        let right = buffer.format.channelCount > 1 ? Array(UnsafeBufferPointer(start: channels[1], count: count)) : left

        var analyzer = SpectrumFrameAnalyzer(sampleRate: rate)
        let size = SpectrumFrameAnalyzer.fftSize
        var levels: [(TimeInterval, Double)] = []
        var onsets: [(TimeInterval, Double)] = []
        var previousMid = 0.0
        var lastOnset = -1.0

        var start = 0
        while start + size <= count {
            // Stamped at the end of the window, as the live tap stamps a buffer when it arrives.
            let time = Double(start + size) / rate
            if let frame = analyzer.analyse(left: Array(left[start..<start + size]), right: Array(right[start..<start + size]), at: time) {
                levels.append((time, frame.voiceLevel))
                let bands = frame.analysis.bands
                let mid = bands[2...5].reduce(0, +) / 4
                let rise = mid - previousMid
                previousMid = mid
                if rise > 0.045, time - lastOnset > 0.2 {
                    lastOnset = time
                    onsets.append((time, rise))
                }
            }
            start += 512
        }
        return (levels, onsets, Double(count) / rate)
    }

    /// The method this replaced, kept here only to be compared against: lines after a five second
    /// gap, the strongest onset within two seconds of each, the median of the differences once
    /// three agree to within a quarter of a second.
    private struct OldCalibrator {
        var entries: [TimeInterval] = []
        var matches: [Int: (position: TimeInterval, strength: Double)] = [:]
        var offset: TimeInterval?
        var matchCount: Int { matches.count }

        init(lyrics: Lyrics) {
            let stamps = lyrics.lines.compactMap(\.timestamp).sorted()
            guard let first = stamps.first else { return }
            entries = [first]
            for (previous, current) in zip(stamps, stamps.dropFirst()) where current - previous >= 5 {
                entries.append(current)
            }
        }

        mutating func note(position: TimeInterval, strength: Double) {
            var best: Int?
            var bestDistance = 2.0
            for (index, entry) in entries.enumerated() where abs(position - entry) <= bestDistance {
                bestDistance = abs(position - entry)
                best = index
            }
            guard let index = best else { return }
            if let existing = matches[index], existing.strength >= strength { return }
            matches[index] = (position, strength)

            let deltas = matches.map { $1.position - entries[$0] }.sorted()
            guard deltas.count >= 3 else { offset = nil; return }
            let middle = median(deltas)
            guard median(deltas.map { abs($0 - middle) }.sorted()) <= 0.25 else { offset = nil; return }
            offset = min(max(-middle, -2), 2)
        }

        private func median(_ sorted: [Double]) -> Double {
            sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        }
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
