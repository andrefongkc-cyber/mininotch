import AppKit
import Darwin
import IOKit
import Observation

/// One app's share of a resource, for the expanded System tab's Top Apps lists.
struct AppLoad: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    /// The app's bundle, for its icon and for Quit; nil for System Services and tools.
    let bundlePath: String?
    let kind: AppEnergyUse.Kind
    /// CPU: share of one core, as Activity Monitor counts it (2 is two whole cores). GPU: share
    /// of the GPU's time. Memory: bytes.
    let value: Double
}

/// Activity Monitor's memory pressure, from `kern.memorystatus_vm_pressure_level`.
enum MemoryPressure: Equatable, Sendable {
    case normal, warning, critical

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Elevated"
        case .critical: return "Critical"
        }
    }
}

struct BatteryHealth: Equatable, Sendable {
    var cycleCount: Int?
    /// The battery's full charge now against when it was new, 0...1.
    var maximumCapacity: Double?
    /// macOS's own verdict, "Normal" or "Service Recommended".
    var condition: String?
}

/// Everything the expanded System tab shows beyond the compact readings.
struct SystemDetails: Equatable, Sendable {
    var topCPU: [AppLoad] = []
    var topGPU: [AppLoad] = []
    var topMemory: [AppLoad] = []
    var pressure: MemoryPressure?
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var diskFree: Int64?
    var diskTotal: Int64?
    /// Bytes a second since the last reading.
    var diskRead: Double?
    var diskWrite: Double?
    var battery: BatteryHealth?
    /// Each core's load, 0...1, in the kernel's order.
    var cores: [Double] = []
    /// Which cores are efficiency cores, by the same index.
    var efficiencyCores: Set<Int> = []
    /// Revolutions a minute; empty on a Mac without fans, nil before the first reading.
    var fans: [Double]?
    /// Watts the Mac is using, read while it runs on battery.
    var powerOnBattery: Double?
    var bootTime: Date?
}

/// Samples `SystemDetails` while the expanded System tab is on screen, and only then: per-app
/// figures mean walking every process, which is cheap once every couple of seconds while someone
/// is looking and pointless otherwise.
@MainActor
@Observable
final class SystemDetailsService {
    /// Whether the System tab is showing its expanded view. Not saved: the tab opens compact.
    var isExpanded = false
    private(set) var details = SystemDetails()
    private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    @ObservationIgnored private var watchers = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isSampling = false
    @ObservationIgnored private let sampler = SystemDetailsSampler()
    @ObservationIgnored private var isPluggedIn: () -> Bool = { true }
    #if DEBUG
    @ObservationIgnored private var holdsSample = false
    #endif

    init() {}

    func start(isPluggedIn: @escaping () -> Bool) {
        self.isPluggedIn = isPluggedIn
    }

