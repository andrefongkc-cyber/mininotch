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

    private var handle: UnsafeMutableRawPointer?
    private var getBrightness: GetBrightnessFunction?

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

        guard let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return }
        getBrightness = unsafeBitCast(symbol, to: GetBrightnessFunction.self)
        isBrightnessSupported = readBrightness() != nil
    }

    /// Brightness of the main display, 0...1.
    func readBrightness() -> Double? {
        guard let getBrightness else { return nil }
        var level: Float = 0
        let display = CGMainDisplayID()
        guard getBrightness(display, &level) == 0 else { return nil }
        guard level.isFinite, level >= 0 else { return nil }
        return Double(level)
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
