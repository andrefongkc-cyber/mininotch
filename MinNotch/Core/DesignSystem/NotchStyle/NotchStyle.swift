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

    /// One line under the tile in Settings: what sets this language apart.
    var blurb: String {
        switch self {
        case .minimal: return "Plain and quiet. The classic notch."
        case .bento: return "Content in tidy rounded modules."
        case .glass: return "Frosted glass with bright edges."
        case .neumorphism: return "Soft shapes pressed from one material."
        case .clay: return "Puffy, rounded and tactile."
        case .skeuomorphism: return "Physical keys, bevels and grain."
        }
    }
}

/// What the notch's surface is made of, under any style: the style's own fill, or Liquid Glass.
enum NotchBackground: String, Codable, CaseIterable, Identifiable {
    case solid
    case liquidGlass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: return "Solid"
        case .liquidGlass: return "Liquid Glass"
        }
    }

    /// Liquid Glass is the material macOS 26 introduced. Earlier systems have nothing to draw it
    /// with, so the option is shown switched off there, with the reason.
    static var isLiquidGlassSupported: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
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
        // "Auto", as macOS's own Appearance settings say it: "Match System" made the three
        // segments so wide that the row's title and subtitle wrapped a word to a line.
        case .system: return "Auto"
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
    /// Extra room between modules, and above the first, for a style that draws them. The panel
    /// grows by it; Minimal has none, so its layout is exactly what it always was.
    var moduleGap: CGFloat = 0

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
    /// Settings > Appearance > Background > Liquid Glass, on macOS 26: the surface is Liquid
    /// Glass tinted towards `base` by `liquidTint`, and the style's own glass, grain and edge
    /// give way to it.
    var liquidGlass = false
    var liquidTint: Double = 0.4
    /// Which appearance glass draws in: the style's variant, not the system's.
    var isDark = true

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
    /// The style's module behind this content: a card for a group of related things. It reaches
    /// `outset` beyond the content rather than padding it, so the content keeps its place and
    /// the module sits in the room `NotchStyle.moduleGap` makes. Nothing at all in a style
    /// without modules.
    func notchModule(cornerRadius: CGFloat = 12, horizontal: CGFloat = 7, vertical: CGFloat = 4) -> some View {
        background(NotchModuleBackground(cornerRadius: cornerRadius, horizontal: horizontal, vertical: vertical))
    }

    /// A multicolour symbol in the style. Apple's weather symbols draw their clouds white, which
    /// vanish on a light surface, so a light style gives them a faint outline of its ink; a dark
    /// style draws them exactly as before.
    @ViewBuilder
    func notchMulticolorSymbol(_ theme: NotchStyle) -> some View {
        if theme.isDark {
            self.symbolRenderingMode(.multicolor)
        } else {
            self.symbolRenderingMode(.multicolor)
                .shadow(color: theme.ink.opacity(0.45), radius: 0.6)
                .shadow(color: theme.ink.opacity(0.25), radius: 1.2)
        }
    }

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

    /// The same element letting the glass under it through: its own fill at `alpha` of its
    /// opacity, for Liquid Glass. A plain element's fill is ink at the call site's emphasis already.
    func glazed(_ alpha: Double) -> NotchElementStyle {
        var copy = self
        switch fill {
        case .ink:
            break
        case .color(let color, let lift):
            copy.fill = .color(color.opacity(alpha), lift: lift)
        case .gradient(let top, let bottom, let lift):
            copy.fill = .gradient(top: top.opacity(alpha), bottom: bottom.opacity(alpha), lift: lift)
        }
        return copy
    }
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

struct NotchModuleBackground: View {
    @Environment(\.notchStyle) private var theme
    let cornerRadius: CGFloat
    let horizontal: CGFloat
    let vertical: CGFloat

    var body: some View {
        if theme.module != nil {
            NotchElementView(.module, shape: .rounded(cornerRadius + max(horizontal, vertical)), emphasis: 0.05)
                .padding(.horizontal, -horizontal)
                .padding(.vertical, -vertical)
                .allowsHitTesting(false)
        }
    }
}

// MARK: Environment

private struct NotchStyleKey: EnvironmentKey {
    static let defaultValue = NotchStyle.make(.minimal, isDark: true)
}

private struct NotchContentScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// How much the open panel's text and controls are scaled for its width, 1 at the old
    /// default of 560 points. Set by `ExpandedPanelView` from the panel's width; read by the
    /// Now Playing card for its title and transport. See `ExpandedPanelView.contentScale`.
    var notchContentScale: CGFloat {
        get { self[NotchContentScaleKey.self] }
        set { self[NotchContentScaleKey.self] = newValue }
    }

    /// The style notch components draw in. Minimal Dark unless a root says otherwise.
    var notchStyle: NotchStyle {
        get { self[NotchStyleKey.self] }
        set { self[NotchStyleKey.self] = newValue }
    }
}
