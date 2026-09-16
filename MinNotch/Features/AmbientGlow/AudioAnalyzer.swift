import Accelerate
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

    private(set) var current: Analysis?
    private(set) var isRunning = false
    private(set) var failure: Failure?

    /// Seconds of buffering between the system reporting a playback position and the sound
    /// actually being audible. Large over Bluetooth and AirPlay, near zero over built-in
    /// speakers.
    private(set) var outputLatency: TimeInterval = 0

    @ObservationIgnored private var tapID = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored private var tapUUID = UUID()
    @ObservationIgnored private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored private var ioProcID: AudioDeviceIOProcID?
    @ObservationIgnored private let queue = DispatchQueue(label: "com.minnotch.audio-tap", qos: .userInitiated)

    /// 1024 frames is about 21 ms at 48 kHz: short enough to catch a transient, long enough
    /// for the low bands to have something to say.
    @ObservationIgnored private let fftSize = 1024
    @ObservationIgnored private var dft: vDSP.DiscreteFourierTransform<Float>?
    @ObservationIgnored private var window: [Float] = []
    @ObservationIgnored private var sampleBuffer: [Float] = []
    /// Scales a raw bin magnitude back to the amplitude of the sinusoid that produced it, so
    /// a full-scale tone reads as 1 rather than as some multiple of the window length.
    /// Without it every decibel figure below is offset by about +48 dB and pinned at the top.
    @ObservationIgnored private var windowGain: Double = 1

    @ObservationIgnored private var previousEnergy: Double = 0
    @ObservationIgnored private var beatLevel: Double = 0
    @ObservationIgnored private var lastPublish = Date()

    init() {
        dft = try? vDSP.DiscreteFourierTransform(
            previous: nil,
            count: fftSize,
            direction: .forward,
            transformType: .complexComplex,
            ofType: Float.self
        )
        window = vDSP.window(
            ofType: Float.self,
            usingSequence: .hanningDenormalized,
            count: fftSize,
            isHalfWindow: false
        )
        windowGain = 2 / max(Double(vDSP.sum(window)), 1)
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
        // request used to hang with nothing on screen.
        DispatchQueue.main.async { ForegroundPrompt.begin() }

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
                    ForegroundPrompt.end()
                    self.isStarting = false
                    self.isRunning = true
                    self.outputLatency = latency
                }
            } catch let error as Failure {
                self.teardown()
                DispatchQueue.main.async {
                    ForegroundPrompt.end()
                    self.isStarting = false
                    self.failure = error
                    AppLog.media.error("Audio tap failed: \(error.message, privacy: .public)")
                }
            } catch {
                self.teardown()
                DispatchQueue.main.async {
                    ForegroundPrompt.end()
                    self.isStarting = false
                    self.failure = .unsupported(error.localizedDescription)
                }
            }
        }

        // A tap that never comes back is reported rather than left spinning forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.isStarting else { return }
            ForegroundPrompt.end()
            self.isStarting = false
            self.failure = .unsupported(
                "The system did not answer the request to record audio within eight seconds. If no permission dialog appeared, allow MinNotch under Privacy & Security > Screen & System Audio Recording, then try again."
            )
        }
    }

    /// True between asking for the tap and hearing back.
    private(set) var isStarting = false

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

    /// Clears a recorded failure and tries again. Called from the Settings row, never
    /// automatically.
    func retry() {
        failure = nil
        start()
    }

    /// Re-reads the output device's latency, after the device changes.
    func refreshLatency() {
        outputLatency = OutputLatency.current()
    }

    // MARK: Core Audio setup

    private func createTap() throws {
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

    private func createAggregateDevice() throws {
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

    private func startIO() throws {
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

    private func teardown() {
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

    private func handle(_ bufferList: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: bufferList)
        )
        guard let first = buffers.first, let data = first.mData else { return }

        let sampleCount = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        guard sampleCount > 0 else { return }

        let pointer = data.assumingMemoryBound(to: Float.self)
        let incoming = UnsafeBufferPointer(start: pointer, count: sampleCount)

        // Interleaved stereo arrives as one buffer. One channel is plenty for a lighting
        // effect and halves the work.
        let channelStride = max(Int(first.mNumberChannels), 1)
        var mono = [Float]()
        mono.reserveCapacity(sampleCount / channelStride)
        for index in stride(from: 0, to: sampleCount, by: channelStride) {
            mono.append(incoming[index])
        }

        sampleBuffer.append(contentsOf: mono)
        if sampleBuffer.count > fftSize * 2 {
            sampleBuffer.removeFirst(sampleBuffer.count - fftSize * 2)
        }
        guard sampleBuffer.count >= fftSize else { return }

        analyse(Array(sampleBuffer.suffix(fftSize)))
    }

    private func analyse(_ frame: [Float]) {
        guard let dft else { return }

        let windowed = vDSP.multiply(frame, window)
        let output = dft.transform(
            real: windowed,
            imaginary: [Float](repeating: 0, count: fftSize)
        )

        // Only the first half carries distinct frequencies for a real input signal.
        let usable = fftSize / 2
        var magnitudes = [Float](repeating: 0, count: usable)
        for index in 0..<usable {
            let real = output.real[index]
            let imaginary = output.imaginary[index]
            magnitudes[index] = sqrt(real * real + imaginary * imaginary)
        }

        publish(energy: Double(vDSP.rootMeanSquare(frame)), bands: bucket(magnitudes))
    }

    /// Maps a linear amplitude onto the 0...1 range the glow works in, by way of decibels.
    ///
    /// Loudness is logarithmic and a linear FFT magnitude is not, so a linear map spends
    /// almost its whole range on the difference between loud and very loud. Everything below
    /// that sits squashed against zero, which is why a correct analysis can still drive a
    /// visual that barely moves.
    private enum Loudness {
        /// Quietest level that registers at all. Anything below is silence.
        static let floorDecibels: Double = -62
        /// Lift applied per band as frequency rises. Music carries far less energy per octave
        /// towards the top, so even in decibels a hi-hat reads as inert beside a kick without
        /// it. Three decibels a band over eight log-spaced bands is the usual pink tilt.
        static let tiltPerBand: Double = 3

        static func normalised(amplitude: Double, boost: Double = 0) -> Double {
            guard amplitude > 0 else { return 0 }
            let decibels = 20 * log10(amplitude) + boost
            return min(max((decibels - floorDecibels) / -floorDecibels, 0), 1)
        }
    }

    /// Groups the spectrum into log-spaced bands and maps each onto a tilted decibel scale.
    ///
    /// Two corrections, and both are needed. The *spacing* is logarithmic because pitch is,
    /// and linear buckets put almost everything into the first one. The *magnitude* is
    /// logarithmic for the same reason loudness is, and tilted upward with frequency because
    /// music has less energy per octave as it rises. Skip either and the bass bands are the
    /// only ones that ever visibly move.
    private func bucket(_ magnitudes: [Float]) -> [Double] {
        let count = GlowInput.bandCount
        var bands = [Double](repeating: 0, count: count)
        let usable = magnitudes.count

        for band in 0..<count {
            let lower = Int(pow(Double(usable), Double(band) / Double(count)))
            let upper = max(lower + 1, Int(pow(Double(usable), Double(band + 1) / Double(count))))
            let slice = magnitudes[min(lower, usable - 1)..<min(upper, usable)]
            guard !slice.isEmpty else { continue }

            let mean = Double(slice.reduce(0, +)) / Double(slice.count) * windowGain
            bands[band] = Loudness.normalised(
                amplitude: mean, boost: Double(band) * Loudness.tiltPerBand
            )
        }
        return bands
    }

    /// Publishes one buffer's numbers, unscaled.
    ///
    /// Deliberately no gain riding here. It used to divide each band by the loudest band in
    /// the same buffer, which guaranteed that some band was always at full scale no matter
    /// how quiet the music was, so the bars could never all drop together and the effect had
    /// no dynamics at all. Levelling now happens once, in `GlowDynamics`, which runs per
    /// displayed frame and therefore knows how much time has passed.
    private func publish(energy: Double, bands: [Double]) {
        let level = Loudness.normalised(amplitude: energy)

        let now = Date()
        let elapsed = now.timeIntervalSince(lastPublish)
        lastPublish = now

        // A sharp rise over the previous buffer is a transient. Buffers land about every
        // 21 ms, which is quick enough to catch one; making it *visible* is the shaper's job.
        let rise = level - previousEnergy
        previousEnergy = level
        beatLevel = rise > 0.06 ? 1 : max(0, beatLevel - elapsed * 6)

        let analysis = Analysis(energy: level, bands: bands, beat: beatLevel)
        DispatchQueue.main.async { [weak self] in
            self?.current = analysis
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
