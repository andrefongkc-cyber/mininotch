import Foundation

/// Turns level readings into something that reads as a hit.
///
/// Drawing analysis straight is the reason an audio-reactive effect looks flat even when the
/// analysis is correct. A frequency band's magnitude is a noisy, mostly-mid-scale number: it
/// wanders, it never rests at zero, and it never leaps, so a bar driven from it slides around
/// instead of striking. Four stages fix that, in this order:
///
/// 1. **Auto-gain.** A rolling floor and ceiling per channel, so the same drum reads the same
///    whether the track is mastered loud or quiet. Without it a quiet passage barely moves
///    anything and a loud one sits pinned at the top.
/// 2. **Attack and decay.** Rise almost instantly, fall slowly. This is the single biggest
///    difference between "responding to audio" and "hitting on the beat": it is what turns a
///    momentary peak into something the eye has time to see.
/// 3. **A spring.** The visible value chases the envelope through a damped oscillator rather
///    than being assigned to it, so every hit overshoots and settles. That overshoot is the
///    bounce; without it even a perfect envelope reads as snapping between values.
/// 4. **Onset.** A sharp rise in the gained energy is a transient, held briefly so styles can
///    flash on it.
///
/// One instance per glow, held by the view that draws it, because the spring is stateful and
/// has to be stepped once per displayed frame. Nothing here is audio-specific: the fallback
/// animation runs through exactly the same chain, which is what lets a machine with no audio
/// permission still show the real motion.
final class GlowDynamics {

    /// One frame of levels, either raw from the analyser or shaped by this type.
    struct Levels {
        /// 0...1 overall loudness.
        var energy: Double
        /// Per-band energy, low to high, each 0...1.
        var bands: [Double]
        /// 1 at the instant of an onset, decaying to 0. A hint only: the shaper runs its own
        /// detector as well and takes whichever is higher, so a source that cannot supply one
        /// still gets beats.
        var beat: Double

        static let silent = Levels(energy: 0, bands: [], beat: 0)
    }

    /// Every constant the feel depends on, in one place, because tuning these is the whole
    /// job and hunting them through four files is how they drift apart.
    struct Tuning {
        /// Time constant on the way up. Short enough to be immediate, long enough that a
        /// single noisy sample cannot spike the whole effect.
        var attack: TimeInterval = 0.012
        /// Half-life on the way down. This is what the eye reads as the length of the hit.
        var decayHalfLife: TimeInterval = 0.22
        /// How long the auto-gain remembers a loud or quiet passage.
        var gainHalfLife: TimeInterval = 2.5
        /// Below this much range between the rolling floor and ceiling, the input is treated
        /// as silence rather than amplified.
        var gainNoiseFloor: Double = 0.02
        /// The loudest thing heard recently must also clear this in absolute terms.
        ///
        /// A span check alone is not enough, and the trace from `--check-glow` is where that
        /// showed: a steady, almost silent hiss has a small span *and* a small ceiling, and
        /// dividing by that span mapped the hiss to full scale. Silence came out as a glow
        /// running flat out. Both gates have to pass.
        var gainSilenceCeiling: Double = 0.08
        /// Spring period. Shorter is snappier.
        var springResponse: Double = 0.19
        /// Below 1 the spring overshoots, which is the bounce. At 1 it slides in flat.
        var springDamping: Double = 0.58
        /// How far the gained energy has to jump in one frame to count as a transient.
        var onsetRise: Double = 0.11
        /// How long a detected onset stays lit.
        var beatHalfLife: TimeInterval = 0.13
        /// Ceiling on the shaped output. Above 1 so the spring's overshoot survives instead
        /// of being flattened by the clamp, which would remove the very thing it is for.
        var headroom: Double = 1.15

        static let `default` = Tuning()
    }

    private var tuning: Tuning
    private var lastTime: TimeInterval?

    private var energyGain = AutoGain()
    private var energyEnvelope = Envelope()
    private var energySpring = Spring()

    private var bandGains: [AutoGain] = []
    private var bandEnvelopes: [Envelope] = []
    private var bandSprings: [Spring] = []

    private var beatEnvelope = Envelope()
    private var beatSpring = Spring()
    private var previousGainedEnergy: Double = 0

    /// The last frame interval actually observed, for the tuning readout.
    private(set) var frameInterval: TimeInterval = 0

    /// The last raw input and the last shaped output, kept side by side so the tuning
    /// readout can show what each stage did rather than only the end of the chain.
    private(set) var raw: Levels = .silent
    private(set) var shaped: Levels = .silent

    init(tuning: Tuning = .default) {
        self.tuning = tuning
    }

