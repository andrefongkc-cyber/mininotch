#if DEBUG
import AppKit

/// Runs the real lyrics pipeline from the command line and prints what it found.
///
/// Run with `MinNotch --check-lyrics "<artist>" "<title>" [duration]`. Lyrics involve a
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

        LRCLIBClient.shared.lyrics(for: track) { lyrics in
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

        // The lookup is asynchronous, so the run loop has to keep turning until it lands.
        RunLoop.main.run(until: Date().addingTimeInterval(20))
        report("Timed out waiting for a response")
        exit(1)
    }

    private static func report(_ message: String) {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    }
}
#endif