    func beginSampling(interval: TimeInterval) {
        watchers += 1
        guard watchers == 1 else { return }
        sample()
        // CPU, GPU and disk are differences between two readings, so a second one follows soon
        // after the first, as the compact readings do.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.watchers > 0 else { return }
            self.sample()
        }
        let timer = Timer.onMain(every: max(1, interval)) { [weak self] in self?.sample() }
        timer.tolerance = 0.2
        self.timer = timer
    }

    func endSampling() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
        sampler.reset()
    }

    /// Asks the app at `bundlePath` to quit, the way the Dock's Quit does, so it can still ask
    /// to save. MiniNotch never quits itself or Finder from here.
    func quit(bundlePath: String) {
        let own = Bundle.main.bundleURL.path
        guard bundlePath != own else { return }
        for app in NSWorkspace.shared.runningApplications where app.bundleURL?.path == bundlePath {
            guard app.bundleIdentifier != "com.apple.finder" else { continue }
            app.terminate()
        }
    }

    static func canQuit(_ load: AppLoad) -> Bool {
        guard load.kind == .app, let path = load.bundlePath else { return false }
        return path != Bundle.main.bundleURL.path && !path.hasSuffix("/Finder.app")
    }

    private func sample() {
        #if DEBUG
        if holdsSample { return }
        #endif
        guard !isSampling else { return }
        isSampling = true
        thermalState = ProcessInfo.processInfo.thermalState
        let wantsPower = !isPluggedIn()
        sampler.read { [weak self] reading in
            PowerSensors.shared.readFans { fans in
                PowerSensors.shared.read { power in
                    Task { @MainActor in
                        self?.finish(reading: reading, fans: fans, power: power, wantsPower: wantsPower)
                    }
                }
            }
        }
    }

    private func finish(reading: SystemDetails, fans: [Double], power: PowerSensors.Reading?, wantsPower: Bool) {
        isSampling = false
        var next = reading
        next.fans = fans
        next.powerOnBattery = wantsPower ? power?.system : nil
        if next != details { details = next }
    }

    #if DEBUG
    /// Fixed figures for `--capture-notch --tab system --expanded-system`.
    func applySample() {
        func app(_ name: String, _ value: Double) -> AppLoad {
            AppLoad(id: name, name: name, bundlePath: "/Applications/\(name).app", kind: .app, value: value)
        }
        details = SystemDetails(
            topCPU: [app("Xcode", 1.42), app("Safari", 0.38), app("Music", 0.06)],
            topGPU: [app("Safari", 0.21), app("WindowServer", 0.09), app("Music", 0.02)],
            topMemory: [app("Xcode", 3.1e9), app("Safari", 1.8e9), app("Slack", 0.6e9)],
            pressure: .normal, swapUsed: 1_200_000_000, swapTotal: 2_147_483_648,
            diskFree: 212_000_000_000, diskTotal: 494_000_000_000, diskRead: 4_200_000, diskWrite: 860_000,
            battery: BatteryHealth(cycleCount: 172, maximumCapacity: 0.95, condition: "Normal"),
            cores: [0.92, 0.35, 0.12, 0.05, 0.62, 0.48, 0.3, 0.21, 0.18, 0.1],
            efficiencyCores: [4, 5, 6, 7, 8, 9],
            fans: [], powerOnBattery: 6.4,
            bootTime: Date().addingTimeInterval(-3 * 86_400 - 4 * 3_600)
        )
        thermalState = .nominal
        holdsSample = true
    }
    #endif
}