    /// Advances every stage to `time` and returns the shaped levels.
    ///
    /// Safe to call more than once for the same instant: the integrators only advance on a
    /// positive elapsed time, so a second evaluation of the same frame returns the same
    /// answer rather than stepping the spring twice.
    func shape(_ input: Levels, at time: TimeInterval) -> Levels {
        let elapsed = lastTime.map { min(max(time - $0, 0), 0.1) } ?? 0
        lastTime = time
        if elapsed > 0 { frameInterval = elapsed }
        raw = input

        resizeBandStages(to: input.bands.count)

        let gainedEnergy = energyGain.normalise(input.energy, elapsed: elapsed, tuning: tuning)

        // Onset is measured on the gained signal and before the envelope, so it sees the
        // actual jump rather than the smoothed ramp the envelope will make of it.
        let rise = gainedEnergy - previousGainedEnergy
        previousGainedEnergy = gainedEnergy
        let onset = max(rise > tuning.onsetRise ? 1 : 0, input.beat)

        let energy = shape(
            gainedEnergy, envelope: &energyEnvelope, spring: &energySpring, elapsed: elapsed
        )

        var bands = [Double](repeating: 0, count: input.bands.count)
        for index in input.bands.indices {
            let gained = bandGains[index].normalise(input.bands[index], elapsed: elapsed, tuning: tuning)
            bands[index] = shape(
                gained, envelope: &bandEnvelopes[index], spring: &bandSprings[index], elapsed: elapsed
            )
        }

        // A beat is all attack and no sustain, so it gets its own much shorter decay rather
        // than the one that shapes the sustained levels.
        let beatEnvelopeValue = beatEnvelope.step(
            towards: onset, elapsed: elapsed, attack: 0.001, decayHalfLife: tuning.beatHalfLife
        )
        let beat = clamp(
            beatSpring.step(
                towards: beatEnvelopeValue, elapsed: elapsed,
                response: tuning.springResponse, damping: tuning.springDamping
            )
        )

        shaped = Levels(energy: energy, bands: bands, beat: beat)
        return shaped
    }

    private func shape(
        _ target: Double, envelope: inout Envelope, spring: inout Spring, elapsed: TimeInterval
    ) -> Double {
        let enveloped = envelope.step(
            towards: target, elapsed: elapsed,
            attack: tuning.attack, decayHalfLife: tuning.decayHalfLife
        )
        return clamp(
            spring.step(
                towards: enveloped, elapsed: elapsed,
                response: tuning.springResponse, damping: tuning.springDamping
            )
        )
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), tuning.headroom)
    }

    private func resizeBandStages(to count: Int) {
        guard bandGains.count != count else { return }
        bandGains = Array(repeating: AutoGain(), count: count)
        bandEnvelopes = Array(repeating: Envelope(), count: count)
        bandSprings = Array(repeating: Spring(), count: count)
    }
}

// MARK: - Stages

/// Exponential smoothing with a different time constant in each direction.
///
/// Fast up, slow down. Symmetric smoothing cannot do this: make it quick enough to catch a
/// transient and it also drops out of the transient just as quickly, so nothing is on screen
/// long enough to see; make it slow enough to see and it rounds the transient off entirely.
private struct Envelope {
    var value: Double = 0

    mutating func step(
        towards target: Double, elapsed: TimeInterval, attack: TimeInterval, decayHalfLife: TimeInterval
    ) -> Double {
        let tau = target > value ? attack : decayHalfLife / .ln2
        value += (target - value) * ExponentialCoefficient.of(elapsed: elapsed, tau: tau)
        return value
    }
}

/// A rolling minimum and maximum with exponential forgetting.
///
/// Each bound snaps to a new extreme immediately and drifts back towards the signal slowly,
/// which is a rolling window over the last several seconds without keeping the samples. The
/// current value is then mapped into whatever range those bounds describe, so the effect is
/// scaled to the material rather than to an absolute level nobody can predict.
private struct AutoGain {
    var floor: Double = 0
    var ceiling: Double = 0

    mutating func normalise(
        _ raw: Double, elapsed: TimeInterval, tuning: GlowDynamics.Tuning
    ) -> Double {
        let drift = ExponentialCoefficient.of(elapsed: elapsed, tau: tuning.gainHalfLife / .ln2)

        if raw > ceiling { ceiling = raw } else { ceiling += (raw - ceiling) * drift }
        if raw < floor { floor = raw } else { floor += (raw - floor) * drift }

        // Two gates, because either one alone lets silence through as a full-scale signal.
        // The span rejects a signal that is loud but never varies; the ceiling rejects one
        // that varies but is far too quiet to be anything but noise.
        let span = ceiling - floor
        guard span > tuning.gainNoiseFloor, ceiling > tuning.gainSilenceCeiling else { return 0 }
        return min(max((raw - floor) / span, 0), 1)
    }
}

/// A damped harmonic oscillator, in the same response and damping terms SwiftUI's springs use.
///
/// Stepped by hand rather than expressed as `.animation(.spring)` because the target changes
/// on every displayed frame. A SwiftUI animation restarts each time its value changes, so at
/// frame rate it never gets far enough into the curve to overshoot: the result is a spring
/// that looks exactly like a linear ramp.
private struct Spring {
    var value: Double = 0
    var velocity: Double = 0

    mutating func step(
        towards target: Double, elapsed: TimeInterval, response: Double, damping: Double
    ) -> Double {
        guard response > 0, elapsed > 0 else {
            if response <= 0 { value = target }
            return value
        }

        let omega = 2 * Double.pi / response
        // Sub-stepped at a fixed rate. Integrating a stiff spring across one long frame,
        // after a dropped frame or a wake from sleep, overshoots to infinity.
        var remaining = elapsed
        while remaining > 0 {
            let step = min(remaining, 1.0 / 240)
            let acceleration = -omega * omega * (value - target) - 2 * damping * omega * velocity
            velocity += acceleration * step
            value += velocity * step
            remaining -= step
        }
        return value
    }
}

private enum ExponentialCoefficient {
    /// Fraction of the remaining distance to cover in `elapsed`, for a time constant `tau`.
    /// Derived from the elapsed time rather than assumed per-frame, so the feel does not
    /// change with the refresh rate or when frames are dropped.
    static func of(elapsed: TimeInterval, tau: TimeInterval) -> Double {
        guard tau > 0 else { return 1 }
        guard elapsed > 0 else { return 0 }
        return 1 - exp(-elapsed / tau)
    }
}

private extension Double {
    static let ln2 = 0.693147180559945
}
