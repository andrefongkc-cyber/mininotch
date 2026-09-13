import SwiftUI

/// One lit stretch of the outline.
///
/// `start` and `end` are fractions of the perimeter and may run past 1, which the renderer
/// wraps. Styles therefore never have to think about the seam.
struct GlowSegment: Identifiable {
    let id: Int
    var start: Double
    var end: Double
    var color: Color
    var width: CGFloat

    /// True when this segment is the entire outline, which the renderer strokes as a closed
    /// path so there is no cap overlap at the seam.
    var coversWholePath: Bool { start <= 0 && end >= 1 }
}

/// One glow animation.
///
/// A style turns `GlowInput` into segments and draws nothing itself. Keeping them as pure
/// data means a style can be reasoned about and tested without a renderer, and adding a sixth
/// is a matter of writing one function and adding a case to `AmbientGlowStyleKind`.
///
/// The levels arriving in `GlowInput` are already shaped by `GlowDynamics`: gain-ridden,
/// enveloped, and sprung. A style should map them to geometry and colour and add no smoothing
/// of its own, because a second round of smoothing on top of the envelope is exactly what
/// makes an audio-reactive effect feel late.
protocol AmbientGlowStyle {
    func segments(input: GlowInput) -> [GlowSegment]
}

enum AmbientGlowStyleFactory {
    static func make(_ kind: AmbientGlowStyleKind) -> AmbientGlowStyle {
        switch kind {
        case .pulse: return PulseGlowStyle()
        case .wave: return WaveGlowStyle()
        case .bars: return BarsGlowStyle()
        case .chase: return ChaseGlowStyle()
        case .rainbow: return RainbowGlowStyle()
        }
    }
}

/// Shared helpers, so the width ramp is defined once.
enum GlowMath {
    /// Thinnest the outline ever gets. Not zero: a stroke that vanishes at rest makes the
    /// effect look like it has stopped working rather than like it is waiting.
    static let minimumWidth: CGFloat = 2
    /// How much thicker a full-level stroke is than a resting one.
    ///
    /// This is the main carrier of the bounce. Opacity alone cannot do it: it saturates at 1
    /// and the eye reads brightness far less precisely than it reads size, so an effect that
    /// only brightens looks like it is glowing along with the music rather than hitting on it.
    static let widthSpan: CGFloat = 6.5

    static func width(for level: Double) -> CGFloat {
        minimumWidth + CGFloat(min(max(level, 0), GlowInput.headroom)) * widthSpan
    }

    /// Adds a transient on top of a sustained level without letting the sum run away.
    static func punch(_ level: Double, beat: Double, amount: Double) -> Double {
        min(level + beat * amount, GlowInput.headroom)
    }
}

/// The whole outline brightens and dims together.
///
/// Evenly lit by construction: one segment covering the entire perimeter, one colour, one
/// width. This is the style to pick when the light should read as a single lamp behind the
/// notch rather than as movement around it.
struct PulseGlowStyle: AmbientGlowStyle {
    func segments(input: GlowInput) -> [GlowSegment] {
        // The transient rides on top of the sustained level rather than replacing it, so a
        // kick lands as a jump above whatever the track is already doing.
        let level = GlowMath.punch(input.energy, beat: input.beat, amount: 0.45)

        return [
            GlowSegment(
                id: 0,
                start: 0,
                end: 1,
                color: input.uniformColor().opacity((0.22 + level * 0.78) * input.intensity),
                width: GlowMath.width(for: level)
            )
        ]
    }
}

/// Hue sweeps around the outline.
///
/// Also evenly lit: the colour changes over time rather than around the perimeter, so there
/// are no bright corners and dim edges of the kind a gradient anchored to the centre of a
/// wide, short shape produces.
struct RainbowGlowStyle: AmbientGlowStyle {
    func segments(input: GlowInput) -> [GlowSegment] {
        let level = GlowMath.punch(input.energy * 0.8, beat: input.beat, amount: 0.5)

        return [
            GlowSegment(
                id: 0,
                start: 0,
                end: 1,
                color: input.uniformColor().opacity((0.35 + level * 0.65) * input.intensity),
                width: GlowMath.width(for: level)
            )
        ]
    }
}

