import Darwin
import IOKit
import Observation
import SwiftUI

/// A single reading of the machine's load.
struct SystemStats: Equatable {
    /// 0...1 across all cores.
    var cpuUsage: Double = 0
    /// 0...1, or nil when no GPU reports utilisation on this Mac.
    var gpuUsage: Double?
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = 0
    /// Bytes per second since the previous sample.
    var networkIn: Double = 0
    var networkOut: Double = 0

    var memoryFraction: Double {
        guard memoryTotal > 0 else { return 0 }
        return min(Double(memoryUsed) / Double(memoryTotal), 1)
    }
}

/// Samples CPU, GPU, memory, and network load.
///
/// Sampling is reference counted through `beginSampling()` and `endSampling()` so the timer
/// only runs while something is actually showing the numbers. A menu bar utility that wakes
/// up every couple of seconds forever is a battery complaint waiting to happen, and nothing
/// here is worth measuring when nobody is looking at it.
@Observable
final class SystemStatsService {
    private(set) var stats = SystemStats()
    /// False when the GPU exposes no utilisation counter, so the view can omit the cell
    /// rather than showing a permanent zero.
    private(set) var isGPUAvailable = true

    @ObservationIgnored private var settings: SettingsStore?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers = 0

    @ObservationIgnored private var previousCPUTicks: (busy: Double, total: Double)?
    @ObservationIgnored private var previousNetwork: (input: UInt64, output: UInt64, at: Date)?

    init() {}

    func start(settings: SettingsStore) {
        self.settings = settings
        stats.memoryTotal = ProcessInfo.processInfo.physicalMemory
    }

    /// Called when a view that shows these numbers appears.
    func beginSampling() {
        observers += 1
        guard observers == 1 else { return }

        // CPU and network are deltas between two readings, so one sample establishes a
        // baseline and reports zero. A second sample follows quickly so the first number the
        // user sees is real, rather than a zero that sits there until the interval elapses.
        sample()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.observers > 0 else { return }
            self.sample()
        }

        restartTimer()
    }

    func endSampling() {
        observers = max(0, observers - 1)
        guard observers == 0 else { return }
        timer?.invalidate()
        timer = nil
        previousCPUTicks = nil
        previousNetwork = nil
    }

    /// Reapplies the refresh interval after a settings change.
    func settingsChanged() {
        guard observers > 0 else { return }
        restartTimer()
    }

    private func restartTimer() {
        timer?.invalidate()
        let interval = max(0.5, settings?.advanced.statsRefreshInterval ?? 2)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.sample()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        var next = stats
        next.memoryTotal = ProcessInfo.processInfo.physicalMemory
        if let cpu = sampleCPU() { next.cpuUsage = cpu }
        next.gpuUsage = Self.sampleGPU()
        isGPUAvailable = next.gpuUsage != nil
        if let memory = Self.sampleMemory() { next.memoryUsed = memory }
        if let network = sampleNetwork() {
            next.networkIn = network.input
            next.networkOut = network.output
        }
        stats = next
    }

    // MARK: CPU

    /// Aggregate load across all cores, from the difference between two tick counts.
    ///
    /// The kernel reports cumulative ticks since boot, so a single reading says nothing;
    /// only the delta between two samples is a usage figure.
    private func sampleCPU() -> Double? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let user = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3)

        let busy = user + system + nice
        let total = busy + idle

        defer { previousCPUTicks = (busy, total) }
        guard let previous = previousCPUTicks else { return nil }

        let busyDelta = busy - previous.busy
        let totalDelta = total - previous.total
        guard totalDelta > 0 else { return nil }
        return min(max(busyDelta / totalDelta, 0), 1)
    }

    // MARK: GPU

    /// Reads GPU utilisation from the accelerator's performance counters.
    ///
    /// This is the same IORegistry key Activity Monitor and the common open source monitors
    /// read. It needs no entitlement and no elevated privileges, but not every GPU publishes
    /// it, so a nil result means "this Mac does not report it" rather than "idle".
    private static func sampleGPU() -> Double? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var highest: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let raw = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] else { continue }

            // Apple silicon and Intel integrated graphics use different key names for the
            // same number, and discrete cards use a third.
            let keys = ["Device Utilization %", "GPU Activity(%)", "Renderer Utilization %"]
            for key in keys {
                guard let value = raw[key] as? Int else { continue }
                highest = max(highest ?? 0, Double(value) / 100)
                break
            }
        }

        return highest.map { min(max($0, 0), 1) }
    }

    // MARK: Memory

    /// Memory in use, matching how Activity Monitor counts it: app memory plus wired plus
    /// compressed. Cached and purgeable pages are excluded because the system reclaims them
    /// on demand, so counting them would show a permanently full machine.
    private static func sampleMemory() -> UInt64? {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var info = vm_statistics64_data_t()

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        let app = UInt64(max(Int64(info.internal_page_count) - Int64(info.purgeable_count), 0))
        let wired = UInt64(info.wire_count)
        let compressed = UInt64(info.compressor_page_count)

        return (app + wired + compressed) * pageSize
    }

    // MARK: Network

    /// Throughput since the previous sample, summed over every physical interface.
    private func sampleNetwork() -> (input: Double, output: Double)? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }

            guard let name = current.pointee.ifa_name else { continue }
            let interface = String(cString: name)
            // Loopback traffic is the machine talking to itself and is not throughput.
            guard !interface.hasPrefix("lo") else { continue }
            guard current.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }
            guard let data = current.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }

            totalIn += UInt64(data.pointee.ifi_ibytes)
            totalOut += UInt64(data.pointee.ifi_obytes)
        }

        let now = Date()
        defer { previousNetwork = (totalIn, totalOut, now) }
        guard let previous = previousNetwork else { return nil }

        let elapsed = now.timeIntervalSince(previous.at)
        guard elapsed > 0 else { return nil }

        // Counters reset when an interface goes away, so a negative delta is discarded.
        let inputDelta = totalIn >= previous.input ? Double(totalIn - previous.input) : 0
        let outputDelta = totalOut >= previous.output ? Double(totalOut - previous.output) : 0

        return (inputDelta / elapsed, outputDelta / elapsed)
    }
}

/// Formats byte counts and rates the way the system does, with the unit next to the number.
enum ByteFormat {
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        return formatter
    }()

    static func size(_ bytes: UInt64) -> String {
        formatter.string(fromByteCount: Int64(bytes))
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond >= 1024 else { return "0 KB/s" }
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }
}
