import AudioToolbox
import CoreAudio
import Observation

/// Taps system audio output and turns it into the few numbers the glow styles need.
///
/// Uses Core Audio process taps, added in macOS 14.2. This replaces an earlier
/// ScreenCaptureKit implementation, which worked but was the wrong shape: ScreenCaptureKit
/// treats audio as a by-product of screen capture, so it asked for the screen recording
/// permission in order to read sound. A process tap is audio-only and raises its own system
/// audio recording permission instead, which is both narrower and far less alarming to grant.
///
/// The pattern Core Audio requires is indirect: create a tap, wrap it in a private aggregate
/// device alongside the real output device, then run an IO proc against that aggregate. A tap
/// cannot be read directly.
///
/// Everything heavy happens on the IO queue. Only the computed numbers cross to the main
/// thread, and only as often as buffers arrive.
@Observable
@MainActor
final class AudioAnalyzer {
    struct Analysis: Equatable {
        /// 0...1 overall loudness, on a decibel scale and before any gain riding.
        var energy: Double
        /// Per-band energy, low to high, each on the same scale as `energy`.
        var bands: [Double]
        /// 1 at an onset, decaying afterwards.
        var beat: Double
    }

    /// Why the tap is not running, when it is not.
    enum Failure: Error, Equatable {
        case unsupported(String)
        case coreAudio(OSStatus, String)

        var message: String {
            switch self {
            case .unsupported(let reason):
                return reason
            case .coreAudio(let status, let stage):
                // Core Audio reports a refused permission as an ordinary failure, so this is
                // very often the user having said no rather than anything being broken.
                return "Core Audio returned \(status) while \(stage). If you have not granted system audio recording, that is the usual cause."
            }
        }
    }

    /// The level of whatever is singing, with the moment it was heard, for every window analysed.
    /// Used to match lyric files to the audio (`LyricsSyncCalibrator`); the glow reads `current`.
    @ObservationIgnored var onVoiceLevel: ((Date, Double) -> Void)?

    private(set) var current: Analysis?
    private(set) var isRunning = false
    private(set) var failure: Failure?

    /// Seconds of buffering between the system reporting a playback position and the sound
    /// actually being audible. Large over Bluetooth and AirPlay, near zero over built-in
    /// speakers. Read when the tap starts, and kept while it is paused between songs.
    private(set) var outputLatency: TimeInterval = 0
    /// True once `outputLatency` has been read at all this launch.
    private(set) var hasMeasuredLatency = false

    // MARK: Audio-queue state
    //
    // Everything below is set up and read on `queue`, where Core Audio also delivers the IO
    // block, not on the main actor the published state above lives on. `nonisolated(unsafe)`
    // says exactly that: the compiler is told the confinement rather than asked to prove it.
    // The one crossing is `teardown()` from `stop()` on main, which only makes Core Audio
    // calls (thread-safe) and resets the identifiers; a buffer already in flight at that
    // moment is analysed once more and published into a stopped analyser, which is harmless.

    @ObservationIgnored nonisolated(unsafe) private var tapID = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored nonisolated(unsafe) private var tapUUID = UUID()
    @ObservationIgnored nonisolated(unsafe) private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored nonisolated(unsafe) private var ioProcID: AudioDeviceIOProcID?
    @ObservationIgnored private let queue = DispatchQueue(label: "com.minnotch.audio-tap", qos: .userInitiated)

    /// The analysis itself, made when the tap's format is known. See `SpectrumFrameAnalyzer`.
    @ObservationIgnored nonisolated(unsafe) private var spectrum: SpectrumFrameAnalyzer?
    /// The most recent frames of each channel, two windows' worth.
    @ObservationIgnored nonisolated(unsafe) private var leftSamples: [Float] = []
    @ObservationIgnored nonisolated(unsafe) private var rightSamples: [Float] = []

    /// Where "the tap has started here before" is remembered. See `start()`.
    @ObservationIgnored private let defaults: UserDefaults
    private static let grantedKey = "audioTap.granted"
    /// True while this start has the app in front for the permission prompt, so exactly one
    /// `ForegroundPrompt.end()` answers the one `begin()`, whichever of success, failure or the
    /// timeout comes first.
    @ObservationIgnored private var isPrompting = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    deinit { teardown() }

    // MARK: Lifecycle

