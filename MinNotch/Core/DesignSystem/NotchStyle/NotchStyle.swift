import AppKit
import SwiftUI

/// The six design languages the notch can be drawn in. Settings > Appearance > Notch Style.
enum NotchDesignLanguage: String, Codable, CaseIterable, Identifiable {
    case minimal
    case bento
    case glass
    case neumorphism
    case clay
    case skeuomorphism

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minimal: return "Minimal"
        case .bento: return "Bento"
        case .glass: return "Glass"
        case .neumorphism: return "Neumorphic"
        case .clay: return "Clay"
        case .skeuomorphism: return "Skeuomorphic"
        }
    }
}

/// Dark, light, or whichever macOS is using.
enum NotchStyleVariant: String, Codable, CaseIterable, Identifiable {
    case dark
    case light
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .system: return "Match System"
        }
    }
}

/// Everything about how the notch looks that a Notch Style decides, as plain values.
///
/// One set of views draws every style: they read this from the environment (`\.notchStyle`) and
/// never ask which language is chosen. A style is an entry in `NotchStyle.catalogue`, so another
/// one is another entry, not another copy of the UI.
///
/// Call sites keep the numbers they always drew with. Text says `theme.ink.opacity(0.6)` where it
/// used to say `.white.opacity(0.6)`, and a row says `NotchElementView(.tile, emphasis: 0.05)`
/// where it used to fill itself with white at 0.05. Minimal Dark's entry turns those back into
/// exactly the old colours, which `Scripts/style-diff.sh` proves pixel for pixel; every other
/// style reads the same numbers as a hierarchy and draws it its own way.
struct NotchStyle: Equatable {
    var language: NotchDesignLanguage
    var isDark: Bool

    /// Text and glyphs on the surface. White in the dark styles, near-black in the light ones.
    var ink: Color

    var surface: NotchSurfaceStyle
    /// Rows, tiles and chips: clipboard rows, links, events, files, lyric chips.
    var tile: NotchElementStyle
    /// Small buttons that light up on hover or when on: the top bar, the card's corner buttons.
    var button: NotchElementStyle
    /// A group of related content, drawn behind it. Bento's modules; nothing at all in Minimal.
    var module: NotchElementStyle?
    /// Previous, play and next.
    var transport: NotchTransportStyle
    /// Progress and level bars: the scrubber, the HUD, the timer, the battery.
    var track: NotchTrackStyle
    var artwork: NotchArtworkStyle
    var glow: NotchGlowStyle

    /// This language's dark variant. The closed notch uses it on a Mac with a camera housing,
    /// over a black surface (`NotchRootView` covers the fill), because the housing is black
    /// hardware and anything around it that is not black shows it up as a hole. Content laid
    /// over something dark whatever the style, such as Full Artwork's blurred cover, uses it too.
    var darkVariant: NotchStyle {
        NotchStyle.make(language, isDark: true)
    }

    /// Whether the surface is plain black, which is the only surface that needs no cover over a
    /// camera housing. True for Minimal Dark, which is why nothing about today's look changes.
    var isHousingBlack: Bool {
        surface == NotchSurfaceStyle.housing
    }
}

/// The surface the notch's shape is filled with.
struct NotchSurfaceStyle: Equatable {
    var base: Color
    /// Drawn over the base, top to bottom.
    var gradient: [Color] = []
    /// Desktop showing through, blurred (Glass). The material and how much tint stays on top.
    var glass: NotchGlass?
    /// Fine noise over the surface, as opacity. Skeuomorphic's material.
    var grain: Double = 0
    /// A line around the sides and bottom, inside the edge.
    var border: NotchBorder?
    /// A shadow under the open panel, for styles whose edge needs one to read against the desktop.
    /// Settings > Appearance > Panel Shadow still adds its own on top.
    var shadow: NotchShadow?
    /// What Settings > Appearance > Translucent Panel lays over the base. Only Minimal offers it.
    var vibrancyMaterial: NSVisualEffectView.Material = .hudWindow

