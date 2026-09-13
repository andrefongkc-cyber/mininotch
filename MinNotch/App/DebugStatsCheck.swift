#if DEBUG
import AppKit

/// Prints a few system stat samples and exits.
///
/// Run with `MinNotch --check-stats [samples]`. The CPU and network figures are deltas
/// between samples, and the GPU counter is not published by every Mac, so a single reading
/// proves nothing. This takes several and shows them changing, which is the only way to tell
/// a working sampler from one that returns a plausible constant.
@MainActor
enum DebugStatsCheck {
    static let flag = "--check-stats"

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag) else { return false }

        let count = arguments.indices.contains(index + 1)
            ? (Int(arguments[index + 1]) ?? 4)
            : 4

        let environment = DebugSupport.makeEnvironment()
        let service = environment.systemStats
        let interval = max(0.5, environment.settings.advanced.statsRefreshInterval)
        service.start(settings: environment.settings)
        service.beginSampling()

        report("total memory: \(ByteFormat.size(ProcessInfo.processInfo.physicalMemory))")

        var remaining = count
        func take() {
            let stats = service.stats
            let gpu = stats.gpuUsage.map { String(format: "%3.0f%%", $0 * 100) } ?? " n/a"
            report(String(
                format: "cpu %3.0f%%   gpu %@   memory %@ of %@ (%3.0f%%)   net in %@ out %@",
                stats.cpuUsage * 100,
                gpu,
                ByteFormat.size(stats.memoryUsed),
                ByteFormat.size(stats.memoryTotal),
                stats.memoryFraction * 100,
                ByteFormat.rate(stats.networkIn),
                ByteFormat.rate(stats.networkOut)
            ))

            remaining -= 1
            guard remaining > 0 else {
                report(service.isGPUAvailable ? "GPU counter available" : "GPU counter not published by this Mac")
                exit(0)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) { take() }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { take() }
        RunLoop.main.run(until: Date().addingTimeInterval(Double(count) * interval + 5))
        report("Timed out")
        exit(1)
    }

    private static func report(_ message: String) {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    }
}
#endif