    /// Starts the tap.
    ///
    /// Does nothing when already running, or when a previous attempt failed. That second
    /// guard matters: without it a refused permission turned into a fresh prompt every time
    /// any unrelated setting changed, because the settings fan-out calls this every time.
    /// Clearing a failure is `retry()`, which only a deliberate user action calls.
    func start() {
        guard !isRunning, !isStarting, failure == nil else { return }
        isStarting = true

        // The system audio prompt, like every other, is only shown to the active app, and this
        // one is an accessory app that never activates. Asking from the background is why the
        // request used to hang with nothing on screen. But only when a prompt can appear: once
        // the tap has started here, the answer is already given, and coming to the front
        // anyway flashed a Dock icon and took focus from whatever the user was doing, at every
        // launch. If the permission has since been taken away, this start times out below, the
        // memory is cleared, and the Retry that follows asks from the front again.
        if !defaults.bool(forKey: Self.grantedKey) {
            isPrompting = true
            ForegroundPrompt.begin()
        }

        // Off the main thread, and not optional. `AudioHardwareCreateProcessTap` does not
        // return until the system has decided whether this process may listen, and on a
        // build that cannot raise the permission prompt it does not return at all. Called
        // inline from the settings fan-out, that froze the whole interface.
        queue.async { [weak self] in
            guard let self else { return }

            do {
                try self.createTap()
                try self.createAggregateDevice()
                try self.startIO()
                let latency = OutputLatency.current()

                DispatchQueue.main.async {
                    self.endPrompt(granted: true)
                    self.isStarting = false
                    self.isRunning = true
                    self.outputLatency = latency
                    self.hasMeasuredLatency = true
                }
            } catch let error as Failure {
                self.teardown()
                DispatchQueue.main.async {
                    self.endPrompt(granted: false)
                    self.isStarting = false
                    self.failure = error
                    AppLog.media.error("Audio tap failed: \(error.message, privacy: .public)")
                }
            } catch {
                self.teardown()
                DispatchQueue.main.async {
                    self.endPrompt(granted: false)
                    self.isStarting = false
                    self.failure = .unsupported(error.localizedDescription)
                }
            }
        }

        // A tap that never comes back is reported rather than left spinning forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.isStarting else { return }
            self.endPrompt(granted: false)
            self.isStarting = false
            self.failure = .unsupported(
                "The system did not answer the request to record audio within eight seconds. If no permission dialog appeared, allow MinNotch under Privacy & Security > Screen & System Audio Recording, then try again."
            )
        }
    }

    /// True between asking for the tap and hearing back.
    private(set) var isStarting = false

    /// Hands the foreground back if this start took it, and remembers the answer: a tap that
    /// started means the permission is granted, so the next start need not come to the front.
    private func endPrompt(granted: Bool) {
        if isPrompting {
            isPrompting = false
            ForegroundPrompt.end()
        }
        defaults.set(granted, forKey: Self.grantedKey)
    }

    /// Stops the tap and clears any recorded failure.
    ///
    /// Clearing the failure here is what makes switching the setting off and back on the
    /// natural way to retry, without unrelated settings changes being able to re-prompt.
    func stop() {
        teardown()
        isStarting = false
        isRunning = false
        current = nil
        failure = nil
    }

    /// Stops listening for now, keeping any recorded failure.
    ///
    /// For when nothing is playing, not for when the setting goes off. `stop()` clears the
    /// failure so that switching the setting off and on asks again; a pause that did that would
    /// turn a refused permission into a fresh prompt every time a song started.
    func pause() {
        guard !isStarting else { return }
        teardown()
        isRunning = false
        current = nil
    }

    /// Clears a recorded failure and tries again. Called from the Settings row, never
    /// automatically.
    func retry() {
        failure = nil
        // A deliberate retry always asks from the front, whatever was remembered.
        defaults.set(false, forKey: Self.grantedKey)
        start()
    }

    /// Re-reads the output device's latency, after the device changes.
    func refreshLatency() {
        outputLatency = OutputLatency.current()
        hasMeasuredLatency = true
    }

    // MARK: Core Audio setup

    nonisolated private func createTap() throws {
        // Everything the machine is playing. Our own process is excluded so the effect
        // cannot feed back into the analysis.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "MinNotch Ambient Lighting"
        description.uuid = UUID()
        description.isPrivate = true
        // The tap must not silence what it is listening to.
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr, tap != kAudioObjectUnknown else {
            throw Failure.coreAudio(status, "creating the process tap")
        }

        tapID = tap
        tapUUID = description.uuid
    }

    nonisolated private func createAggregateDevice() throws {
        guard let outputUID = OutputLatency.defaultOutputDeviceUID() else {
            throw Failure.unsupported("There is no default output device to attach the tap to.")
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MinNotch Ambient Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            // Private, so it never appears in Sound settings or other apps' device lists.
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapUUID.uuidString
                ]
            ]
        ]

        var aggregate = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregate)
        guard status == noErr, aggregate != kAudioObjectUnknown else {
            throw Failure.coreAudio(status, "creating the aggregate device")
        }
        aggregateID = aggregate
    }

    nonisolated private func startIO() throws {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let formatStatus = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format)
        guard formatStatus == noErr else {
            throw Failure.coreAudio(formatStatus, "reading the tap's format")
        }
        spectrum = SpectrumFrameAnalyzer(sampleRate: format.mSampleRate)
        leftSamples.removeAll()
        rightSamples.removeAll()

        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) {
            [weak self] _, inputData, _, _, _ in
            self?.handle(inputData)
        }
        guard status == noErr, let procID else {
            throw Failure.coreAudio(status, "creating the IO proc")
        }
        ioProcID = procID

        let startStatus = AudioDeviceStart(aggregateID, procID)
        guard startStatus == noErr else {
            throw Failure.coreAudio(startStatus, "starting the aggregate device")
        }
    }

    nonisolated private func teardown() {
        if let ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil

        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    // MARK: Analysis

    /// Splits a buffer into its two channels and analyses the latest window of each.
    ///
    /// The tap delivers interleaved stereo in one buffer; a non-interleaved device would give one
    /// buffer per channel, and a mono one a single channel, which is used for both.
    nonisolated private func handle(_ bufferList: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        guard let first = buffers.first, let data = first.mData else { return }

        let sampleCount = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        guard sampleCount > 0 else { return }
        let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: sampleCount)

        let channels = Int(first.mNumberChannels)
        if channels >= 2 {
            for index in stride(from: 0, to: sampleCount - 1, by: channels) {
                leftSamples.append(samples[index])
                rightSamples.append(samples[index + 1])
            }
        } else if buffers.count >= 2, let secondData = buffers[1].mData {
            let second = UnsafeBufferPointer(
                start: secondData.assumingMemoryBound(to: Float.self),
                count: min(sampleCount, Int(buffers[1].mDataByteSize) / MemoryLayout<Float>.size)
            )
            leftSamples.append(contentsOf: samples.prefix(second.count))
            rightSamples.append(contentsOf: second)
        } else {
            leftSamples.append(contentsOf: samples)
            rightSamples.append(contentsOf: samples)
        }

        let size = SpectrumFrameAnalyzer.fftSize
        if leftSamples.count > size * 2 {
            leftSamples.removeFirst(leftSamples.count - size * 2)
            rightSamples.removeFirst(rightSamples.count - size * 2)
        }
        guard leftSamples.count >= size, spectrum != nil else { return }

        let now = Date()
        guard let frame = spectrum?.analyse(
            left: Array(leftSamples.suffix(size)),
            right: Array(rightSamples.suffix(size)),
            at: now.timeIntervalSinceReferenceDate
        ) else { return }

        // Deliberately no gain riding here. Levelling happens once, in `GlowDynamics`, which runs
        // per displayed frame and therefore knows how much time has passed.
        DispatchQueue.main.async { [weak self] in
            self?.current = frame.analysis
            self?.onVoiceLevel?(now, frame.voiceLevel)
        }
    }
}

