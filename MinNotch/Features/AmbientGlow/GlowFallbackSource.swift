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
    /// **Nothing playing means nothing moving.** This used to breathe gently when playback was
    /// paused, on the theory that a light which freezes reads as broken. It reads worse than
    /// broken: light moving with no music playing is indistinguishable from light following
    /// music badly, and the first thing anyone asks is whether the effect is listening at all.
    /// Stillness is the honest answer, and it is also the answer that makes the moving version
    /// mean something.
    /// With a `tempo`, beats fall on its grid: a tapped tempo on the taps, a song's tempo on the
    /// song's own position. Without one, the Speed slider sets it.
    static func levels(at time: TimeInterval, isPlaying: Bool, speed: Double, tempo: GlowTempo? = nil) -> GlowDynamics.Levels {
        guard isPlaying else {
            return GlowDynamics.Levels(
                energy: 0,
                bands: [Double](repeating: 0, count: GlowInput.bandCount),
                beat: 0
            )
        }

        // 92 to 140 bpm across the speed slider, which is the range most things sit in.
        let secondsPerBeat = tempo?.secondsPerBeat ?? 60 / (92 + speed * 48)
        // Measured from the tempo's origin, so beats land where it says they do. A remainder of
        // a negative time would be negative and never inside the window below.
        let time = time - (tempo?.origin ?? 0)
        guard time >= 0 else {
            return GlowDynamics.Levels(energy: 0, bands: [Double](repeating: 0, count: GlowInput.bandCount), beat: 0)
        }
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
