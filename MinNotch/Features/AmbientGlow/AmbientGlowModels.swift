import SwiftUI

/// Which animation the glow runs.
enum AmbientGlowStyleKind: String, Codable, CaseIterable, Identifiable {
    case pulse
    case wave
    case bars
    case chase
    case rainbow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pulse: return "Pulse"
        case .wave: return "Wave"
        case .bars: return "Bars"
        case .chase: return "Chase"
        case .rainbow: return "Rainbow Cycle"
        }
    }

    var detail: String {
        switch self {
        case .pulse: return "The whole outline brightens and dims together."
        case .wave: return "A band of light flows around the outline."
        case .bars: return "The outline is split into segments, each following a frequency band."
        case .chase: return "A bright point runs around the outline, trailing behind it."
        case .rainbow: return "Hue sweeps continuously around the outline."
        }
    }

    /// Rainbow owns its own colour, so the colour mode picker is meaningless for it.
    var usesColorMode: Bool { self != .rainbow }
}

/// Where a glow is drawn. Any style can render at any of these.
enum AmbientGlowPlacement: String, Codable, CaseIterable, Identifiable, Hashable {
    case albumArt
    case collapsedNotch
    case expandedPanel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .albumArt: return "Album Art"
        case .collapsedNotch: return "Closed Notch"
        case .expandedPanel: return "Open Panel"
        }
    }

    var symbolName: String {
        switch self {
        case .albumArt: return "photo"
        case .collapsedNotch: return "rectangle.topthird.inset.filled"
        case .expandedPanel: return "rectangle.expand.vertical"
        }
    }
}

/// Where the glow takes its colour from.
enum GlowColorMode: String, Codable, CaseIterable, Identifiable {
    case albumArt
    case staticColor
    case rainbow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .albumArt: return "Album Artwork"
        case .staticColor: return "Static Color"
        case .rainbow: return "Rainbow"
        }
    }
}

/// Everything a style needs in order to draw one frame.
///
/// Styles receive this and nothing else. That is what keeps them swappable: a new style is a
/// function of this value and a path, with no knowledge of where the numbers came from or
/// whether the audio layer is even running.
///
/// The levels have already been through `GlowDynamics`, so they are gain-ridden, enveloped,
/// and sprung whichever source produced them. A style that branched on whether audio was
/// live would be reintroducing the difference this deliberately erases: the fallback drives
/// the same motion as a real signal, which is what makes the effect testable on a machine
/// that cannot be granted the audio permission.
struct GlowInput {
    var time: TimeInterval
    /// Overall loudness, 0...`headroom`.
    var energy: Double
    /// Per-band energy, low to high, each 0...`headroom`.
    var bands: [Double]
    /// 1 at the instant of an onset, decaying to 0.
    var beat: Double
    var isPlaying: Bool

    var palette: ArtworkPalette
    var colorMode: GlowColorMode
    var staticColor: Color
    /// 0...1, scales overall brightness.
    var intensity: Double
    /// 0...1, scales how fast anything moves.
    var speed: Double

    /// Kept small on purpose: Bars draws two segments per band and every segment is a
    /// stroked shape, so this is the main lever on how much the effect costs to draw.
    static let bandCount = 8

    /// Ceiling on a shaped level. Above 1 on purpose, so the spring's overshoot survives to
    /// the geometry instead of being flattened by a clamp at exactly the moment it matters.
    static let headroom: Double = 1.15

    /// Colour at a position around the outline, 0...1.
    ///
    /// Styles call this instead of picking colours themselves, so the colour mode applies
    /// uniformly and a new style gets all three modes for free.
    func color(at position: Double) -> Color {
        switch colorMode {
        case .rainbow:
            let hue = (position + time * 0.08 * (0.3 + speed)).truncatingRemainder(dividingBy: 1)
            return Color(hue: hue < 0 ? hue + 1 : hue, saturation: 0.85, brightness: 1)
        case .staticColor:
            return staticColor
        case .albumArt:
            // Two artwork colours blended by position, so the outline is not one flat tone.
            let blend = (sin(position * .pi * 2) + 1) / 2
            return blend < 0.5 ? palette.glowPrimary : palette.glowSecondary
        }
    }

    /// A single colour for styles that light the whole outline evenly.
    func uniformColor() -> Color {
        switch colorMode {
        case .rainbow:
            let hue = (time * 0.08 * (0.3 + speed)).truncatingRemainder(dividingBy: 1)
            return Color(hue: hue < 0 ? hue + 1 : hue, saturation: 0.85, brightness: 1)
        case .staticColor:
            return staticColor
        case .albumArt:
            return palette.glowPrimary
        }
    }
}

/// Settings > Appearance > Ambient Lighting.
struct AmbientGlowSettings: Codable, Equatable {
    var isEnabled: Bool = false
    var style: AmbientGlowStyleKind = .rainbow
    /// Multi-select: each active placement renders the same style against its own geometry.
    var placements: Set<AmbientGlowPlacement> = [.collapsedNotch, .expandedPanel]
    var colorMode: GlowColorMode = .albumArt
    var staticColor: RGBAColor = .systemBlue

    /// Off by default. Reading system audio needs a screen recording permission, which is
    /// not something to trigger on someone's behalf for a lighting effect.
    var isAudioReactive: Bool = false

    var intensity: Double = 0.7
    var speed: Double = 0.5
    var glowRadius: Double = 12

    /// Stop animating and drop the audio tap while the Mac is conserving power.
    var pauseInLowPowerMode: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = c.value(.isEnabled, false)
        style = c.value(.style, AmbientGlowStyleKind.rainbow)
        placements = c.value(.placements, Set<AmbientGlowPlacement>([.collapsedNotch, .expandedPanel]))
        colorMode = c.value(.colorMode, GlowColorMode.albumArt)
        staticColor = c.value(.staticColor, RGBAColor.systemBlue)
        isAudioReactive = c.value(.isAudioReactive, false)
        intensity = c.value(.intensity, 0.7, in: 0.1...1)
        speed = c.value(.speed, 0.5, in: 0...1)
        glowRadius = c.value(.glowRadius, 12, in: 2...28)
        pauseInLowPowerMode = c.value(.pauseInLowPowerMode, true)
    }

    /// True when the effect should draw at all right now.
    func isActive(isLowPower: Bool) -> Bool {
        guard isEnabled else { return false }
        if pauseInLowPowerMode && isLowPower { return false }
        return true
    }
}