/// Reads how far the current output device lags what the system thinks it is playing.
///
/// Bluetooth and AirPlay buffer audio for tens to hundreds of milliseconds, so the position a
/// player reports is ahead of what is actually audible. Subtracting this is what makes lyrics
/// line up with what is being heard rather than with what has already been handed to the
/// speakers.
enum OutputLatency {
    static func current() -> TimeInterval {
        guard let device = defaultOutputDeviceID() else { return 0 }

        let frames = property(device, kAudioDevicePropertyLatency)
            + property(device, kAudioDevicePropertySafetyOffset)
            + streamLatency(device)

        let rate = sampleRate(device)
        guard rate > 0 else { return 0 }
        return Double(frames) / rate
    }

    static func defaultOutputDeviceID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    static func defaultOutputDeviceUID() -> String? {
        guard let device = defaultOutputDeviceID() else { return nil }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        // Core Audio hands back a +1 reference, so this has to go through `Unmanaged`
        // rather than a bridged optional, which would leak or over-release.
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    private static func property(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : 0
    }

    private static func streamLatency(_ device: AudioObjectID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }

        let count = Int(size) / MemoryLayout<AudioStreamID>.size
        var streams = [AudioStreamID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &streams) == noErr,
              let stream = streams.first else { return 0 }

        var streamAddress = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyLatency,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var latency: UInt32 = 0
        var latencySize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(stream, &streamAddress, 0, nil, &latencySize, &latency)
        return status == noErr ? latency : 0
    }

    private static func sampleRate(_ device: AudioObjectID) -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate)
        return status == noErr ? rate : 0
    }
}
