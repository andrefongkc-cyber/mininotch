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
        devices = Self.scan()
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
    }

    func stopWatchingConnections() {
        connectIterators.forEach { IOObjectRelease($0) }
        connectIterators.removeAll()
        if let notifyPort { IONotificationPortDestroy(notifyPort) }
        notifyPort = nil
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
