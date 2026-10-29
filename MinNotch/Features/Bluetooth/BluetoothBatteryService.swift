import CoreAudio
import Foundation
import IOKit
import Observation
import SwiftUI

/// A connected wireless device that reports its own charge.
struct BluetoothDevice: Identifiable, Equatable {
    let id: String
    var name: String
    /// 0...100. Earbuds report each side and the case separately, and those arrive as
    /// separate entries rather than being averaged, because an average hides the one that
    /// is about to die.
    var percentage: Int
    var isCharging: Bool

    var symbolName: String {
        let lowercased = name.lowercased()
        if lowercased.contains("airpod") { return "airpods" }
        if lowercased.contains("beats") || lowercased.contains("headphone") { return "headphones" }
        if lowercased.contains("mouse") { return "magicmouse" }
        if lowercased.contains("keyboard") { return "keyboard" }
        if lowercased.contains("trackpad") { return "trackpad" }
        return "wave.3.right.circle"
    }

    var isLow: Bool { percentage <= 20 && !isCharging }

    /// The device's own name, without the side or case suffix earbuds are split into.
    var baseName: String {
        for suffix in [" (Left)", " (Right)", " (Case)"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }
}

/// Reads the battery level of connected Bluetooth accessories from the IO registry.
///
/// Apple publishes accessory charge through `AppleDeviceManagementHIDEventService`, the same
/// source the Bluetooth menu reads. It needs no entitlement and no Bluetooth permission,
/// because nothing is being scanned or connected: the values are already in the registry for
/// devices that are paired and awake.
///
/// Devices that are asleep or do not report charge simply do not appear, which is why the
/// list is rebuilt on each poll rather than accumulated.
///
/// AirPods and other Bluetooth headphones are not in that registry at all, so they come from
/// `BluetoothProfiler`, macOS's own `system_profiler` report of connected devices, which carries
/// each bud's and the case's charge and needs no Bluetooth permission. Their connecting is heard
/// from Core Audio, where a pair of headphones appears as a new output device.
@Observable
@MainActor
final class BluetoothBatteryService {
    private(set) var devices: [BluetoothDevice] = []

    @ObservationIgnored private var settings: SettingsStore?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers = 0

    /// Raised when an accessory that reports its charge connects, with what it reported.
    @ObservationIgnored var onDeviceConnected: (([BluetoothDevice]) -> Void)?
    @ObservationIgnored private var notifyPort: IONotificationPortRef?
    @ObservationIgnored private var connectIterators: [io_iterator_t] = []
    @ObservationIgnored private var audioListener: AudioObjectPropertyListenerBlock?
    /// Bluetooth audio devices connected now, by Core Audio's ID, so a new one can be told apart.
    @ObservationIgnored private var knownAudioDevices: Set<AudioObjectID> = []

    /// Registry classes that publish accessory charge. Apple has used more than one over the
    /// years and a Mac can have several attached at once.
    private static let serviceClasses = [
        "AppleDeviceManagementHIDEventService",
        "BNBTrackpadDevice",
        "BNBMouseDevice",
        "AppleHSBluetoothDevice"
    ]

    init() {}

    func start(settings: SettingsStore) {
        self.settings = settings
    }

    /// Reference counted the same way the system stats are: accessory charge changes slowly
    /// and there is no reason to walk the registry while nothing is displaying it.
    func beginSampling() {
        observers += 1
        guard observers == 1 else { return }
        refresh()

                let timer = Timer.onMain(every: 30) { [weak self] in
            self?.refresh()
        }
        self.timer = timer
    }

    func endSampling() {
        observers = max(0, observers - 1)
        guard observers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    var isEnabled: Bool {
        settings?.battery.showBluetoothDeviceBattery ?? false
    }

    func refresh() {
        guard isEnabled else {
            if !devices.isEmpty { devices = [] }
            return
        }
        let registry = Self.scan()
        devices = Self.merged(registry, devices.filter { $0.id.hasPrefix(BluetoothProfiler.idPrefix) })
        // Headphones from the profiler, a moment later, off the main thread.
        BluetoothProfiler.queue.async {
            let headphones = BluetoothProfiler.connectedDevices()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isEnabled else { return }
                self.devices = Self.merged(registry, headphones)
            }
        }
    }

