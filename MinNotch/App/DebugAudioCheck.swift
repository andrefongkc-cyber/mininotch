#if DEBUG
import AppKit

/// Starts the Core Audio tap and reports what it hears.
///
/// Run with `MinNotch --check-audio [seconds]`. The tap needs the system audio recording
/// permission, and Core Audio reports a refusal as an ordinary error code rather than
/// anything obviously permission-shaped, so this prints the failure verbatim along with the
/// output device's reported latency, which is the other thing worth knowing.
@MainActor
enum DebugAudioCheck {
    static let flag = "--check-audio"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return false }

        let seconds = arguments.indices.contains(index + 1)
            ? (Double(arguments[index + 1]) ?? 6)
            : 6

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()

        let analyzer = AudioAnalyzer()
        report("output latency: \(Int(OutputLatency.current() * 1000)) ms")
        report("starting the tap…")
        analyzer.start()

        // Starting is asynchronous now, because the Core Audio call can block for as long as
        // the system takes to decide whether this process may listen.
        func waitForStart(_ remaining: Int) {
            if analyzer.isRunning {
                report("running. sampling for \(Int(seconds))s")
                sample()
                return
            }
            if let failure = analyzer.failure {
                report("failed: \(failure.message)")
                exit(1)
            }
            guard remaining > 0 else {
                report("gave up waiting for the tap to start")
                exit(1)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { waitForStart(remaining - 1) }
        }

        final class Count { var samples = 0 }
        let count = Count()
        var samples: Int { count.samples }

        let tick: @MainActor @Sendable () -> Void = {
            guard let analysis = analyzer.current else {
                report("  no buffers yet")
                return
            }
            count.samples += 1
            let bars = analysis.bands.map { String(format: "%.2f", $0) }.joined(separator: " ")
            report(String(format: "  energy %.2f  beat %.2f  bands %@", analysis.energy, analysis.beat, bars))
        }

        func sample() {

            let timer = Timer.onMain(every: 1, tick)

            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                timer.invalidate()
                analyzer.stop()
                report(samples > 0 ? "received audio on \(samples) of \(Int(seconds)) checks" : "tap ran but no audio arrived")
                exit(samples > 0 ? 0 : 1)
            }
        }

        waitForStart(40)
        app.run()
        return true
    }

    private static func report(_ message: String) {
        let line = message + "\n"
        FileHandle.standardError.write(line.data(using: .utf8)!)

        guard let index = CommandLine.arguments.firstIndex(of: "--out"),
              CommandLine.arguments.indices.contains(index + 1) else { return }
        let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? line.data(using: .utf8)?.write(to: url)
        }
    }
}
#endif
