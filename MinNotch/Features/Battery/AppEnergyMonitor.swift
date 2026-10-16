import AppKit
import Darwin
import IOKit
import Observation

/// Which apps have used the most energy since the Mac was last unplugged (Settings > Battery >
/// Apps Using the Battery).
///
/// macOS keeps its own per-app record in a database only root can read, so this keeps one of its
/// own, from the same source: the kernel puts every app and everything it starts into a resource
/// coalition (a browser's helpers and renderers, a terminal's shells and what they run), and keeps
/// a running total of the coalition's processor and graphics energy, including processes that have
/// already exited, and moves energy a system service spent on an app's behalf onto that app
/// (`coalition_info_resource_usage`, private, looked up at run time; readable for every coalition
/// with no permission). Once a minute on battery, every five seconds while the Battery pane is
/// open, it reads every coalition's total, takes the difference from the last reading, and adds it
/// to the coalition's app. It counted per process first, and lost everything a process that started
/// and exited between two readings used: a build, or a script, is mostly such processes.
///
/// The first reading of a stretch only records where every coalition stands, so what ran before
/// counts for nothing. The display is not in any coalition, so the shares are of what apps and
/// macOS's services used, not of the whole battery.
///
/// The stretch is saved after every reading, so a relaunch on battery carries on with it, unless
/// the charge has gone up in between (it was plugged in while MiniNotch was not running).
@MainActor
@Observable
final class AppEnergyMonitor {
    private(set) var stretch: BatteryStretch?

    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var watchers = 0
    @ObservationIgnored private var isSampling = false
    /// Nil until the first battery reading, so the first one can tell a launch on battery from an
    /// unplug.
    @ObservationIgnored private var wasPluggedIn: Bool?
    @ObservationIgnored private let sampler = AppEnergySampler()

    init() {}

    /// `fileURL` is where the stretch is kept between launches; nil keeps it in memory only.
    func start(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            stretch = try? JSONDecoder().decode(BatteryStretch.self, from: data)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        save()
    }

    /// Reference counted to the Battery pane: readings every five seconds while it is open, so the
    /// list moves while someone is looking at it.
    func beginWatching() {
        watchers += 1
        if watchers == 1 { sampleNow() }
        schedule()
    }

    func endWatching() {
        watchers = max(0, watchers - 1)
        schedule()
    }

    /// Every battery reading, from `AppEnvironment`.
    func update(battery status: BatteryStatus) {
        guard status.isPresent else { return }
        let pluggedIn = status.isPluggedIn
        defer { wasPluggedIn = pluggedIn }

        switch (wasPluggedIn, pluggedIn) {
        case (nil, false):
            // Launched on battery: carry on with the saved stretch if it is the same one.
            if let stretch, stretch.endedAt == nil, status.percentage <= stretch.lastPercentage + 1 {
                self.stretch?.lastPercentage = status.percentage
                sampleNow()
            } else {
                begin(percentage: status.percentage, sawUnplug: false)
            }
        case (nil, true):
            // Plugged in while MiniNotch was not running: the saved stretch ended some time after
            // its last reading, which is the best there is.
            if stretch != nil, stretch?.endedAt == nil {
                stretch?.endedAt = stretch?.lastSampleAt
                save()
            }
        case (true?, false):
            begin(percentage: status.percentage, sawUnplug: true)
        case (false?, true):
            // One last reading, then the stretch is over and kept to show.
            sampleNow { [weak self] in
                self?.stretch?.endedAt = .now
                self?.save()
            }
        case (false?, false):
            stretch?.lastPercentage = status.percentage
        case (true?, true):
            break
        }
        schedule()
    }

    /// Apps by energy used in the stretch, most first.
    var ranking: [AppEnergyUse] {
        guard let stretch else { return [] }
        return stretch.entries
            .map { key, entry in
                AppEnergyUse(id: key, name: entry.name, bundlePath: entry.bundlePath,
                             kind: entry.kind, joules: entry.nanojoules / 1e9)
            }
            .filter { $0.joules > 0.05 }
            .sorted { $0.joules > $1.joules }
    }

    // MARK: Stretch

    private func begin(percentage: Int, sawUnplug: Bool) {
        stretch = BatteryStretch(
            startedAt: .now,
            sawUnplug: sawUnplug,
            startPercentage: percentage,
            lastPercentage: percentage,
            batteryWattHours: AppEnergySampler.batteryWattHours()
        )
        // The first reading only records where every coalition stands.
        sampleNow()
    }

    private var isOnBattery: Bool { stretch != nil && stretch?.endedAt == nil && wasPluggedIn == false }

