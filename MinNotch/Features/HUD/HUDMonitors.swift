import AudioToolbox
import CoreAudio
import CoreGraphics
import Foundation
import IOKit

/// What a HUD is reporting.
struct HUDReading: Equatable {
    enum Kind: String, Equatable {
        case volume
        case brightness
        case keyboardBacklight

        var symbolName: String {
            switch self {
            case .volume: return "speaker.wave.2.fill"
            case .brightness: return "sun.max.fill"
            case .keyboardBacklight: return "keyboard"
            }
        }

        var mutedSymbolName: String {
            switch self {
            case .volume: return "speaker.slash.fill"
            case .brightness: return "sun.min.fill"
            case .keyboardBacklight: return "keyboard"
            }
        }

        var title: String {
            switch self {
            case .volume: return "Volume"
            case .brightness: return "Brightness"
            case .keyboardBacklight: return "Keyboard Backlight"
            }
        }
    }

    var kind: Kind
    /// 0...1.
    var value: Double
    var isMuted: Bool = false

    var symbolName: String {
        if isMuted || value <= 0.001 { return kind.mutedSymbolName }
        return kind.symbolName
    }

    var percentage: Int { Int((min(max(value, 0), 1) * 100).rounded()) }
}

/// Watches the default output device's volume.
///
/// CoreAudio posts a change notification, so this is event driven rather than polled, and it
/// needs no permission. The device itself can change underneath us when headphones are
/// plugged in, so the listener is re-registered when the default output changes.
final class VolumeMonitor {
    var onChange: ((Double, Bool) -> Void)?

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var isRunning = false

    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        guard !isRunning else { return }
        isRunning = true

        attachToDefaultDevice()

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.attachToDefaultDevice()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        detach()
    }

    private func attachToDefaultDevice() {
        detach()

        var newID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            0,
            nil,
            &size,
            &newID
        )
        guard status == noErr, newID != kAudioObjectUnknown else { return }
        deviceID = newID

        let handler: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.publish()
        }
        AudioObjectAddPropertyListenerBlock(deviceID, &volumeAddress, DispatchQueue.main, handler)
        AudioObjectAddPropertyListenerBlock(deviceID, &muteAddress, DispatchQueue.main, handler)
    }

    private func detach() {
        guard deviceID != kAudioObjectUnknown else { return }
        deviceID = AudioObjectID(kAudioObjectUnknown)
    }

    private func publish() {
        guard let reading = read() else { return }
        onChange?(reading.0, reading.1)
    }

    // MARK: Setting

    /// Does what a volume or mute key does to the default output, and returns the new level and
    /// mute state. Nil when this output cannot do it in software, so the key can go to macOS.
    ///
    /// Steps on the same grid macOS uses, sixteenths, or sixty-fourths with Shift and Option,
    /// rounding the current level onto the grid first so a level set by a slider elsewhere does
    /// not leave every later step off by a fraction. Stepping up unmutes; reaching zero mutes.
    func apply(_ key: SystemKeyInterceptor.Key, fineStep: Bool) -> (level: Double, muted: Bool)? {
        guard let device = Self.defaultOutputDevice() else { return nil }

        var level = Float32(0)
        var levelSize = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &levelSize, &level) == noErr else {
            return nil
        }

        let hasMute = Self.isSettable(device, &muteAddress)
        var mutedValue = UInt32(0)
        if hasMute {
            var size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &mutedValue)
        }
        var muted = mutedValue != 0

        switch key {
        case .mute:
            guard hasMute else { return nil }
            muted.toggle()
        case .volumeUp, .volumeDown:
            guard Self.isSettable(device, &volumeAddress) else { return nil }
            let steps: Float32 = fineStep ? 64 : 16
            let direction: Float32 = key == .volumeUp ? 1 : -1
            let next = min(max(((level * steps).rounded() + direction) / steps, 0), 1)
            var value = next
            guard AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, levelSize, &value) == noErr else {
                return nil
            }
            level = next
            muted = hasMute ? next <= 0 : false
        default:
            return nil
        }

        if hasMute, muted != (mutedValue != 0) {
            var value = UInt32(muted ? 1 : 0)
            AudioObjectSetPropertyData(device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        }
        return (Double(level), muted)
    }

    /// True when the default output's volume can be set in software, which is when the volume
    /// keys can be taken at all.
    var canSetVolume: Bool {
        guard let device = Self.defaultOutputDevice() else { return false }
        return Self.isSettable(device, &volumeAddress)
    }

    /// Read fresh on each key press rather than taken from the listener, which only tracks the
    /// device while the volume indicator is on.
    private static func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func isSettable(_ device: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> Bool {
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    /// Current level and mute state, or nil when the device exposes neither.
    func read() -> (Double, Bool)? {
        guard deviceID != kAudioObjectUnknown else { return nil }

        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let volumeStatus = AudioObjectGetPropertyData(deviceID, &volumeAddress, 0, nil, &size, &volume)
        guard volumeStatus == noErr else { return nil }

        var muted = UInt32(0)
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &muteSize, &muted)

        return (Double(volume), muted != 0)
    }
}

