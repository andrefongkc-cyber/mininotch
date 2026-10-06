import IOKit.ps
import Observation
import SwiftUI

/// Charge state of the internal battery.
struct BatteryStatus: Equatable {
    var isPresent: Bool = false
    /// 0...100.
    var percentage: Int = 0
    var isCharging: Bool = false
    var isPluggedIn: Bool = false
    var isCharged: Bool = false
    /// Minutes until empty or full, or nil while the estimate is still being calculated.
    var minutesRemaining: Int?
    var isLowPowerMode: Bool = false
    /// The connected charger's rating, as the charger itself reports it, while plugged in.
    var adapterWatts: Int?

    /// SF Symbol matching the current state, using Apple's own battery glyph family.
    var symbolName: String {
        guard isPresent else { return "powerplug" }
        if isCharging { return "battery.100percent.bolt" }
        switch percentage {
        case ..<10: return "battery.0percent"
        case ..<35: return "battery.25percent"
        case ..<60: return "battery.50percent"
        case ..<85: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// Colour for the glyph. Yellow in Low Power Mode and red when critical, matching the
    /// system menu bar item so the two never disagree.
    ///
    /// The neutral case is the Notch Style's ink, passed in, rather than a semantic label
    /// colour: the notch draws in its style's colours whatever the system appearance is.
    func tint(neutral: Color) -> Color {
        if isCharging || isPluggedIn { return Color(nsColor: .systemGreen) }
        if isLowPowerMode { return Color(nsColor: .systemYellow) }
        if percentage <= 10 { return Color(nsColor: .systemRed) }
        return neutral
    }

    var timeRemainingDescription: String? {
        guard let minutesRemaining, minutesRemaining > 0 else { return nil }
        let hours = minutesRemaining / 60
        let minutes = minutesRemaining % 60
        let suffix = isCharging ? "until full" : "remaining"
        if hours > 0 { return "\(hours)h \(minutes)m \(suffix)" }
        return "\(minutes)m \(suffix)"
    }
}

/// Where the power is going while plugged in: in from the charger, used by the Mac, into the
/// battery. Watts, each nil where this Mac does not report it.
struct ChargingPower: Equatable {
    var input: Double?
    var system: Double?
    /// Negative while the battery is helping the charger keep up.
    var battery: Double?

    /// The share of what the charger delivers that ends up in the battery, while charging.
    var batteryShare: Double? {
        guard let input, let battery, input >= 1, battery > Self.idle else { return nil }
        return min(battery / input, 1)
    }

    var isCharging: Bool { (battery ?? 0) > Self.idle }
    var isDraining: Bool { (battery ?? 0) < -Self.idle }

    /// Below half a watt either way the battery is being held, not charged or drained: that is
    /// the gauge's noise, and the trickle that keeps a full or paused battery where it is.
    static let idle = 0.5
}

/// Reads the internal battery and republishes it as observable state.
///
/// IOKit posts a run-loop notification whenever any power source changes, so there is no
/// polling: the readout updates the moment the charger is plugged in or the percentage
/// ticks over. The one exception is `power`, the live watts while plugged in, which nothing
/// announces: it is read from the SMC once a second, and only while the System tab is showing
/// it.
@Observable
@MainActor
final class BatteryService {
    private(set) var status = BatteryStatus()
    /// Live while plugged in and something is showing it (`beginPowerSampling()`), else nil.
    private(set) var power: ChargingPower?
    /// Set once the SMC has answered with none of the power keys, so nothing keeps room for
    /// figures this Mac cannot give.
    private(set) var isPowerUnavailable = false

    /// Set by `AppEnvironment` so notification posting stays out of the service.
    @ObservationIgnored var onLowBattery: ((Int) -> Void)?
    @ObservationIgnored var onPowerSourceChange: ((Bool) -> Void)?

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var lastNotifiedThresholdCrossing: Int?
    @ObservationIgnored private var lastPluggedIn: Bool?
    @ObservationIgnored private var settings: SettingsStore?
    @ObservationIgnored private var powerObservers = 0
    @ObservationIgnored private var powerTimer: Timer?
    #if DEBUG
    /// Keeps a sample reading in place for a capture, instead of the real SMC's.
    @ObservationIgnored private var holdsSamplePower = false
    #endif

    init() {}

    func start(settings: SettingsStore) {
        self.settings = settings
        refresh()

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { service.refresh() }
        }, context)?.takeRetainedValue() else {
            AppLog.battery.error("Could not create the power source run loop source")
            return
        }

        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
        powerObservers = 0
        applyPowerSchedule()
    }

    func refresh() {
        let newStatus = Self.read()
        let previous = status
        status = newStatus

        evaluateLowBattery(previous: previous, current: newStatus)
        evaluatePowerSourceChange(current: newStatus)
        applyPowerSchedule()
    }

    // MARK: Charging power

    /// True when the System tab should keep a row for the charging figures: plugged in, the
    /// setting on, and a Mac that has them. It does not wait for the first reading, so the
    /// panel is the right height on the frame it opens.
    var showsChargingPower: Bool {
        status.isPresent && status.isPluggedIn && !isPowerUnavailable
            && (settings?.battery.showChargingPower ?? false)
    }

