#if DEBUG
import Foundation

/// Prints what the expanded System tab would show, from two real readings a second and a half
/// apart, with a busy child process (`yes`) running in between so the CPU list has a known
/// figure in it: it should show about 100% for System Services, where `/usr/bin/yes` counts.
///
/// Run with `MiniNotch --check-system-details`.
@MainActor
enum DebugSystemDetailsCheck {
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--check-system-details") else { return false }
        let sampler = SystemDetailsSampler()
        func read() -> SystemDetails {
            let box = Box<SystemDetails>()
            sampler.read { reading in box.set(reading) }
            let deadline = Date().addingTimeInterval(10)
            while box.get() == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
            return box.get() ?? SystemDetails()
        }
        let busy = Process()
        busy.executableURL = URL(fileURLWithPath: "/usr/bin/yes")
        busy.standardOutput = FileHandle.nullDevice
        try? busy.run()
        _ = read()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        let started = Date()
        let details = read()
        let took = Date().timeIntervalSince(started)
        busy.terminate()

        func list(_ title: String, _ loads: [AppLoad], _ format: (Double) -> String) {
            print(title + ": " + loads.map { "\($0.name) \(format($0.value))" }.joined(separator: ", "))
        }
        list("CPU", details.topCPU) { String(format: "%.0f%%", $0 * 100) }
        list("GPU", details.topGPU) { String(format: "%.1f%%", $0 * 100) }
        list("Memory", details.topMemory) { ByteFormat.size(UInt64($0)) }
        print("pressure \(details.pressure?.title ?? "?"), swap \(ByteFormat.size(details.swapUsed)) of \(ByteFormat.size(details.swapTotal))")
        print("disk free \(details.diskFree.map { ByteFormat.size(UInt64($0)) } ?? "?") of \(details.diskTotal.map { ByteFormat.size(UInt64($0)) } ?? "?"), read \(details.diskRead.map(ByteFormat.rate) ?? "?"), write \(details.diskWrite.map(ByteFormat.rate) ?? "?")")
        if let battery = details.battery {
            print("battery cycles \(battery.cycleCount ?? -1), max \(battery.maximumCapacity.map { String(format: "%.0f%%", $0 * 100) } ?? "?"), \(battery.condition ?? "?")")
        }
        print("cores " + details.cores.enumerated().map { "\(details.efficiencyCores.contains($0.offset) ? "E" : "P")\(Int($0.element * 100))" }.joined(separator: " "))
        print("boot \(details.bootTime.map { "\($0)" } ?? "?"), thermal \(ProcessInfo.processInfo.thermalState.rawValue)")
        print(String(format: "one reading took %.0f ms", took * 1000))
        let fans = Box<[Double]>()
        PowerSensors.shared.readFans { fans.set($0) }
        let deadline = Date().addingTimeInterval(3)
        while fans.get() == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        print("fans \(fans.get().map { "\($0)" } ?? "no answer")")
        return true
    }
}

/// A value handed across from another queue, behind a lock.
private final class Box<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?
    func set(_ new: Value) { lock.withLock { value = new } }
    func get() -> Value? { lock.withLock { value } }
}
#endif