    private func schedule() {
        let interval: TimeInterval? = isOnBattery ? (watchers > 0 ? 5 : 60) : nil
        if timer?.timeInterval == interval { return }
        timer?.invalidate()
        timer = nil
        guard let interval else { return }
        let timer = Timer.onMain(every: interval) { [weak self] in self?.sampleNow() }
        timer.tolerance = interval * 0.2
        self.timer = timer
    }

    private func sampleNow(then done: (@MainActor @Sendable () -> Void)? = nil) {
        guard let stretch, stretch.endedAt == nil, !isSampling else { done?(); return }
        isSampling = true
        // Coalition numbers start again after a restart, so a reading from before one means
        // nothing: every coalition is then new, and counts from zero.
        let boot = AppEnergySampler.bootTime()
        let lastSeen = stretch.seenBoot == boot ? stretch.lastSeen : [:]
        sampler.read(lastSeen: lastSeen, isBaseline: stretch.seenBoot == nil) { [weak self] reading in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSampling = false
                self.merge(reading)
                done?()
            }
        }
    }

    private func merge(_ reading: AppEnergySampler.Reading) {
        guard var stretch, stretch.endedAt == nil else { return }
        for (key, use) in reading.used {
            var entry = stretch.entries[key]
                ?? BatteryStretch.Entry(name: use.app.name, bundlePath: use.app.bundlePath, kind: use.app.kind, nanojoules: 0)
            entry.nanojoules += Double(use.nanojoules)
            stretch.entries[key] = entry
        }
        stretch.lastSeen = reading.seen
        stretch.seenBoot = AppEnergySampler.bootTime()
        stretch.lastSampleAt = .now
        self.stretch = stretch
        save()
    }

    private func save() {
        guard let fileURL, let stretch, let data = try? JSONEncoder().encode(stretch) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    #if DEBUG
    /// For `--check-app-energy`: an unplug, a reading, a plug-in, without a battery doing either.
    func debugBegin(percentage: Int) { wasPluggedIn = false; begin(percentage: percentage, sawUnplug: true) }
    func debugSample(then done: @escaping @MainActor @Sendable () -> Void) { sampleNow(then: done) }
    #endif
}

/// One app's energy over a stretch on battery.
struct AppEnergyUse: Identifiable, Equatable {
    enum Kind: String, Codable { case app, system, tool }

    let id: String
    let name: String
    /// The app's bundle, for its icon; nil for System Services and command line tools.
    let bundlePath: String?
    let kind: Kind
    let joules: Double
}

/// A stretch on battery: from an unplug (or from when MiniNotch started, if it started on battery)
/// to now, or to the plug-in that ended it.
struct BatteryStretch: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var name: String
        var bundlePath: String?
        var kind: AppEnergyUse.Kind
        var nanojoules: Double
    }

    var startedAt: Date
    /// False when MiniNotch started on battery and so counts from then, not from the unplug.
    var sawUnplug: Bool
    var startPercentage: Int
    var lastPercentage: Int
    var endedAt: Date?
    /// The battery's full charge, for "about 3% of a full charge".
    var batteryWattHours: Double?
    var entries: [String: Entry] = [:]
    /// Each coalition's total at the last reading, by its number.
    var lastSeen: [String: UInt64] = [:]
    /// The boot `lastSeen` was read in (`kern.boottime`); nil before the first reading.
    var seenBoot: Double?
    var lastSampleAt: Date = .now
}

/// Reads every coalition's energy on a queue of its own. `@unchecked Sendable`: the name cache is
/// only touched on `queue`.
final class AppEnergySampler: @unchecked Sendable {
    struct App: Sendable {
        let key: String
        let name: String
        let bundlePath: String?
        let kind: AppEnergyUse.Kind
    }

    struct Use: Sendable {
        let app: App
        var nanojoules: UInt64
    }

    struct Reading: Sendable {
        var used: [String: Use] = [:]
        var seen: [String: UInt64] = [:]
    }

    private let queue = DispatchQueue(label: "com.minnotch.app-energy", qos: .utility)
    /// Executable path to the app it belongs to.
    private var apps: [String: App] = [:]

