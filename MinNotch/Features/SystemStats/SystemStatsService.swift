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
    /// Degrees Celsius from `TemperatureSensors`: the chip's hottest die sensor, the battery,
    /// and the SSD. Nil where this Mac reports none, or while temperatures are switched off.
    var chipTemperature: Double?
    var batteryTemperature: Double?
    var ssdTemperature: Double?

    var memoryFraction: Double {
        guard memoryTotal > 0 else { return 0 }
        return min(Double(memoryUsed) / Double(memoryTotal), 1)
    }
}

/// The readings of the last five minutes, each with the moment it was taken, for the graph
/// under each reading.
///
/// Timestamped, because samples do not arrive at one rate: at the refresh interval while the
/// System tab is open, every few seconds otherwise. Drawn by time, a mixed cadence still makes an
/// honest line, and a stretch with no samples (the Mac asleep, Low Power Mode) shows as a gap
/// rather than being joined up.
struct SystemStatsHistory: Equatable {
    /// How far back the graphs reach.
    static let window: TimeInterval = 5 * 60

    struct Sample: Equatable {
        var time: Date
        var cpu: Double
        var gpu: Double?
        var memory: Double
        /// Bytes per second in and out together. The view scales it to its own maximum, since
        /// there is no fixed ceiling for a network rate.
        var network: Double
        /// Degrees Celsius.
        var chipTemperature: Double?
    }

    private(set) var samples: [Sample] = []

    mutating func append(_ stats: SystemStats, at time: Date = Date()) {
        samples.append(Sample(
            time: time,
            cpu: stats.cpuUsage,
            gpu: stats.gpuUsage,
            memory: stats.memoryFraction,
            network: stats.networkIn + stats.networkOut,
            chipTemperature: stats.chipTemperature
        ))
        let cutoff = time.addingTimeInterval(-Self.window)
        if let first = samples.firstIndex(where: { $0.time >= cutoff }), first > 0 {
            samples.removeFirst(first)
        }
    }

    /// One reading as points across the window: `x` runs from 0, five minutes before the newest
    /// sample, to 1, the newest.
    func points(_ value: (Sample) -> Double?) -> [ChartPoint] {
        guard let newest = samples.last?.time else { return [] }
        return samples.compactMap { sample in
            value(sample).map { ChartPoint(x: 1 - newest.timeIntervalSince(sample.time) / Self.window, value: $0) }
        }
    }
}

/// A point on a `StatChart`: `x` and `value` both 0...1.
struct ChartPoint: Equatable {
    var x: Double
    var value: Double
}

/// Samples CPU, GPU, memory, network and temperature.
///
/// Two speeds. While the System tab is on screen (`beginSampling()` / `endSampling()`, counted),
/// at the refresh interval the user chose. Otherwise every five seconds, temperatures every
/// fifteen, so that opening the tab shows the last five minutes instead of a graph that starts
/// from nothing each time, which is what the user saw when sampling stopped with the tab closed.
/// That background rate is the cost of keeping a history at all: a handful of kernel counters
/// per tick, with timer tolerance so macOS can fold the wakeups into ones it was doing anyway,
/// and nothing at all while the readout is switched off or the Mac is in Low Power Mode.
@Observable
@MainActor
final class SystemStatsService {
    private(set) var stats = SystemStats()
    // Settable from the debug sample below; nothing else writes them.
    fileprivate(set) var history = SystemStatsHistory()
    /// False when the GPU exposes no utilisation counter, so the view can omit the cell
    /// rather than showing a permanent zero.
    fileprivate(set) var isGPUAvailable = true

    private static let backgroundInterval: TimeInterval = 5
    private static let backgroundTemperatureInterval: TimeInterval = 15

    @ObservationIgnored private var settings: SettingsStore?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var timerInterval: TimeInterval = 0
    @ObservationIgnored private var observers = 0
    @ObservationIgnored private var lastTemperatureRead = Date.distantPast

    @ObservationIgnored private var previousCPUTicks: (busy: Double, total: Double)?
    @ObservationIgnored private var previousNetwork: (input: UInt64, output: UInt64, at: Date)?

    init() {}

    private var isEnabled: Bool {
        FeatureFlag.systemStats.isEnabled && settings?.advanced.showSystemStats == true
    }

    func start(settings: SettingsStore) {
        self.settings = settings
        stats.memoryTotal = ProcessInfo.processInfo.physicalMemory
        applySchedule()
    }