    private static func merged(_ registry: [BluetoothDevice], _ headphones: [BluetoothDevice]) -> [BluetoothDevice] {
        let names = Set(registry.map(\.baseName))
        return (registry + headphones.filter { !names.contains($0.baseName) })
            .sorted { $0.percentage < $1.percentage }
    }

    // MARK: Connections

    /// Starts announcing accessories as they connect.
    ///
    /// A registry notification rather than polling or IOBluetooth: the registry says when a
    /// service of one of the charge-reporting classes appears, which is exactly "an accessory
    /// connected", costs nothing between events, and needs no Bluetooth permission, which the
    /// IOBluetooth connection callbacks would.
    func startWatchingConnections() {
        guard notifyPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        IONotificationPortSetDispatchQueue(port, .main)

        let context = Unmanaged.passUnretained(self).toOpaque()
        for className in Self.serviceClasses {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port,
                kIOFirstMatchNotification,
                IOServiceMatching(className),
                { refcon, iterator in
                    guard let refcon else { return }
                    Unmanaged<BluetoothBatteryService>.fromOpaque(refcon)
                        .takeUnretainedValue()
                        .handleMatches(iterator, announce: true)
                },
                context,
                &iterator
            )
            guard result == KERN_SUCCESS else { continue }
            connectIterators.append(iterator)
            // The iterator has to be drained once to arm the notification. What is in it now is
            // everything already connected, which is not news.
            handleMatches(iterator, announce: false)
        }

        // Headphones: what is connected now is not news either.
        knownAudioDevices = Set(Self.bluetoothAudioDevices().keys)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.audioDevicesChanged() }
        }
        audioListener = listener
        var address = Self.devicesAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
    }

    func stopWatchingConnections() {
        connectIterators.forEach { IOObjectRelease($0) }
        connectIterators.removeAll()
        if let notifyPort { IONotificationPortDestroy(notifyPort) }
        notifyPort = nil
        if let audioListener {
            var address = Self.devicesAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, audioListener)
        }
        audioListener = nil
        knownAudioDevices = []
    }

    /// A Bluetooth audio device that was not there before is a pair of headphones connecting.
    /// Its charge is read from the profiler two seconds later, and again at five if it had not
    /// reported yet, because AirPods tell the Mac their levels a moment after they connect.
    private func audioDevicesChanged() {
        let current = Self.bluetoothAudioDevices()
        // AirPods are two devices, the speakers and the microphone, under one name.
        let arrived = Set(current.filter { !knownAudioDevices.contains($0.key) }.map(\.value))
        let alreadyHere = Set(current.filter { knownAudioDevices.contains($0.key) }.map(\.value))
        knownAudioDevices = Set(current.keys)
        for name in arrived.subtracting(alreadyHere) { announceHeadphones(named: name, attempt: 0) }
    }

    private func announceHeadphones(named name: String, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 2 : 3)) {
            BluetoothProfiler.queue.async {
                let found = BluetoothProfiler.connectedDevices().filter { BluetoothProfiler.sameName($0.baseName, name) }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if found.isEmpty {
                        if attempt == 0 { self.announceHeadphones(named: name, attempt: 1) }
                        return
                    }
                    self.onDeviceConnected?(found)
                    if self.observers > 0 { self.refresh() }
                }
            }
        }
    }

    private static var devicesAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// Every Bluetooth audio device Core Audio has, by ID, with its name.
    static func bluetoothAudioDevices() -> [AudioObjectID: String] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = devicesAddress
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [:] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [:] }

        var found: [AudioObjectID: String] = [:]
        for id in ids {
            var transportAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var transport = UInt32(0)
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(id, &transportAddress, 0, nil, &transportSize, &transport)
            guard transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE else { continue }

            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name) == noErr,
                  let value = name?.takeRetainedValue() as String? else { continue }
            found[id] = value
        }
        return found
    }

    private func handleMatches(_ iterator: io_iterator_t, announce: Bool) {
        var matched: [io_service_t] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if announce { matched.append(service) } else { IOObjectRelease(service) }
            service = IOIteratorNext(iterator)
        }
        guard !matched.isEmpty else { return }

        // A service that has just appeared usually has not published its charge yet, so it is
        // read a moment later rather than reported as a device with no battery.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            let devices = matched.flatMap { Self.devices(in: $0) }
            matched.forEach { IOObjectRelease($0) }
            guard let self, !devices.isEmpty else { return }
            self.onDeviceConnected?(devices)
            if self.observers > 0 { self.refresh() }
        }
    }

    // MARK: Registry

    private static func scan() -> [BluetoothDevice] {
        var found: [BluetoothDevice] = []

        for className in serviceClasses {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching(className),
                &iterator
            ) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                defer {
                    IOObjectRelease(service)
                    service = IOIteratorNext(iterator)
                }
                found.append(contentsOf: devices(in: service))
            }
        }

        // The same accessory can appear under more than one registry class.
        var seen = Set<String>()
        return found.filter { seen.insert($0.id).inserted }
            .sorted { $0.percentage < $1.percentage }
    }

    private static func devices(in service: io_service_t) -> [BluetoothDevice] {
        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue()
        }

        let name = (property("Product") as? String)
            ?? (property("DeviceName") as? String)
            ?? "Bluetooth Device"
        let address = (property("DeviceAddress") as? String) ?? name

        // Earbuds publish a level per side plus the case; everything else publishes one.
        let parts: [(suffix: String, level: String, charging: String)] = [
            ("", "BatteryPercent", "BatteryStatusFlags"),
            (" (Left)", "BatteryPercentLeft", "BatteryStatusFlagsLeft"),
            (" (Right)", "BatteryPercentRight", "BatteryStatusFlagsRight"),
            (" (Case)", "BatteryPercentCase", "BatteryStatusFlagsCase")
        ]

        return parts.compactMap { part in
            guard let percentage = property(part.level) as? Int, percentage > 0 else { return nil }
            let flags = property(part.charging) as? Int ?? 0
            return BluetoothDevice(
                id: address + part.suffix,
                name: name + part.suffix,
                percentage: min(percentage, 100),
                // Bit 1 of the status flags is the charging bit.
                isCharging: flags & 0x02 != 0
            )
        }
    }
}