/// Reads everything in `SystemDetails` on a queue of its own. `@unchecked Sendable`: every
/// stored property is touched only on `queue`.
final class SystemDetailsSampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.minnotch.system-details", qos: .utility)
    /// For its executable-to-app mapping and cache, only ever used on `queue`.
    private let apps = AppEnergySampler()
    private var previous: (time: UInt64, cpu: [UInt64: UInt64], gpu: [UInt64: UInt64])?
    private var previousCores: [(busy: Double, total: Double)] = []
    private var previousDisk: (read: UInt64, write: UInt64, time: UInt64)?
    private lazy var efficiencyCores: Set<Int> = Self.readEfficiencyCores()
    private lazy var timebase: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    /// Where the processor and graphics time sit in `struct coalition_resource_usage`.
    private enum Field {
        static let cpuTime = 3, gpuTime = 8, cpuBilledToMe = 9, cpuBilledToOthers = 10
    }

    func read(_ completion: @escaping @Sendable (SystemDetails) -> Void) {
        queue.async { completion(self.readNow()) }
    }

    func reset() {
        queue.async {
            self.previous = nil
            self.previousCores = []
            self.previousDisk = nil
        }
    }

    private func readNow() -> SystemDetails {
        var details = SystemDetails()
        readApps(into: &details)
        readMemory(into: &details)
        readDisk(into: &details)
        details.battery = Self.readBatteryHealth()
        details.cores = readCores()
        details.efficiencyCores = efficiencyCores
        details.bootTime = Date(timeIntervalSince1970: AppEnergySampler.bootTime())
        return details
    }

    // MARK: Apps

    /// Every process's coalition, then each coalition's processor and graphics time since the
    /// last reading and its members' memory, added up by app.
    private func readApps(into details: inout SystemDetails) {
        var members: [UInt64: [pid_t]] = [:]
        var memory: [UInt64: UInt64] = [:]
        for pid in AppEnergySampler.allProcesses() {
            guard let id = AppEnergySampler.coalition(of: pid) else { continue }
            members[id, default: []].append(pid)
            if let footprint = Self.footprint(of: pid) { memory[id, default: 0] += footprint }
        }

        let now = mach_absolute_time()
        var cpu: [UInt64: UInt64] = [:]
        var gpu: [UInt64: UInt64] = [:]
        for id in members.keys {
            guard let usage = AppEnergySampler.rawUsage(ofCoalition: id) else { continue }
            let own = Int64(clamping: usage[Field.cpuTime]) + Int64(clamping: usage[Field.cpuBilledToMe])
                - Int64(clamping: usage[Field.cpuBilledToOthers])
            cpu[id] = UInt64(max(0, own))
            gpu[id] = usage[Field.gpuTime]
        }

        var cpuByApp: [String: (AppEnergySampler.App, Double)] = [:]
        var gpuByApp: [String: (AppEnergySampler.App, Double)] = [:]
        var memoryByApp: [String: (AppEnergySampler.App, Double)] = [:]
        let elapsedNanoseconds = previous.map { Double(now &- $0.time) * timebase } ?? 0

        for (id, pids) in members {
            guard let app = apps.app(forMembers: pids.sorted()) else { continue }
            if let bytes = memory[id] {
                memoryByApp[app.key, default: (app, 0)].1 += Double(bytes)
            }
            guard let previous, elapsedNanoseconds > 0 else { continue }
            if let now = cpu[id], let before = previous.cpu[id], now >= before {
                // `cpu_time` counts in Mach time units.
                cpuByApp[app.key, default: (app, 0)].1 += Double(now - before) * timebase / elapsedNanoseconds
            }
            if let now = gpu[id], let before = previous.gpu[id], now >= before {
                // `gpu_time` counts in nanoseconds.
                gpuByApp[app.key, default: (app, 0)].1 += Double(now - before) / elapsedNanoseconds
            }
        }
        previous = (now, cpu, gpu)

        func top(_ byApp: [String: (AppEnergySampler.App, Double)], floor: Double) -> [AppLoad] {
            byApp.values
                .filter { $0.1 > floor }
                .sorted { $0.1 > $1.1 }
                .prefix(3)
                .map { AppLoad(id: $0.0.key, name: $0.0.name, bundlePath: $0.0.bundlePath, kind: $0.0.kind, value: $0.1) }
        }
        details.topCPU = top(cpuByApp, floor: 0.001)
        details.topGPU = top(gpuByApp, floor: 0.001)
        details.topMemory = top(memoryByApp, floor: 1_000_000)
    }

    /// The process's memory as Activity Monitor's Memory column counts it. Nil for processes
    /// this user cannot read, which are macOS's own and count under System Services anyway.
    private static func footprint(of pid: pid_t) -> UInt64? {
        var info = rusage_info_v2()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        return status == 0 ? info.ri_phys_footprint : nil
    }

    // MARK: Memory pressure and swap

    private func readMemory(into details: inout SystemDetails) {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            details.pressure = level >= 4 ? .critical : level >= 2 ? .warning : .normal
        }
        var swap = xsw_usage()
        size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            details.swapUsed = swap.xsu_used
            details.swapTotal = swap.xsu_total
        }
    }

    // MARK: Storage

    private func readDisk(into details: inout SystemDetails) {
        let root = URL(fileURLWithPath: "/")
        if let values = try? root.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            details.diskTotal = values.volumeTotalCapacity.map(Int64.init)
            details.diskFree = values.volumeAvailableCapacityForImportantUsage
        }

        // Bytes read and written by every disk since boot, from each storage driver's statistics.
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0
        var written: UInt64 = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let statistics = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                read += (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                written += (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        let now = mach_absolute_time()
        if let previousDisk, read >= previousDisk.read, written >= previousDisk.write {
            let seconds = Double(now &- previousDisk.time) * timebase / 1e9
            if seconds > 0 {
                details.diskRead = Double(read - previousDisk.read) / seconds
                details.diskWrite = Double(written - previousDisk.write) / seconds
            }
        }
        previousDisk = (read, written, now)
    }

    // MARK: Battery health

    static func readBatteryHealth() -> BatteryHealth? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        func number(_ key: String) -> Double? {
            (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber)?.doubleValue
        }
        var health = BatteryHealth()
        health.cycleCount = number("CycleCount").map { Int($0) }
        // On Apple silicon `MaxCapacity` is already the percentage System Settings shows (here
        // 100% where the raw charge against design is 95%); elsewhere it is milliamp hours, and
        // the raw charge against design is the figure.
        if let percent = number("MaxCapacity"), percent > 0, percent <= 100, (number("DesignCapacity") ?? 0) > 100 {
            health.maximumCapacity = percent / 100
        } else if let design = number("DesignCapacity"), design > 0,
                  let full = number("AppleRawMaxCapacity") ?? number("NominalChargeCapacity") ?? number("MaxCapacity") {
            health.maximumCapacity = min(full / design, 1)
        }
        // The power source's own `BatteryHealth` cannot be trusted: on this M4 it says "Check
        // Battery" while System Settings says Normal. Apple's rule is below 80% of the design
        // capacity, or a permanent failure the gauge has recorded.
        let failed = (number("PermanentFailureStatus") ?? 0) != 0
        if failed {
            health.condition = "Service Recommended"
        } else if let capacity = health.maximumCapacity {
            health.condition = capacity < 0.8 ? "Service Recommended" : "Normal"
        }
        return health
    }

    // MARK: Cores

    private func readCores() -> [Double] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var ticks: [(busy: Double, total: Double)] = []
        for core in 0..<Int(count) {
            let base = core * Int(CPU_STATE_MAX)
            let user = Double(info[base + Int(CPU_STATE_USER)])
            let system = Double(info[base + Int(CPU_STATE_SYSTEM)])
            let nice = Double(info[base + Int(CPU_STATE_NICE)])
            let idle = Double(info[base + Int(CPU_STATE_IDLE)])
            ticks.append((user + system + nice, user + system + nice + idle))
        }
        defer { previousCores = ticks }
        guard previousCores.count == ticks.count else { return ticks.map { _ in 0 } }
        return zip(ticks, previousCores).map { now, before in
            let total = now.total - before.total
            return total > 0 ? min(max((now.busy - before.busy) / total, 0), 1) : 0
        }
    }

    /// Which logical cores are efficiency cores, from the device tree's `cluster-type` ("E" or
    /// "P") on each `cpuN`. Failing that, the first `hw.perflevel1.logicalcpu`, which is where
    /// Apple silicon puts them.
    private static func readEfficiencyCores() -> Set<Int> {
        var result: Set<Int> = []
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        if cpus != 0 {
            defer { IOObjectRelease(cpus) }
            var iterator: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &iterator) == KERN_SUCCESS {
                defer { IOObjectRelease(iterator) }
                var entry = IOIteratorNext(iterator)
                while entry != 0 {
                    func property(_ key: String) -> CFTypeRef? {
                        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
                    }
                    let type = (property("cluster-type") as? Data).flatMap { String(data: $0.prefix { $0 != 0 }, encoding: .ascii) }
                    let id = (property("logical-cpu-id") as? NSNumber)?.intValue
                    if type == "E", let id { result.insert(id) }
                    IOObjectRelease(entry)
                    entry = IOIteratorNext(iterator)
                }
            }
        }
        if !result.isEmpty { return result }
        var efficiency: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.perflevel1.logicalcpu", &efficiency, &size, nil, 0) == 0 else { return [] }
        return Set(0..<Int(efficiency))
    }
}
