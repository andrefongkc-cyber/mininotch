import Accelerate
import Foundation

/// One window of audio turned into numbers: the glow's loudness, bands and beat, and the level of
/// whatever is singing, which is what lyrics are matched against.
///
/// Separate from `AudioAnalyzer` so that something other than the live tap can feed it.
/// `--check-lyric-sync --audio` runs a real song through exactly this code, which is the only way
/// the lyric matching has been judged against music rather than against synthetic clicks.
///
/// Confined to whichever thread feeds it: the tap's queue, or a debug tool's.
struct SpectrumFrameAnalyzer {
    struct Frame {
        var analysis: AudioAnalyzer.Analysis
        /// Decibels of what sits in the middle of the stereo image between 300 Hz and 4 kHz.
        ///
        /// A lead vocal is mixed to the centre and lives in that range; most of what plays around
        /// it does not do both. Guitars and keys are spread wide, cymbals are higher, the kick and
        /// the bass lower. So the centre's energy in the voice range, less the sides', rises when
        /// someone starts singing and falls when they stop, far more than a level of the whole mix
        /// does. On a mono recording there are no sides and this is the voice range of everything.
        var voiceLevel: Double
    }

    /// 1024 frames is about 21 ms at 48 kHz: short enough to catch a transient, long enough for
    /// the low bands to have something to say.
    static let fftSize = 1024
    /// Anything quieter is silence, not a level, so a silent start cannot look like a huge rise.
    static let voiceFloor: Double = -70

    private let dft: vDSP.DiscreteFourierTransform<Float>?
    private let window: [Float]
    private let zeros: [Float]
    /// Scales a raw bin magnitude back to the amplitude of the sinusoid that produced it, so a
    /// full-scale tone reads as 1 rather than as some multiple of the window length. Without it
    /// every decibel figure below is offset by about +48 dB and pinned at the top.
    private let windowGain: Double
    private let voiceBins: ClosedRange<Int>

    private var previousEnergy: Double = 0
    private var beatLevel: Double = 0
    private var lastTime: TimeInterval?

    init(sampleRate: Double) {
        let size = Self.fftSize
        dft = try? vDSP.DiscreteFourierTransform(
            previous: nil,
            count: size,
            direction: .forward,
            transformType: .complexComplex,
            ofType: Float.self
        )
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        zeros = [Float](repeating: 0, count: size)
        windowGain = 2 / max(Double(vDSP.sum(window)), 1)
        let binWidth = max(sampleRate, 8000) / Double(size)
        let low = max(1, Int((300 / binWidth).rounded()))
        voiceBins = low...max(low, min(size / 2 - 1, Int((4000 / binWidth).rounded())))
    }

    /// Analyses one window of `fftSize` frames per channel. `time` is in seconds on any clock that
    /// only moves forward; only differences between calls are used.
    mutating func analyse(left: [Float], right: [Float], at time: TimeInterval) -> Frame? {
        let size = Self.fftSize
        guard let dft, left.count == size, right.count == size else { return nil }

        var mid = [Float](repeating: 0, count: size)
        var side = [Float](repeating: 0, count: size)
        vDSP.add(left, right, result: &mid)
        vDSP.multiply(0.5, mid, result: &mid)
        vDSP.subtract(left, right, result: &side)
        vDSP.multiply(0.5, side, result: &side)

        let midPower = power(of: mid, using: dft)
        let sidePower = power(of: side, using: dft)

        let magnitudes = midPower.map { sqrt($0) }
        let energy = Loudness.normalised(amplitude: Double(vDSP.rootMeanSquare(mid)))
        let bands = bucket(magnitudes)

        let elapsed = lastTime.map { max(0, time - $0) } ?? 0
        lastTime = time
        // A sharp rise over the previous window is a transient. Windows land about every 11 to
        // 21 ms, which is quick enough to catch one; making it *visible* is the shaper's job.
        let rise = energy - previousEnergy
        previousEnergy = energy
        beatLevel = rise > 0.06 ? 1 : max(0, beatLevel - elapsed * 6)

        var centre: Double = 0
        var sides: Double = 0
        for bin in voiceBins {
            centre += Double(midPower[bin])
            sides += Double(sidePower[bin])
        }
        // Never all of it: a voice doubled wide would otherwise cancel itself out entirely.
        let voice = max(centre - sides, centre * 0.05) * windowGain * windowGain
        let voiceLevel = max(10 * log10(max(voice, 1e-12)), Self.voiceFloor)

        return Frame(analysis: AudioAnalyzer.Analysis(energy: energy, bands: bands, beat: beatLevel), voiceLevel: voiceLevel)
    }

    /// Squared magnitude of each distinct frequency bin. Only the first half carries distinct
    /// frequencies for a real input.
    private func power(of samples: [Float], using dft: vDSP.DiscreteFourierTransform<Float>) -> [Float] {
        let output = dft.transform(real: vDSP.multiply(samples, window), imaginary: zeros)
        let usable = Self.fftSize / 2
        var power = [Float](repeating: 0, count: usable)
        for index in 0..<usable {
            let real = output.real[index]
            let imaginary = output.imaginary[index]
            power[index] = real * real + imaginary * imaginary
        }
        return power
    }

    /// Groups the spectrum into log-spaced bands and maps each onto a tilted decibel scale.
    ///
    /// Two corrections, and both are needed. The *spacing* is logarithmic because pitch is, and
    /// linear buckets put almost everything into the first one. The *magnitude* is logarithmic for
    /// the same reason loudness is, and tilted upward with frequency because music has less energy
    /// per octave as it rises. Skip either and the bass bands are the only ones that ever visibly
    /// move.
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
            bands[band] = Loudness.normalised(amplitude: mean, boost: Double(band) * Loudness.tiltPerBand)
        }
        return bands
    }

    /// Maps a linear amplitude onto the 0...1 range the glow works in, by way of decibels.
    ///
    /// Loudness is logarithmic and a linear FFT magnitude is not, so a linear map spends almost
    /// its whole range on the difference between loud and very loud. Everything below that sits
    /// squashed against zero, which is why a correct analysis can still drive a visual that barely
    /// moves.
    private enum Loudness {
        /// Quietest level that registers at all. Anything below is silence.
        static let floorDecibels: Double = -62
        /// Lift applied per band as frequency rises. Music carries far less energy per octave
        /// towards the top, so even in decibels a hi-hat reads as inert beside a kick without it.
        /// Three decibels a band over eight log-spaced bands is the usual pink tilt.
        static let tiltPerBand: Double = 3

        static func normalised(amplitude: Double, boost: Double = 0) -> Double {
            guard amplitude > 0 else { return 0 }
            let decibels = 20 * log10(amplitude) + boost
            return min(max((decibels - floorDecibels) / -floorDecibels, 0), 1)
        }
    }
}
