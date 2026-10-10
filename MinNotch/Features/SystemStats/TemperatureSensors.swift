import Foundation

/// The Mac's own temperature sensors: the chip, the battery and the SSD.
///
/// macOS has no public API for them. Apple silicon publishes each thermal sensor as a HID
/// service (vendor usage page `0xff00`, usage 5), and the event system will hand over a
/// temperature event for any of them, which is how monitoring apps such as Stats read them. The
/// functions that do it are private, so they are loaded at run time like MediaRemote and
/// SkyLight: a macOS without them reports no temperatures rather than failing to launch.
///
/// The sensors are not labelled CPU or GPU on Apple silicon. The die sensors (`PMU tdie…`) are
/// spread across the whole chip, so the chip temperature is the hottest of them, the figure
/// that says how hot the Mac is running. The battery's fuel gauge and the SSD's controller
/// report their own.
///
/// Reading is not cheap: each sensor is a round trip to the event system, about 24 ms for the
/// 31 this uses on an M4. So it happens on a queue of its own, never on main, where it would
/// stutter whatever was animating. Everything below is confined to that queue.
final class TemperatureSensors: @unchecked Sendable {
    struct Reading: Sendable, Equatable {
        /// Degrees Celsius, or nil where this Mac has no such sensor.
        var chip: Double?
        var battery: Double?
        var ssd: Double?

        var isEmpty: Bool { chip == nil && battery == nil && ssd == nil }
    }

    static let shared = TemperatureSensors()

    private typealias CreateClient = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatValue = @convention(c) (AnyObject, Int32) -> Double

    /// `kIOHIDEventTypeTemperature`, and its level field, `type << 16`.
    private static let temperatureEvent: Int64 = 15
    private static let temperatureField: Int32 = 15 << 16
    /// Anything outside this is a sensor reporting a calibration value, not a temperature: the
    /// `tdev` sensors read -22 on an M4.
    private static let plausible: ClosedRange<Double> = 5...130

    private let queue = DispatchQueue(label: "com.minnotch.temperatures", qos: .utility)

    // Confined to `queue`.
    private var isLoaded = false
    private var copyEvent: CopyEvent?
    private var getFloatValue: GetFloatValue?
    /// Held so the services stay valid for as long as they are read.
    private var client: AnyObject?
    private var chipSensors: [AnyObject] = []
    private var batterySensor: AnyObject?
    private var ssdSensors: [AnyObject] = []

    /// Reads every sensor once, off the main thread, and calls back on that queue with nil
    /// when this Mac offers no temperatures at all.
    func read(_ completion: @escaping @Sendable (Reading?) -> Void) {
        queue.async { [self] in
            let reading = readNow()
            completion(reading.isEmpty ? nil : reading)
        }
    }

    #if DEBUG
    /// Every sensor by name, for `--check-temps`.
    func allSensors() -> [(name: String, celsius: Double)] {
        queue.sync {
            loadIfNeeded()
            guard let client, let copyServices = Self.function("IOHIDEventSystemClientCopyServices", CopyServices.self),
                  let copyProperty = Self.function("IOHIDServiceClientCopyProperty", CopyProperty.self) else { return [] }
            let services = (copyServices(client)?.takeRetainedValue() as? [AnyObject]) ?? []
            return services.compactMap { service in
                let name = (copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String) ?? "?"
                return value(of: service).map { (name, $0) }
            }
            .sorted { $0.name < $1.name }
        }
    }
    #endif

    private func readNow() -> Reading {
        loadIfNeeded()
        return Reading(
            chip: chipSensors.compactMap(value(of:)).max(),
            battery: batterySensor.flatMap(value(of:)),
            ssd: ssdSensors.compactMap(value(of:)).max()
        )
    }

    private func value(of sensor: AnyObject) -> Double? {
        guard let copyEvent, let getFloatValue,
              let event = copyEvent(sensor, Self.temperatureEvent, 0, 0)?.takeRetainedValue() else { return nil }
        let celsius = getFloatValue(event, Self.temperatureField)
        return Self.plausible.contains(celsius) ? celsius : nil
    }

    /// IOKit is linked already, so this only finds the handle; it is read on `queue` and the
    /// debug check, never written after it is opened.
    private nonisolated(unsafe) static let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)

    private static func function<T>(_ name: String, _ type: T.Type) -> T? {
        guard let iokit, let pointer = dlsym(iokit, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    /// Finds the sensors once and keeps them: the set does not change while the Mac runs.
    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true

        guard let create = Self.function("IOHIDEventSystemClientCreate", CreateClient.self),
              let setMatching = Self.function("IOHIDEventSystemClientSetMatching", SetMatching.self),
              let copyServices = Self.function("IOHIDEventSystemClientCopyServices", CopyServices.self),
              let copyProperty = Self.function("IOHIDServiceClientCopyProperty", CopyProperty.self),
              let copyEvent = Self.function("IOHIDServiceClientCopyEvent", CopyEvent.self),
              let getFloatValue = Self.function("IOHIDEventGetFloatValue", GetFloatValue.self),
              let client = create(kCFAllocatorDefault)?.takeRetainedValue()
        else {
            AppLog.app.error("The HID event system functions for temperatures are missing")
            return
        }
        self.copyEvent = copyEvent
        self.getFloatValue = getFloatValue
        self.client = client

        _ = setMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        let services = (copyServices(client)?.takeRetainedValue() as? [AnyObject]) ?? []
        for service in services {
            let name = (copyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String) ?? ""
            if name.contains("tdie") {
                chipSensors.append(service)
            } else if name.hasPrefix("gas gauge battery") {
                // Several report the same pack; one is enough.
                if batterySensor == nil { batterySensor = service }
            } else if name.hasPrefix("NAND") {
                ssdSensors.append(service)
            }
        }
    }
}

/// Degrees for display, in the units chosen in Settings > Tabs > Weather, with the unit said.
///
/// The forecast leaves the unit off, as the Weather app does, but a chip at "138°" looks broken
/// to anyone used to the Celsius every other monitoring tool shows; "138°F" does not.
enum TemperatureFormat {
    static func string(celsius: Double, fahrenheit: Bool) -> String {
        let value = fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°\(fahrenheit ? "F" : "C")"
    }
}
