#if DEBUG
import AppKit

/// Runs the real lyrics pipeline from the command line and prints what it found.
///
/// Run with `MinNotch --check-lyrics "<artist>" "<title>" [duration] [--no-cache]`. Run it twice:
/// the first lookup goes to LRCLIB and fills the cache, the second should say "hit" and take
/// a few milliseconds. `--no-cache` empties the cache first. Lyrics involve a
/// third-party lookup and a parser, and neither is visible from the UI when it fails, so
/// this exercises `LRCLIBClient` and `LRCParser` together against a real track without
/// having to play something and watch the notch.
@MainActor
enum DebugLyricsCheck {
    static let flag = "--check-lyrics"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return false }
        guard arguments.count > index + 2 else {
            report("Usage: --check-lyrics \"<artist>\" \"<title>\" [duration seconds]")
            exit(2)
        }

        let artist = arguments[index + 1]
        let title = arguments[index + 2]
        let duration = arguments.count > index + 3 ? Double(arguments[index + 3]) ?? 0 : 0

        let track = NowPlayingTrack(
            title: title,
            artist: artist,
            album: "",
            duration: duration,
            elapsed: 0,
            isPlaying: true,
            sourceKind: .appleMusic,
            sourceAppName: "Music",
            trackIdentity: "check"
        )

        if arguments.contains("--no-cache") { LyricsCache.shared.removeAll() }
        let before = LyricsCache.shared.lookup(track)
        report("cache before lookup: \(Self.describe(before))")
        let started = Date()

        LRCLIBClient.shared.lyrics(for: track) { lyrics in
            report(String(format: "lookup took %.0f ms", Date().timeIntervalSince(started) * 1000))
            // The store is asynchronous; give it a moment before asking what it holds.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                report("cache after lookup:  \(Self.describe(LyricsCache.shared.lookup(track)))")
                Self.printResult(lyrics, artist: artist, title: title)
            }
        }

        RunLoop.main.run(until: Date().addingTimeInterval(20))
        report("Timed out")
        exit(1)
    }

    private static func describe(_ lookup: LyricsCache.Lookup) -> String {
        switch lookup {
        case .hit(let text): return "hit (\(text.count) characters)"
        case .knownMissing: return "known missing"
        case .miss: return "miss"
        }
    }

    private static func printResult(_ lyrics: Lyrics?, artist: String, title: String) {
        do {
            guard let lyrics, !lyrics.isEmpty else {
                report("No lyrics found for \(artist) — \(title)")
                exit(1)
            }

            report("Found \(lyrics.lines.count) lines, synced: \(lyrics.isSynced)")
            for line in lyrics.lines.prefix(4) {
                let stamp = line.timestamp.map { String(format: "%6.2fs", $0) } ?? "  ----"
                report("  \(stamp)  \(line.text)")
            }
            report("Per-word highlighting: \(lyrics.hasWordTiming ? "yes" : "no")")

            // Prove the highlight lookup works, which is what the strip actually calls, and
            // step through one line to show the word the strip would pick out at each moment.
            if let index = lyrics.index(at: 30) {
                let line = lyrics.lines[index]
                report("Line at 0:30 -> \"\(line.text)\"")
                for word in line.words {
                    report(String(format: "  %6.2f-%6.2fs  %@", word.start, word.end, word.text))
                }

                var sampled: [String] = []
                for step in stride(from: line.timestamp ?? 0, to: (line.words.last?.end ?? 0), by: 0.4) {
                    let current = line.words.first { $0.isCurrent(at: step) }
                    sampled.append(current?.text ?? "-")
                }
                report("Highlight every 0.4s: " + sampled.joined(separator: " "))
            }
            exit(0)
        }
    }

    private static func report(_ message: String) {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    }
}
#endif