    /// Called when a view that shows these numbers appears.
    func beginSampling() {
        observers += 1
        guard observers == 1 else { return }

        // CPU and network are deltas between two readings. Sampling in the background normally
        // leaves a baseline in place; when it has not (the readout was off, or Low Power Mode),
        // a second sample follows quickly so the first number the user sees is real, rather
        // than a zero that sits there until the interval elapses.
        let hadBaseline = previousCPUTicks != nil
        sample(force: true)
        if !hadBaseline {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.observers > 0 else { return }
                self.sample(force: true)
            }
        }
        applySchedule()
    }

    func endSampling() {
        observers = max(0, observers - 1)
        guard observers == 0 else { return }
        applySchedule()
    }

    /// Reapplies the switch and the refresh interval after a settings change.
    func settingsChanged() {
        applySchedule()
    }

    /// Runs the timer at whichever speed fits, or not at all with the readout switched off, in
    /// which case the history goes too: there is nothing to keep it for.
    private func applySchedule() {
        guard isEnabled else {
            timer?.invalidate()
            timer = nil
            timerInterval = 0
            history = SystemStatsHistory()
            previousCPUTicks = nil
            previousNetwork = nil
            return
        }
        let interval = observers > 0
            ? max(0.5, settings?.advanced.statsRefreshInterval ?? 2)
            : Self.backgroundInterval
        guard timer == nil || interval != timerInterval else { return }

        timer?.invalidate()
        let timer = Timer.onMain(every: interval) { [weak self] in
            self?.sample(force: false)
        }
        // A quarter of the interval in the background, so the wakeups can share; a tenth while
        // someone is watching the numbers move.
        timer.tolerance = interval * (observers > 0 ? 0.1 : 0.25)
        self.timer = timer
        timerInterval = interval
    }

    private func sample(force: Bool) {
        // Nothing in the background while the Mac is saving power. The deltas start again
        // afterwards rather than averaging across the gap, and the graph shows the gap.
        if !force, observers == 0, ProcessInfo.processInfo.isLowPowerModeEnabled {
            previousCPUTicks = nil
            previousNetwork = nil
            return
        }

        var next = stats
        next.memoryTotal = ProcessInfo.processInfo.physicalMemory
        let cpu = sampleCPU()
        if let cpu { next.cpuUsage = cpu }
        next.gpuUsage = Self.sampleGPU()
        isGPUAvailable = next.gpuUsage != nil
        if let memory = Self.sampleMemory() { next.memoryUsed = memory }
        let network = sampleNetwork()
        if let network {
            next.networkIn = network.input
            next.networkOut = network.output
        }
        stats = next
        // The first reading of a delta is only a baseline (both samplers return nil for it),
        // not a measurement, so it stays out of the history rather than starting every line on
        // the floor.
        if cpu != nil, network != nil {
            history.append(next)
        }

        // The sensors are the expensive part, so in the background they are read less often.
        let temperatureInterval = observers > 0 ? 0 : Self.backgroundTemperatureInterval
        if Date().timeIntervalSince(lastTemperatureRead) >= temperatureInterval {
            lastTemperatureRead = Date()
            sampleTemperatures()
        }
    }

    // MARK: Temperatures

    /// Asks for the temperatures off the main thread, where the 20-odd milliseconds of sensor
    /// reads cannot stutter anything, and lays them into the readings when they arrive. The
    /// history picks them up on the next tick, one interval behind the rest, which a line five
    /// minutes long cannot show.
    private func sampleTemperatures() {
        guard settings?.advanced.showTemperatures == true else {
            if stats.chipTemperature != nil || stats.batteryTemperature != nil || stats.ssdTemperature != nil {
                stats.chipTemperature = nil
                stats.batteryTemperature = nil
                stats.ssdTemperature = nil
            }
            return
        }
        TemperatureSensors.shared.read { reading in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled else { return }
                self.stats.chipTemperature = reading?.chip
                self.stats.batteryTemperature = reading?.battery
                self.stats.ssdTemperature = reading?.ssd
            }
        }
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

        // The page size the VM counts are in. `vm_kernel_page_size` is a mutable C global,
        // which Swift 6 will not read here; on macOS the user page size is the same value.
        let pageSize = UInt64(getpagesize())
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
    // A formatter is safe to use from any thread once configured, and this one is never
    // reconfigured after it is built.
    nonisolated(unsafe) private static let formatter: ByteCountFormatter = {
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

#if DEBUG
extension SystemStatsService {
    /// Fixed readings and a history with a spike in it, for `--capture-notch --sample-stats`.
    /// A live capture cannot be relied on for this: the real pointer and run loop close or
    /// switch the panel while it waits for samples to accumulate.
    func applySampleHistory() {
        var stats = SystemStats()
        stats.memoryTotal = 16 << 30
        var history = SystemStatsHistory()
        let count = 60
        let now = Date()
        for index in 0..<count {
            let spike = (28...33).contains(index)
            stats.cpuUsage = spike ? 0.92 : 0.12 + 0.05 * sin(Double(index) / 3)
            stats.gpuUsage = spike ? 0.55 : 0.08
            stats.memoryUsed = UInt64(Double(stats.memoryTotal) * (0.52 + Double(index) * 0.002))
            stats.networkIn = index > 45 ? 2_400_000 : 40_000
            stats.networkOut = 12_000
            stats.chipTemperature = spike ? 82 : 47 + Double(index % 5)
            stats.batteryTemperature = 34.6
            stats.ssdTemperature = 45
            // Five minutes at the background rate, as a tab opened after a while would find it.
            history.append(stats, at: now.addingTimeInterval(-Double(count - 1 - index) * 5))
        }
        self.stats = stats
        self.history = history
        isGPUAvailable = true
    }
}
#endif
