#if DEBUG
import AppKit

/// Runs the glow's shaping chain headlessly and prints what each stage did.
///
/// Run with `MinNotch --check-glow [seconds] [--source step|fallback] [--out file]`.
///
/// The constants in `GlowDynamics.Tuning` are the entire feel of the effect, and there is no
/// way to judge them from the glow on screen: a level pinned at the top and a level that
/// never leaves the middle look much the same once blurred and stroked. This prints the trace
/// instead, so an attack that is too slow, a decay that is too fast, a gain that has collapsed,
/// or a spring that never overshoots are all visible as numbers.
///
/// `step` feeds a square pulse, which is the clearest way to see the envelope and the spring:
/// a correct chain rises within a frame or two, overshoots past the input, and settles back.
/// `fallback` runs the real no-audio source, which is what an unsigned build actually shows.
@MainActor
enum DebugGlowCheck {
    static let flag = "--check-glow"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return false }

        let seconds = arguments.indices.contains(index + 1)
            ? (Double(arguments[index + 1]) ?? 2.5)
            : 2.5

        var source = "step"
        if let sourceIndex = arguments.firstIndex(of: "--source"),
           arguments.indices.contains(sourceIndex + 1) {
            source = arguments[sourceIndex + 1]
        }

        if source == "tempo" {
            checkTempo()
            return true
        }

        run(seconds: seconds, source: source)
        return true
    }

    /// `--source tempo`: checks that a set tempo puts the low-band hits exactly on its grid,
    /// measured from its origin, for a tapped tempo and a song's.
    private static func checkTempo() {
        var failures = 0
        for (bpm, origin) in [(100.0, 0.25), (128.0, 3.7), (60.0, 0.0)] {
            let tempo = GlowTempo(beatsPerMinute: bpm, origin: origin)
            var hits: [TimeInterval] = []
            var wasHit = false
            var time = origin - 0.5
            while time < origin + 6 {
                let isHit = (GlowFallbackSource.levels(at: time, isPlaying: true, speed: 0.5, tempo: tempo).bands.first ?? 0) > 0
                if isHit, !wasHit { hits.append(time) }
                wasHit = isHit
                time += 0.001
            }
            let expected = (0..<hits.count).map { origin + Double($0) * tempo.secondsPerBeat }
            let worst = zip(hits, expected).map { abs($0 - $1) }.max() ?? .infinity
            let passed = !hits.isEmpty && worst < 0.002 && hits.first! >= origin - 0.001
            if !passed { failures += 1 }
            report(String(format: "%@ %.0f bpm from %.2f s: %d hits, first at %.3f, worst %.4f s off the grid",
                          passed ? "ok  " : "FAIL", bpm, origin, hits.count, hits.first ?? -1, worst))
        }
        report(failures == 0 ? "all checks passed" : "\(failures) check(s) failed")
    }

    /// 120 Hz, which is what the effect gets on a ProMotion display and the hardest case for
    /// the spring's sub-stepping.
    private static let frameRate: Double = 120

    private static func run(seconds: Double, source: String) {
        let dynamics = GlowDynamics()
        let frames = Int(seconds * frameRate)
        let start: TimeInterval = 1000

        report("source \(source)   \(Int(frameRate))fps   \(String(format: "%.1f", seconds))s")
        report("")
        report("    time |  raw e | out e | beat | bands (raw -> shaped)")

        var peak: Double = 0
        var peakBeat: Double = 0
        var firstHit: TimeInterval?
        var riseTime: TimeInterval?

        for frame in 0..<frames {
            let time = start + Double(frame) / frameRate
            let raw = levels(for: source, at: time - start)
            let shaped = dynamics.shape(raw, at: time)

            peak = max(peak, shaped.energy)
            peakBeat = max(peakBeat, shaped.beat)

            // Timed from the first frame the input actually rises, not from the start of the
            // run, or the leading silence would be counted as part of the attack.
            if firstHit == nil, raw.energy > 0.5 { firstHit = time }
            if let firstHit, riseTime == nil, shaped.energy > 0.6 { riseTime = time - firstHit }

            // One line every 16 ms is enough to read; every frame is a wall of text.
            guard frame % Int(frameRate / 60) == 0 else { continue }
            report(String(
                format: "  %6.3f | %6.3f | %5.3f | %4.2f | %@ -> %@",
                time - start, raw.energy, shaped.energy, shaped.beat,
                meter(raw.bands), meter(shaped.bands)
            ))
        }

        report("")
        report(String(format: "peak shaped energy: %.3f   (overshoot %+.3f past full scale)", peak, peak - 1))
        report(String(format: "peak beat:          %.3f", peakBeat))
        if let riseTime {
            report(String(format: "0 to 0.6 after the hit: %.0f ms", riseTime * 1000))
        }
        report("")
        report("A chain with no spring peaks at exactly 1.000 and never above it. A chain with")
        report("too slow an attack takes well over 60 ms to reach 0.6. Either reads as flat.")

        flush()
        exit(0)
    }

    /// A square pulse: silence, a full-scale hit held briefly, then silence again.
    private static func levels(for source: String, at elapsed: TimeInterval) -> GlowDynamics.Levels {
        guard source != "fallback" else {
            return GlowFallbackSource.levels(at: elapsed, isPlaying: true, speed: 0.5)
        }

        // Two hits, so the second one shows what the auto-gain learned from the first.
        let isHit = (elapsed > 0.3 && elapsed < 0.42) || (elapsed > 1.2 && elapsed < 1.32)
        let level: Double = isHit ? 1 : 0.02
        return GlowDynamics.Levels(
            energy: level,
            bands: (0..<GlowInput.bandCount).map { _ in level },
            beat: 0
        )
    }

    private static func meter(_ levels: [Double]) -> String {
        let blocks = Array(" ▁▂▃▄▅▆▇█")
        return String(levels.map { level in
            blocks[Int((min(max(level, 0), 1) * Double(blocks.count - 1)).rounded())]
        })
    }

    // MARK: Output

    /// Mirrors the other check tools: `--out` exists because a process started by
    /// LaunchServices has nowhere to send stderr.
    private static var buffer = ""

    private static func report(_ message: String) {
        if outputPath == nil {
            FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
        } else {
            buffer += message + "\n"
        }
    }

    private static func flush() {
        guard let outputPath else { return }
        try? buffer.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    private static var outputPath: String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--out"),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
#endif