/// Reads display brightness and keyboard backlight.
///
/// Neither has a public read API on Apple silicon. Brightness comes from DisplayServices,
/// loaded with `dlopen` the same way MediaRemote is, so a macOS release that renames the
/// symbol degrades to "unsupported" rather than failing to launch. Keyboard backlight is read
/// from the IO registry, which not every keyboard publishes.
///
/// Neither posts a change notification, so the coordinator polls these while the feature is
/// switched on, and only while it is switched on.
final class BrightnessMonitor {
    private typealias GetBrightnessFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFunction = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private var handle: UnsafeMutableRawPointer?
    private var getBrightness: GetBrightnessFunction?
    private var setBrightness: SetBrightnessFunction?

    private(set) var isBrightnessSupported = false
    private(set) var isKeyboardBacklightSupported = false

    init() {
        loadDisplayServices()
        isKeyboardBacklightSupported = readKeyboardBacklight() != nil
    }

    private func loadDisplayServices() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_NOW) else { return }
        self.handle = handle

        if let setter = dlsym(handle, "DisplayServicesSetBrightness") {
            setBrightness = unsafeBitCast(setter, to: SetBrightnessFunction.self)
        }
        guard let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return }
        getBrightness = unsafeBitCast(symbol, to: GetBrightnessFunction.self)
        isBrightnessSupported = readBrightness() != nil
    }

    /// Brightness of the display the brightness keys control, 0...1.
    func readBrightness() -> Double? {
        guard let getBrightness else { return nil }
        var level: Float = 0
        guard getBrightness(Self.keyboardDisplay, &level) == 0 else { return nil }
        guard level.isFinite, level >= 0 else { return nil }
        return Double(level)
    }

    /// True when brightness can be both read and set, which is when the brightness keys can be
    /// taken at all.
    var canSetBrightness: Bool { setBrightness != nil && readBrightness() != nil }

    /// Does what a brightness key does, and returns the new level, or nil if it could not be set.
    /// Steps in sixteenths, or sixty-fourths with Shift and Option, as macOS does.
    func apply(_ key: SystemKeyInterceptor.Key, fineStep: Bool) -> Double? {
        guard key == .brightnessUp || key == .brightnessDown,
              let setBrightness, let current = readBrightness() else { return nil }

        let steps = fineStep ? 64.0 : 16.0
        let direction = key == .brightnessUp ? 1.0 : -1.0
        let next = min(max(((current * steps).rounded() + direction) / steps, 0), 1)
        guard setBrightness(Self.keyboardDisplay, Float(next)) == 0 else { return nil }
        return next
    }

    /// The built-in display when there is one, which is the one a Mac's brightness keys
    /// adjust, even when an external monitor is the main display.
    private static var keyboardDisplay: CGDirectDisplayID {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        if CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success,
           let builtIn = displays.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) {
            return builtIn
        }
        return CGMainDisplayID()
    }

    /// Keyboard backlight level, 0...1, or nil on a keyboard that does not report it.
    func readKeyboardBacklight() -> Double? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleHIDKeyboardEventDriverV2")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            let keys = ["KeyboardBacklightBrightness", "BacklightBrightness", "KeyboardBacklight"]
            for key in keys {
                guard let raw = IORegistryEntryCreateCFProperty(
                    service,
                    key as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue() as? Int else { continue }
                // Reported 0...4095 on most keyboards.
                return min(max(Double(raw) / 4095.0, 0), 1)
            }
        }
        return nil
    }
}
