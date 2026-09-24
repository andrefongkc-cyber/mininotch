import AppKit
import AudioToolbox
import CoreAudio
import Observation

/// One place sound can go.
struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
    let symbolName: String
}

/// The Mac's sound outputs, which one is in use, and its volume, for the Now Playing card.
///
/// Everything here is public Core Audio and needs no permission: the device list, the default
/// output, and the default output's volume are what the Sound menu in Control Center reads and
/// writes too. Changes arrive as property listeners on the main queue, so the list stays right
/// when AirPods connect or a display with speakers is plugged in while the sheet is open.
///
/// Reference counted to the view that shows it, like every other sampler here: nothing listens
/// while the output sheet is closed.
///
/// AirPlay appears as one device, as it does to every app: which receivers it sends to is
/// chosen in Control Center, and there is no public way to list or pick them.
@Observable
@MainActor
final class AudioOutputService {
    private(set) var devices: [AudioOutputDevice] = []
    private(set) var defaultID: AudioObjectID?
    /// Nil when the current output has no volume that can be set in software, such as some
    /// HDMI displays, whose volume is on the display itself.
    private(set) var volume: Double?
    private(set) var isMuted = false

    @ObservationIgnored private var users = 0
    @ObservationIgnored private var systemListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var volumeListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var watchedDevice: AudioObjectID?

    // MARK: Lifecycle

    func beginObserving() {
        users += 1
        guard users == 1 else { return }

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refresh()
        }
        systemListener = listener
        var devicesAddress = Self.address(kAudioHardwarePropertyDevices)
        var defaultAddress = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, .main, listener)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, .main, listener)
        refresh()
    }

    func endObserving() {
        guard users > 0 else { return }
        users -= 1
        guard users == 0 else { return }

        if let listener = systemListener {
            var devicesAddress = Self.address(kAudioHardwarePropertyDevices)
            var defaultAddress = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, .main, listener)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, .main, listener)
        }
        systemListener = nil
        watchVolume(of: nil)
    }

    /// Reads everything again. Cheap: a handful of property reads.
    func refresh() {
        devices = Self.outputDevices()
        defaultID = Self.defaultOutput()
        watchVolume(of: defaultID)
        readVolume()
    }

    // MARK: Changing

    /// Sends sound to `device`, as picking it in the Sound menu does.
    func select(_ device: AudioOutputDevice) {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = device.id
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioObjectID>.size), &id
        )
        refresh()
    }

    /// Sets the current output's volume, unmuting it when the level goes above zero, which is
    /// what the volume keys do.
    func setVolume(_ level: Double) {
        guard let device = defaultID else { return }
        var address = Self.volumeAddress
        guard Self.isSettable(device, &address) else { return }
        var value = Float32(min(max(level, 0), 1))
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)

        var muteAddress = Self.muteAddress
        if Self.isSettable(device, &muteAddress) {
            var muted = UInt32(value <= 0 ? 1 : 0)
            AudioObjectSetPropertyData(device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &muted)
        }
        readVolume()
    }

    // MARK: Volume

    private func watchVolume(of device: AudioObjectID?) {
        guard device != watchedDevice else { return }
        if let old = watchedDevice, let listener = volumeListener {
            var volume = Self.volumeAddress
            var mute = Self.muteAddress
            AudioObjectRemovePropertyListenerBlock(old, &volume, .main, listener)
            AudioObjectRemovePropertyListenerBlock(old, &mute, .main, listener)
        }
        watchedDevice = nil
        volumeListener = nil
        guard let device, users > 0 else { return }

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.readVolume()
        }
        var volume = Self.volumeAddress
        var mute = Self.muteAddress
        AudioObjectAddPropertyListenerBlock(device, &volume, .main, listener)
        AudioObjectAddPropertyListenerBlock(device, &mute, .main, listener)
        volumeListener = listener
        watchedDevice = device
    }

    private func readVolume() {
        guard let device = defaultID else {
            volume = nil
            return
        }
        var address = Self.volumeAddress
        var level = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        if Self.isSettable(device, &address),
           AudioObjectGetPropertyData(device, &address, 0, nil, &size, &level) == noErr {
            volume = Double(level)
        } else {
            volume = nil
        }

        var muteAddress = Self.muteAddress
        var muted = UInt32(0)
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(device, &muteAddress) {
            AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &muteSize, &muted)
        }
        isMuted = muted != 0
    }

    // MARK: Reading devices

    private static let volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func isSettable(_ device: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> Bool {
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    static func defaultOutput() -> AudioObjectID? {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    /// Every device sound can be sent to, in the order Core Audio lists them.
    ///
    /// Leaves out input-only devices, hidden ones, anything that cannot be the default output,
    /// and aggregates: an aggregate is plumbing, such as the private one the audio tap builds
    /// to listen through, not somewhere a person means to send sound.
    static func outputDevices() -> [AudioOutputDevice] {
        var address = address(kAudioHardwarePropertyDevices)
        var size = UInt32(0)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasOutputStreams(id), canBeDefault(id), !isHidden(id) else { return nil }
            let transport = uint32(id, kAudioDevicePropertyTransportType)
            guard transport != kAudioDeviceTransportTypeAggregate,
                  transport != kAudioDeviceTransportTypeAutoAggregate else { return nil }
            let name = name(of: id) ?? "Output"
            let symbol = symbol(transport: transport, name: name)
            // Some of these symbols are newer than others; an unknown name draws nothing at all.
            let drawable = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil ? "speaker.wave.2" : symbol
            return AudioOutputDevice(id: id, name: name, symbolName: drawable)
        }
    }

    private static func hasOutputStreams(_ id: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        var size = UInt32(0)
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func canBeDefault(_ id: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(id, &address) else { return true }
        var value = UInt32(1)
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return value != 0
    }

    private static func isHidden(_ id: AudioObjectID) -> Bool {
        uint32(id, kAudioDevicePropertyIsHidden) != 0
    }

    private static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var address = address(selector)
        guard AudioObjectHasProperty(id, &address) else { return 0 }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return value
    }

    private static func name(of id: AudioObjectID) -> String? {
        var address = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    /// A symbol for the kind of output, and for AirPods and Beats by name, since Bluetooth
    /// alone does not say whether it is earbuds, a headset or a speaker.
    private static func symbol(transport: UInt32, name: String) -> String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            if name.contains("AirPods Max") { return "airpodsmax" }
            if name.contains("AirPods Pro") { return "airpodspro" }
            if name.contains("AirPods") { return "airpods" }
            if name.contains("Beats") { return "beats.headphones" }
            return "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "tv"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeUSB:
            return "hifispeaker"
        case kAudioDeviceTransportTypeVirtual:
            return "waveform"
        default:
            return "speaker.wave.2"
        }
    }
}