    /// Reference counted, like the other samplers, to the view that shows the figures.
    func beginPowerSampling() {
        powerObservers += 1
        applyPowerSchedule()
    }

    func endPowerSampling() {
        powerObservers = max(0, powerObservers - 1)
        applyPowerSchedule()
    }

    /// Reads every second while plugged in and watched, the rate the SMC itself updates at, and
    /// not at all otherwise. Called on every power source change, so unplugging stops it.
    private func applyPowerSchedule() {
        #if DEBUG
        if holdsSamplePower { return }
        #endif
        let wanted = powerObservers > 0 && showsChargingPower
        if wanted, powerTimer == nil {
            samplePower()
            let timer = Timer.onMain(every: 1) { [weak self] in self?.samplePower() }
            timer.tolerance = 0.1
            powerTimer = timer
        } else if !wanted, powerTimer != nil {
            powerTimer?.invalidate()
            powerTimer = nil
            power = nil
            PowerSensors.shared.close()
        }
    }

    private func samplePower() {
        PowerSensors.shared.read { reading in
            Task { @MainActor [weak self] in
                guard let self, self.powerTimer != nil else { return }
                guard let reading else {
                    AppLog.battery.info("This Mac reports no charging power")
                    self.isPowerUnavailable = true
                    self.applyPowerSchedule()
                    return
                }
                self.power = Self.smoothed(reading, after: self.power)
            }
        }
    }

    /// The Mac's own use swings by several watts from one second to the next as work comes
    /// and goes, which as a raw readout is a number nobody can read. A short average, about
    /// three seconds, keeps it legible and still follows a real change within a few seconds.
    private static func smoothed(_ reading: PowerSensors.Reading, after previous: ChargingPower?) -> ChargingPower {
        func blend(_ new: Double?, _ old: Double?) -> Double? {
            guard let new else { return nil }
            guard let old else { return new }
            return old + (new - old) * 0.4
        }
        return ChargingPower(
            input: blend(reading.input, previous?.input),
            system: blend(reading.system, previous?.system),
            battery: blend(reading.battery, previous?.battery)
        )
    }

    // MARK: Reading IOKit

    private static func read() -> BatteryStatus {
        var status = BatteryStatus()
        status.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return status }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            status.isPresent = true

            let current = info[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = info[kIOPSMaxCapacityKey] as? Int ?? 100
            status.percentage = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : 0

            status.isCharging = info[kIOPSIsChargingKey] as? Bool ?? false
            status.isCharged = info[kIOPSIsChargedKey] as? Bool ?? false
            status.isPluggedIn = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            if status.isPluggedIn,
               let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
               let watts = adapter[kIOPSPowerAdapterWattsKey] as? Int, watts > 0 {
                status.adapterWatts = watts
            }

            // IOKit reports -1 while it is still computing an estimate, which it does for a
            // minute or two after any power state change and after waking from sleep. A nil
            // here means "not known yet", never "no time left".
            let key = status.isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            if let minutes = info[key] as? Int, minutes >= 0 {
                status.minutesRemaining = minutes
            } else {
                status.minutesRemaining = nil
            }
            break
        }

        return status
    }

    // MARK: Notifications

    private func evaluateLowBattery(previous: BatteryStatus, current: BatteryStatus) {
        guard let settings, settings.battery.lowBatteryNotifications else { return }
        guard current.isPresent, !current.isCharging, !current.isPluggedIn else {
            // Charging again re-arms the notification for the next discharge.
            lastNotifiedThresholdCrossing = nil
            return
        }

        let threshold = settings.battery.lowBatteryThreshold
        let crossedDown = previous.percentage > threshold && current.percentage <= threshold
        let startedBelow = previous.percentage == 0 && current.percentage <= threshold

        guard crossedDown || startedBelow else { return }
        guard lastNotifiedThresholdCrossing != threshold else { return }

        lastNotifiedThresholdCrossing = threshold
        onLowBattery?(current.percentage)
    }

    private func evaluatePowerSourceChange(current: BatteryStatus) {
        guard let settings, settings.battery.notifyOnPowerSourceChange else {
            lastPluggedIn = current.isPluggedIn
            return
        }
        defer { lastPluggedIn = current.isPluggedIn }
        guard let lastPluggedIn, lastPluggedIn != current.isPluggedIn else { return }
        onPowerSourceChange?(current.isPluggedIn)
    }
}

#if DEBUG
extension BatteryService {
    /// Injects a fixed reading for offscreen design review, so previews do not depend on
    /// the charge of whatever Mac happens to be rendering them.
    func applySampleStatus() {
        status = BatteryStatus(
            isPresent: true,
            percentage: 68,
            isCharging: false,
            isPluggedIn: false,
            isCharged: false,
            minutesRemaining: 214,
            isLowPowerMode: false
        )
    }

    /// Charging from a 60 W charger, for `--capture-notch --tab system --sample-power`.
    func applySampleCharging(settings: SettingsStore) {
        self.settings = settings
        holdsSamplePower = true
        status = BatteryStatus(
            isPresent: true,
            percentage: 41,
            isCharging: true,
            isPluggedIn: true,
            isCharged: false,
            minutesRemaining: 74,
            isLowPowerMode: false,
            adapterWatts: 60
        )
        power = ChargingPower(input: 53.6, system: 9.7, battery: 42.4)
    }
}
#endif