/// Connected Bluetooth devices' charge, from macOS's own `system_profiler` report.
///
/// AirPods and other headphones publish their levels to `bluetoothd`, not to the IO registry the
/// rest of this file reads, and asking `bluetoothd` directly would need the Bluetooth permission.
/// The report is about a tenth of a second, run only when headphones connect or the System tab
/// refreshes, never on the main thread.
enum BluetoothProfiler {
    static let queue = DispatchQueue(label: "com.minnotch.bluetooth-profiler", qos: .utility)
    static let idPrefix = "profiler|"

    nonisolated static func connectedDevices() -> [BluetoothDevice] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        // Read before waiting: a child that fills the pipe blocks until it is read.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return devices(fromJSON: data)
    }

    /// The devices with a charge in a report. Each level becomes one entry, as the registry's
    /// do: a bud each and the case, or a single level for anything else.
    nonisolated static func devices(fromJSON data: Data) -> [BluetoothDevice] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        let parts: [(suffix: String, key: String)] = [
            ("", "device_batteryLevelMain"),
            ("", "device_batteryLevel"),
            (" (Left)", "device_batteryLevelLeft"),
            (" (Right)", "device_batteryLevelRight"),
            (" (Case)", "device_batteryLevelCase")
        ]
        var found: [BluetoothDevice] = []
        for section in sections {
            for entry in section["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    let address = info["device_address"] as? String ?? name
                    var seenSuffixes = Set<String>()
                    for part in parts {
                        guard let text = info[part.key] as? String,
                              let percentage = Int(text.filter(\.isNumber)), percentage > 0,
                              seenSuffixes.insert(part.suffix).inserted else { continue }
                        found.append(BluetoothDevice(
                            id: idPrefix + address + part.suffix,
                            name: name + part.suffix,
                            percentage: min(percentage, 100),
                            // The report does not say whether a bud is charging.
                            isCharging: false
                        ))
                    }
                }
            }
        }
        return found
    }

    /// Core Audio and the report can write the same name with a different apostrophe.
    nonisolated static func sameName(_ a: String, _ b: String) -> Bool {
        func normal(_ s: String) -> String {
            s.replacingOccurrences(of: "\u{2019}", with: "'").lowercased().trimmingCharacters(in: .whitespaces)
        }
        return normal(a) == normal(b)
    }
}