    static let housing = NotchSurfaceStyle(base: .black)
}

struct NotchGlass: Equatable {
    var material: NSVisualEffectView.Material
    var appearance: NSAppearance.Name
    /// The base colour's opacity over the blur.
    var tint: Double
}

/// A stroke whose colour runs from the top of the shape to the bottom. The same colour twice is a
/// hairline; light over dark is a bevel.
struct NotchBorder: Equatable {
    var top: Color
    var bottom: Color
    var width: CGFloat = 1

    /// A plain colour when both ends match, so a hairline draws exactly as a coloured stroke.
    var shapeStyle: AnyShapeStyle {
        top == bottom
            ? AnyShapeStyle(top)
            : AnyShapeStyle(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
    }
}

struct NotchShadow: Equatable {
    var color: Color
    var radius: CGFloat
    var x: CGFloat = 0
    var y: CGFloat = 0
}

extension View {
    /// A style's shadow, or none: never a shadow at zero opacity, which still costs an offscreen
    /// pass and leaves a fringe on a transparent window.
    @ViewBuilder
    func notchShadow(_ shadow: NotchShadow?) -> some View {
        if let shadow {
            self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
        } else {
            self
        }
    }
}

/// How a background element is drawn: a tile, a button, a module, a track, a transport disc.
struct NotchElementStyle: Equatable {
    enum Fill: Equatable {
        /// The ink at the call site's own emphasis: exactly what Minimal always drew.
        case ink
        /// A colour of its own, with the ink laid over at the call site's emphasis times `lift`,
        /// so a hovered row still brightens.
        case color(Color, lift: Double)
        /// The same, top to bottom.
        case gradient(top: Color, bottom: Color, lift: Double)
    }

    var fill: Fill = .ink
    var border: NotchBorder?
    /// Shadows outside the shape: one dark and one light for a raised, molded look.
    var outer: [NotchShadow] = []
    /// Shadows inside the shape: a groove, or the soft swell of something inflated.
    var inner: [NotchShadow] = []
    /// Applied to a rounded rectangle's radius.
    var cornerScale: CGFloat = 1
    /// Whether an element at zero emphasis, an idle button, is drawn at all.
    var drawsWhenIdle = false

    /// True when the element is a plain fill, drawn exactly as Minimal draws it.
    var isPlain: Bool { border == nil && outer.isEmpty && inner.isEmpty }

    static let plain = NotchElementStyle()
}

struct NotchTransportStyle: Equatable {
    /// Drawn behind previous and next. `nil` leaves the bare glyph, as Minimal does.
    var disc: NotchElementStyle?
    /// Drawn behind play and pause, which can be stronger than its neighbours.
    var primaryDisc: NotchElementStyle?
}

struct NotchTrackStyle: Equatable {
    /// The groove behind the fill.
    var groove: NotchElementStyle = .plain
    /// Something drawn on the filled part, over the accent: a sheen, an inner light.
    var fillHighlight: Color?
    /// Light around the filled part, for an accent that glows.
    var fillGlow: NotchShadow?
}

struct NotchArtworkStyle: Equatable {
    var cornerScale: CGFloat = 1
    var border: NotchBorder? = NotchBorder(top: .white.opacity(0.12), bottom: .white.opacity(0.12), width: 0.5)
    var shadow: NotchShadow? = NotchShadow(color: .black.opacity(0.3), radius: 6, y: 3)
}

struct NotchGlowStyle: Equatable {
    /// Multiplies Ambient Lighting's intensity. 1 leaves it as the user set it.
    var intensityScale: Double = 1
}

// MARK: Environment

private struct NotchStyleKey: EnvironmentKey {
    static let defaultValue = NotchStyle.make(.minimal, isDark: true)
}

extension EnvironmentValues {
    /// The style notch components draw in. Minimal Dark unless a root says otherwise.
    var notchStyle: NotchStyle {
        get { self[NotchStyleKey.self] }
        set { self[NotchStyleKey.self] = newValue }
    }
}
