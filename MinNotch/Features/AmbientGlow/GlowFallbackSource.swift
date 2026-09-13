import Foundation

/// Stand-in levels for when there is no audio to analyse.
///
/// Emits impulses, not curves. Everything downstream, the envelope, the auto-gain, and the
/// spring, exists to turn a bare "now" into a hit that rises, overshoots, and settles, so the
/// fallback only has to say when. A source that pre-shapes its own smooth oscillation gets
/// shaped twice and arrives looking like the gentle breathing this replaces.
///
/// It matters more than a fallback usually would. The system audio permission cannot be
/// granted to an ad-hoc signed build at all, so on an unsigned machine this is the only thing
/// that ever drives the glow, and the whole effect is judged on it.
enum GlowFallbackSource {

    /// A synthetic bar of levels at `time`.
    ///
    /// Paused playback breathes instead of striking: a light that freezes reads as broken,
    /// and a light still hammering out a beat with nothing playing reads as a bug.
    static func levels(at time: TimeInterval, isPlaying: Bool, speed: Double) -> GlowDynamics.Levels {
        guard isPlaying else {
            let breath: Double = (sin(time * 0.55) + 1) / 2 * 0.4
            var resting = [Double](repeating: 0, count: GlowInput.bandCount)
            for index in resting.indices {
                let offset: Double = sin(time * 0.4 + Double(index) * 0.8)
                resting[index] = breath * (0.5 + 0.25 * (offset + 1))
            }
            return GlowDynamics.Levels(energy: breath, bands: resting, beat: 0)
        }

        // 92 to 140 bpm across the speed slider, which is the range most things sit in.
        let secondsPerBeat = 60 / (92 + speed * 48)
        let beat = time / secondsPerBeat
        let bar = floor(beat / 4)

        var bands = [Double](repeating: 0, count: GlowInput.bandCount)
        for index in bands.indices {
            let fraction = Double(index) / Double(max(GlowInput.bandCount - 1, 1))

            // Low bands land on the beat and high bands subdivide it, so the spectrum has a
            // pattern across it rather than every band flashing as one. Capped at four
            // subdivisions: at eight, something was striking almost every frame and nothing
            // ever had time to fall, which is the flatness this whole chain exists to avoid.
            let division = pow(2, floor(fraction * 2 + 0.5))
            let period = secondsPerBeat / division

            // A fixed window in seconds, not a fraction of the period. As a fraction, the
            // fastest subdivision's window came out shorter than one frame at 120 Hz, so
            // whole hits fell between samples and the pattern arrived ragged.
            guard time.truncatingRemainder(dividingBy: period) < 0.03 else { continue }

            // Varied per bar so it does not read as a metronome. Deterministic, so two
            // placements drawing at the same instant agree.
            bands[index] = 0.55 + 0.45 * abs(sin(bar * 2.3 + fraction * 3.1 + floor(beat) * 1.7))
        }

        // Overall level follows the low end, the way anything beat-driven should. Taking the
        // maximum across the whole spectrum let the fast top-end subdivisions hold it up
        // permanently, so the glow stayed lit instead of striking and falling.
        let low = max(bands.first ?? 0, bands.count > 1 ? bands[1] : 0)

        return GlowDynamics.Levels(
            energy: low,
            bands: bands,
            // Left to the shaper's own onset detector, which sees the energy jump. One
            // detector for both sources means the fallback exercises the real path.
            beat: 0
        )
    }
}