    private typealias ResourceUsage = @convention(c) (UInt64, UnsafeMutableRawPointer, Int) -> Int32
    private static let resourceUsage: ResourceUsage? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "coalition_info_resource_usage")
        else { return nil }
        return unsafeBitCast(symbol, to: ResourceUsage.self)
    }()

    /// Where the energy figures sit in the kernel's `struct coalition_resource_usage`, which only
    /// ever grows at the end: an older macOS fills fewer fields and leaves the rest at zero.
    private enum Field {
        static let energy = 11, energyBilledToMe = 20, energyBilledToOthers = 21
        static let gpuEnergy = 40, gpuEnergyBilledToMe = 41, gpuEnergyBilledToOthers = 42
    }

    /// `isBaseline` records where every coalition stands and counts nothing.
    func read(lastSeen: [String: UInt64], isBaseline: Bool, completion: @escaping @Sendable (Reading) -> Void) {
        queue.async {
            completion(self.readNow(lastSeen: lastSeen, isBaseline: isBaseline))
        }
    }

    private func readNow(lastSeen: [String: UInt64], isBaseline: Bool) -> Reading {
        var members: [UInt64: [pid_t]] = [:]
        for pid in Self.allProcesses() {
            if let id = Self.coalition(of: pid) { members[id, default: []].append(pid) }
        }
        var reading = Reading()
        for (id, pids) in members {
            guard let energy = Self.energy(ofCoalition: id) else { continue }
            let key = String(id)
            reading.seen[key] = energy
            if isBaseline { continue }
            // A coalition not seen before was made since the last reading: all of it counts.
            let used = lastSeen[key].map { energy >= $0 ? energy - $0 : 0 } ?? energy
            guard used > 0, let app = app(forMembers: pids.sorted()) else { continue }
            reading.used[app.key, default: Use(app: app, nanojoules: 0)].nanojoules += used
        }
        return reading
    }

    /// Processor and graphics energy, with what others spent on the coalition's behalf moved onto
    /// it and what it spent on theirs moved off, in nanojoules.
    static func energy(ofCoalition id: UInt64) -> UInt64? {
        guard let resourceUsage else { return nil }
        var usage = [UInt64](repeating: 0, count: 64)
        let status = usage.withUnsafeMutableBytes { resourceUsage(id, $0.baseAddress!, $0.count) }
        guard status == 0 else { return nil }
        func value(_ index: Int) -> Int64 { Int64(clamping: usage[index]) }
        let cpu = value(Field.energy) + value(Field.energyBilledToMe) - value(Field.energyBilledToOthers)
        let gpu = value(Field.gpuEnergy) + value(Field.gpuEnergyBilledToMe) - value(Field.gpuEnergyBilledToOthers)
        return UInt64(max(0, cpu) + max(0, gpu))
    }

    /// The process's resource coalition (`PROC_PIDCOALITIONINFO`, the first of its two ids).
    static func coalition(of pid: pid_t) -> UInt64? {
        var ids = [UInt64](repeating: 0, count: 5)
        let size = Int32(ids.count * MemoryLayout<UInt64>.size)
        guard proc_pidinfo(pid, 20, 0, &ids, size) > 0, ids[0] != 0 else { return nil }
        return ids[0]
    }

    /// The app a coalition stands for: its first member that is an app (the earliest started,
    /// which is the app itself), else its first member.
    func app(forMembers pids: [pid_t]) -> App? {
        let candidates = pids.compactMap(app(for:))
        return candidates.first { $0.kind == .app } ?? candidates.first
    }

    private func app(for pid: pid_t) -> App? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        if let known = apps[path] { return known }
        let app = Self.app(forExecutable: path)
        apps[path] = app
        return app
    }

    /// The outermost app bundle in the path, so a helper inside Chrome is Chrome; else macOS's
    /// own background processes as one, else the tool by its name.
    static func app(forExecutable path: String) -> App {
        if let range = path.range(of: ".app/") {
            let bundlePath = String(path[..<range.lowerBound]) + ".app"
            return App(key: bundlePath, name: bundleName(bundlePath), bundlePath: bundlePath, kind: .app)
        }
        let systemPrefixes = ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/", "/private/var/"]
        if systemPrefixes.contains(where: path.hasPrefix) {
            return App(key: "system", name: "System Services", bundlePath: nil, kind: .system)
        }
        return App(key: path, name: (path as NSString).lastPathComponent, bundlePath: nil, kind: .tool)
    }

    private static func bundleName(_ bundlePath: String) -> String {
        let info = Bundle(path: bundlePath)?.infoDictionary
        let name = info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String
        return name ?? ((bundlePath as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    static func allProcesses() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return pids.prefix(Int(max(filled, 0))).filter { $0 > 0 }
    }

    static func bootTime() -> Double {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &time, &size, nil, 0) == 0 else { return 0 }
        return Double(time.tv_sec)
    }

    /// The battery's full charge in watt hours, from its own registry entry.
    static func batteryWattHours() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        func number(_ key: String) -> Double? {
            (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber)?.doubleValue
        }
        guard let capacity = number("AppleRawMaxCapacity") ?? number("NominalChargeCapacity"),
              let millivolts = number("Voltage"), capacity > 0, millivolts > 0 else { return nil }
        return capacity * millivolts / 1_000_000
    }
}