/// A band of light travelling around the perimeter.
struct WaveGlowStyle: AmbientGlowStyle {
    private let restingLength: Double = 0.24
    private let steps = 8

    func segments(input: GlowInput) -> [GlowSegment] {
        let energy = input.energy
        let rate = 0.06 + input.speed * 0.22 + energy * 0.18
        let head = (input.time * rate).truncatingRemainder(dividingBy: 1)

        // The band lengthens as well as brightening, so a loud passage is a longer sweep of
        // light and not just the same sweep turned up.
        let length = restingLength * (0.65 + energy * 0.7)

        // A dim rim underneath, so the unlit stretch still reads as part of the effect
        // rather than as a gap.
        var result = [
            GlowSegment(
                id: 0,
                start: 0,
                end: 1,
                color: input.uniformColor().opacity(0.14 * input.intensity),
                width: GlowMath.minimumWidth
            )
        ]

        let step = length / Double(steps)
        for index in 0..<steps {
            let position = Double(index) / Double(steps)
            // Brightest in the middle of the band, tapering at both ends.
            let falloff = sin(position * .pi)
            let level = falloff * GlowMath.punch(0.3 + energy * 0.7, beat: input.beat, amount: 0.4)
            let start = head + position * length

            result.append(
                GlowSegment(
                    id: index + 1,
                    start: start,
                    end: start + step,
                    color: input.color(at: start).opacity(level * input.intensity),
                    width: GlowMath.width(for: level)
                )
            )
        }
        return result
    }
}

/// A spectrum analyser wrapped around the outline.
///
/// Mirrored, so the two halves match: the lowest band sits at both ends of the top edge and
/// the highest meets in the middle, which keeps bass at the corners where there is most room.
///
/// Each bar carries its level three ways at once, thickness, arc length, and brightness,
/// because the outline gives a bar nowhere to grow in height. Thickness is the closest
/// analogue and length is what makes a loud band read as bigger rather than merely brighter.
struct BarsGlowStyle: AmbientGlowStyle {
    func segments(input: GlowInput) -> [GlowSegment] {
        let total = GlowInput.bandCount * 2
        let span = 1.0 / Double(total)

        return (0..<total).map { index in
            let mirrored = index < total / 2 ? index : total - 1 - index
            let level = input.bands.isEmpty
                ? 0
                : input.bands[min(mirrored, input.bands.count - 1)]

            let start = Double(index) * span
            return GlowSegment(
                id: index,
                start: start,
                // Never the full span: the gap between bars is what makes them read as
                // separate bars rather than as one ring of varying thickness.
                end: start + span * (0.4 + 0.45 * min(level, 1)),
                color: input.color(at: start).opacity((0.12 + level * 0.88) * input.intensity),
                width: GlowMath.width(for: level)
            )
        }
    }
}

/// A bright point running around the outline with a fading tail.
struct ChaseGlowStyle: AmbientGlowStyle {
    private let tailSegments = 10
    private let restingTail: Double = 0.3

    func segments(input: GlowInput) -> [GlowSegment] {
        let energy = input.energy
        let rate = 0.1 + input.speed * 0.35 + energy * 0.35
        let head = (input.time * rate).truncatingRemainder(dividingBy: 1)
        // A loud passage smears the tail out behind the head.
        let tail = restingTail * (0.6 + energy * 0.8)

        var result: [GlowSegment] = []

        // A beat flashes the whole outline before the chase resumes.
        if input.beat > 0.01 {
            result.append(
                GlowSegment(
                    id: 0,
                    start: 0,
                    end: 1,
                    color: input.uniformColor().opacity(input.beat * 0.45 * input.intensity),
                    width: GlowMath.width(for: input.beat)
                )
            )
        }

        let step = tail / Double(tailSegments)
        for index in 0..<tailSegments {
            let back = Double(index) / Double(tailSegments)
            // Square falloff, so the head reads as a point and the tail drops away fast.
            let level = pow(1 - back, 1.7) * (0.45 + energy * 0.55)
            let start = head - back * tail

            result.append(
                GlowSegment(
                    id: index + 1,
                    start: start,
                    end: start + step,
                    color: input.color(at: start).opacity(level * input.intensity),
                    width: GlowMath.width(for: level)
                )
            )
        }
        return result
    }
}
