import AppKit
import SwiftUI

/// The styles themselves. Each language is one function returning its dark or light variant.
///
/// Minimal Dark holds the values the notch was drawn with before styles existed, literally: white
/// ink, a black surface, plain fills, the artwork's old border and shadow. Change nothing about it
/// without running `Scripts/style-diff.sh` against a build from before the change.
extension NotchStyle {
    static func make(_ language: NotchDesignLanguage, isDark: Bool) -> NotchStyle {
        var style: NotchStyle
        switch language {
        case .minimal: style = minimal(isDark: isDark)
        case .bento: style = bento(isDark: isDark)
        case .glass: style = glass(isDark: isDark)
        case .neumorphism: style = neumorphism(isDark: isDark)
        case .clay: style = clay(isDark: isDark)
        case .skeuomorphism: style = skeuomorphism(isDark: isDark)
        }
        style.surface.isDark = isDark
        return style
    }

    /// Whether a language is finished enough to be offered in Settings.
    static func isOffered(_ language: NotchDesignLanguage) -> Bool {
        true
    }

    /// Resolves the user's choice. `systemIsDark` answers Match System.
    static func resolve(_ settings: AppearanceSettings, systemIsDark: Bool) -> NotchStyle {
        let isDark: Bool
        switch settings.notchVariant {
        case .dark: isDark = true
        case .light: isDark = false
        case .system: isDark = systemIsDark
        }
        let language = isOffered(settings.notchLanguage) ? settings.notchLanguage : .minimal
        var style = make(language, isDark: isDark)
        if settings.notchBackground == .liquidGlass, NotchBackground.isLiquidGlassSupported {
            style.surface.liquidGlass = true
            // Settings > Appearance > Glass Opacity. The default, 0.45, keeps text's contrast over a
            // busy desktop; a light style takes about seven tenths of it, as the same tint reads
            // stronger in white.
            let opacity = min(max(settings.liquidGlassOpacity, 0), 1)
            style.surface.liquidTint = isDark ? opacity : opacity * 0.72
            // A style's panels, tiles and buttons let the glass through as well, by the same
            // setting: solid panels sat on the glass as slabs and covered most of it, which in
            // Neumorphic, whose whole look is panels the colour of the surface, left almost no
            // glass at all. At 0 they are about 40% solid, glass panels with the style's shading;
            // at 1, solid again.
            let alpha = 0.42 + 0.58 * opacity
            style.tile = style.tile.glazed(alpha)
            style.button = style.button.glazed(alpha)
            style.module = style.module?.glazed(alpha)
            style.transport.disc = style.transport.disc?.glazed(alpha)
            style.transport.primaryDisc = style.transport.primaryDisc?.glazed(alpha)
            style.track.groove = style.track.groove.glazed(alpha)
        }
        return style
    }

    // MARK: Minimal

    /// The notch as it always was, and its light counterpart: the same geometry and the same
    /// simplicity, near-black ink on white, a hairline edge and a faint shadow so it holds its
    /// shape against a light desktop.
    private static func minimal(isDark: Bool) -> NotchStyle {
        if isDark {
            return NotchStyle(
                language: .minimal,
                isDark: true,
                ink: .white,
                surface: .housing,
                tile: .plain,
                button: .plain,
                module: nil,
                transport: NotchTransportStyle(),
                track: NotchTrackStyle(),
                artwork: NotchArtworkStyle(),
                glow: NotchGlowStyle()
            )
        }
        let ink = Color(red: 0.11, green: 0.11, blue: 0.12)
        return NotchStyle(
            language: .minimal,
            isDark: false,
            ink: ink,
            surface: NotchSurfaceStyle(
                base: Color(red: 0.985, green: 0.985, blue: 0.99),
                border: NotchBorder(top: .black.opacity(0.1), bottom: .black.opacity(0.14), width: 1),
                shadow: NotchShadow(color: .black.opacity(0.12), radius: 10, y: 3),
                vibrancyMaterial: .popover
            ),
            tile: .plain,
            button: .plain,
            module: nil,
            transport: NotchTransportStyle(),
            track: NotchTrackStyle(),
            artwork: NotchArtworkStyle(
                border: NotchBorder(top: .black.opacity(0.08), bottom: .black.opacity(0.08), width: 0.5),
                shadow: NotchShadow(color: .black.opacity(0.16), radius: 6, y: 3)
            ),
            glow: NotchGlowStyle()
        )
    }

    // MARK: Bento

    /// Modular: content sits in rounded modules a step lighter than the base (darker in the light
    /// variant, white on off-white), with hairline edges and generous room between them. Flat,
    /// quiet, and ordered, as Apple lays out its own modular pages.
    private static func bento(isDark: Bool) -> NotchStyle {
        if isDark {
            let module = Color(red: 0.11, green: 0.11, blue: 0.12)
            return NotchStyle(
                language: .bento,
                isDark: true,
                ink: Color(red: 0.96, green: 0.96, blue: 0.97),
                surface: NotchSurfaceStyle(
                    base: Color(red: 0.035, green: 0.035, blue: 0.04),
                    border: NotchBorder(top: .white.opacity(0.07), bottom: .white.opacity(0.04)),
                    shadow: NotchShadow(color: .black.opacity(0.4), radius: 14, y: 6)
                ),
                tile: NotchElementStyle(
                    fill: .color(Color(red: 0.15, green: 0.15, blue: 0.165), lift: 0.6),
                    border: NotchBorder(top: .white.opacity(0.06), bottom: .white.opacity(0.03), width: 0.5)
                ),
                button: .plain,
                module: NotchElementStyle(
                    fill: .color(module, lift: 0),
                    border: NotchBorder(top: .white.opacity(0.08), bottom: .white.opacity(0.03), width: 0.5),
                    drawsWhenIdle: true
                ),
                transport: NotchTransportStyle(
                    primaryDisc: NotchElementStyle(
                        fill: .color(Color(red: 0.19, green: 0.19, blue: 0.205), lift: 0.5),
                        border: NotchBorder(top: .white.opacity(0.1), bottom: .white.opacity(0.04), width: 0.5)
                    )
                ),
                track: NotchTrackStyle(groove: NotchElementStyle(fill: .color(Color(red: 0.2, green: 0.2, blue: 0.215), lift: 0))),
                artwork: NotchArtworkStyle(
                    cornerScale: 1.3,
                    border: NotchBorder(top: .white.opacity(0.1), bottom: .white.opacity(0.1), width: 0.5),
                    shadow: NotchShadow(color: .black.opacity(0.4), radius: 8, y: 3)
                ),
                glow: NotchGlowStyle(intensityScale: 0.85),
                moduleGap: 10
            )
        }
        return NotchStyle(
            language: .bento,
            isDark: false,
            ink: Color(red: 0.11, green: 0.11, blue: 0.12),
            surface: NotchSurfaceStyle(
                base: Color(red: 0.955, green: 0.955, blue: 0.965),
                border: NotchBorder(top: .black.opacity(0.08), bottom: .black.opacity(0.12)),
                shadow: NotchShadow(color: .black.opacity(0.14), radius: 12, y: 4),
                vibrancyMaterial: .popover
            ),
            tile: NotchElementStyle(
                fill: .color(Color(red: 0.93, green: 0.93, blue: 0.94), lift: 0.5),
                border: NotchBorder(top: .black.opacity(0.05), bottom: .black.opacity(0.07), width: 0.5)
            ),
            button: .plain,
            module: NotchElementStyle(
                fill: .color(.white, lift: 0),
                border: NotchBorder(top: .black.opacity(0.05), bottom: .black.opacity(0.08), width: 0.5),
                outer: [NotchShadow(color: .black.opacity(0.05), radius: 5, y: 2)],
                drawsWhenIdle: true
            ),
            transport: NotchTransportStyle(
                primaryDisc: NotchElementStyle(
                    fill: .color(Color(red: 0.94, green: 0.94, blue: 0.95), lift: 0.4),
                    border: NotchBorder(top: .black.opacity(0.05), bottom: .black.opacity(0.09), width: 0.5)
                )
            ),
            track: NotchTrackStyle(groove: NotchElementStyle(fill: .color(Color(red: 0.89, green: 0.89, blue: 0.905), lift: 0))),
            artwork: NotchArtworkStyle(
                cornerScale: 1.3,
                border: NotchBorder(top: .black.opacity(0.06), bottom: .black.opacity(0.06), width: 0.5),
                shadow: NotchShadow(color: .black.opacity(0.16), radius: 8, y: 3)
            ),
            glow: NotchGlowStyle(intensityScale: 0.85),
            moduleGap: 10
        )
    }

    // MARK: Glass

    /// Frosted glass over the desktop: the blurred desktop shows through a tinted surface, panes
    /// of lighter glass hold the content, and thin bright edges catch the light along the top.
    /// The edges and the shadow are what define the shape, since the middle is see-through.
    private static func glass(isDark: Bool) -> NotchStyle {
        if isDark {
            return NotchStyle(
                language: .glass,
                isDark: true,
                ink: .white,
                surface: NotchSurfaceStyle(
                    base: Color(red: 0.07, green: 0.08, blue: 0.1),
                    gradient: [.white.opacity(0.07), .white.opacity(0.0)],
                    glass: NotchGlass(material: .hudWindow, appearance: .darkAqua, tint: 0.36),
                    border: NotchBorder(top: .white.opacity(0.24), bottom: .white.opacity(0.08)),
                    shadow: NotchShadow(color: .black.opacity(0.35), radius: 14, y: 6)
                ),
                tile: NotchElementStyle(
                    fill: .color(.white.opacity(0.07), lift: 0.6),
                    border: NotchBorder(top: .white.opacity(0.14), bottom: .white.opacity(0.03), width: 0.5)
                ),
                button: .plain,
                module: NotchElementStyle(
                    fill: .color(.white.opacity(0.06), lift: 0),
                    border: NotchBorder(top: .white.opacity(0.18), bottom: .white.opacity(0.04), width: 0.5),
                    drawsWhenIdle: true
                ),
                transport: NotchTransportStyle(
                    primaryDisc: NotchElementStyle(
                        fill: .color(.white.opacity(0.12), lift: 0.5),
                        border: NotchBorder(top: .white.opacity(0.3), bottom: .white.opacity(0.05), width: 0.5)
                    )
                ),
                track: NotchTrackStyle(
                    groove: NotchElementStyle(fill: .color(.white.opacity(0.14), lift: 0)),
                    fillGlow: NotchShadow(color: .white, radius: 3)
                ),
                artwork: NotchArtworkStyle(
                    cornerScale: 1.2,
                    border: NotchBorder(top: .white.opacity(0.3), bottom: .white.opacity(0.08), width: 0.5),
                    shadow: NotchShadow(color: .black.opacity(0.35), radius: 10, y: 4)
                ),
                glow: NotchGlowStyle(intensityScale: 1),
                moduleGap: 10
            )
        }
        return NotchStyle(
            language: .glass,
            isDark: false,
            ink: Color(red: 0.1, green: 0.1, blue: 0.12),
            surface: NotchSurfaceStyle(
                base: .white,
                gradient: [.white.opacity(0.3), .white.opacity(0.05)],
                glass: NotchGlass(material: .popover, appearance: .aqua, tint: 0.28),
                border: NotchBorder(top: .white.opacity(0.95), bottom: .black.opacity(0.12)),
                shadow: NotchShadow(color: .black.opacity(0.18), radius: 14, y: 6),
                vibrancyMaterial: .popover
            ),
            tile: NotchElementStyle(
                fill: .color(.white.opacity(0.45), lift: 0.4),
                border: NotchBorder(top: .white.opacity(0.9), bottom: .black.opacity(0.06), width: 0.5)
            ),
            button: .plain,
            module: NotchElementStyle(
                fill: .color(.white.opacity(0.4), lift: 0),
                border: NotchBorder(top: .white.opacity(0.95), bottom: .black.opacity(0.06), width: 0.5),
                outer: [NotchShadow(color: .black.opacity(0.05), radius: 5, y: 2)],
                drawsWhenIdle: true
            ),
            transport: NotchTransportStyle(
                primaryDisc: NotchElementStyle(
                    fill: .color(.white.opacity(0.6), lift: 0.3),
                    border: NotchBorder(top: .white, bottom: .black.opacity(0.08), width: 0.5),
                    outer: [NotchShadow(color: .black.opacity(0.08), radius: 4, y: 2)]
                )
            ),
            track: NotchTrackStyle(
                groove: NotchElementStyle(fill: .color(.black.opacity(0.08), lift: 0)),
                fillGlow: NotchShadow(color: .white, radius: 3)
            ),
            artwork: NotchArtworkStyle(
                cornerScale: 1.2,
                border: NotchBorder(top: .white.opacity(0.7), bottom: .black.opacity(0.06), width: 0.5),
                shadow: NotchShadow(color: .black.opacity(0.18), radius: 10, y: 4)
            ),
            glow: NotchGlowStyle(intensityScale: 1),
            moduleGap: 10
        )
    }

    // MARK: Neumorphic

    /// Molded from one soft material: the surface, the modules and the controls are all the same
    /// tone, and depth comes only from a dark shadow on one side and a light one on the other.
    /// Modules and play controls stand out of the surface; grooves and pressed buttons sink in.
    private static func neumorphism(isDark: Bool) -> NotchStyle {
        let base: Color
        let dark: Color
        let light: Color
        let ink: Color
        if isDark {
            base = Color(red: 0.165, green: 0.176, blue: 0.196)
            dark = Color(red: 0.09, green: 0.096, blue: 0.11)
            light = Color(red: 0.235, green: 0.25, blue: 0.275)
            ink = Color(red: 0.88, green: 0.9, blue: 0.92)
        } else {
            base = Color(red: 0.894, green: 0.886, blue: 0.875)
            dark = Color(red: 0.74, green: 0.725, blue: 0.705)
            light = .white
            ink = Color(red: 0.27, green: 0.28, blue: 0.3)
        }
        func raised(_ distance: CGFloat, _ radius: CGFloat) -> [NotchShadow] {
            [NotchShadow(color: dark, radius: radius, x: distance, y: distance),
             NotchShadow(color: light, radius: radius, x: -distance, y: -distance)]
        }
        func sunk(_ distance: CGFloat, _ radius: CGFloat) -> [NotchShadow] {
            [NotchShadow(color: dark, radius: radius, x: distance, y: distance),
             NotchShadow(color: light.opacity(isDark ? 0.8 : 1), radius: radius, x: -distance, y: -distance)]
        }
        return NotchStyle(
            language: .neumorphism,
            isDark: isDark,
            ink: ink,
            surface: NotchSurfaceStyle(
                base: base,
                shadow: NotchShadow(color: .black.opacity(isDark ? 0.45 : 0.2), radius: 16, y: 6),
                vibrancyMaterial: isDark ? .hudWindow : .popover
            ),
            tile: NotchElementStyle(fill: .color(base, lift: 0.4), outer: raised(2, 3), cornerScale: 1.3, drawsWhenIdle: true),
            button: NotchElementStyle(fill: .color(base, lift: 0.3), inner: sunk(1.5, 2)),
            module: NotchElementStyle(fill: .color(base, lift: 0), outer: raised(3.5, 5), cornerScale: 1.2, drawsWhenIdle: true),
            transport: NotchTransportStyle(
                disc: NotchElementStyle(fill: .color(base, lift: 0.3), outer: raised(2, 3), drawsWhenIdle: true),
                primaryDisc: NotchElementStyle(
                    fill: .gradient(top: light.opacity(isDark ? 0.35 : 0.6), bottom: base, lift: 0.3),
                    outer: raised(3, 4),
                    drawsWhenIdle: true
                )
            ),
            track: NotchTrackStyle(groove: NotchElementStyle(fill: .color(base, lift: 0), inner: sunk(1, 1.5), drawsWhenIdle: true)),
            artwork: NotchArtworkStyle(
                cornerScale: 1.4,
                border: nil,
                shadow: NotchShadow(color: dark, radius: 6, x: 3, y: 3)
            ),
            glow: NotchGlowStyle(intensityScale: 0.55),
            moduleGap: 12
        )
    }

    // MARK: Clay

    /// Soft and inflated: big rounded modules and controls that look filled with air, lit from
    /// the top left inside and casting a soft shadow below. Warm neutrals, never bright colours;
    /// the accent is the only colour there is.
    private static func clay(isDark: Bool) -> NotchStyle {
        let base: Color
        let raisedFill: Color
        let ink: Color
        let highlight: Color
        let shade: Color
        let drop: Color
        let pressedFill: Color
        let pressedShade: Color
        if isDark {
            base = Color(red: 0.16, green: 0.155, blue: 0.19)
            raisedFill = Color(red: 0.23, green: 0.22, blue: 0.27)
            ink = Color(red: 0.95, green: 0.94, blue: 0.97)
            highlight = .white.opacity(0.13)
            shade = .black.opacity(0.32)
            drop = .black.opacity(0.45)
            pressedFill = Color(red: 0.12, green: 0.115, blue: 0.145)
            pressedShade = .black.opacity(0.6)
        } else {
            base = Color(red: 0.93, green: 0.91, blue: 0.89)
            raisedFill = Color(red: 0.985, green: 0.975, blue: 0.965)
            ink = Color(red: 0.24, green: 0.22, blue: 0.26)
            highlight = .white
            shade = Color(red: 0.8, green: 0.76, blue: 0.72).opacity(0.7)
            drop = Color(red: 0.55, green: 0.5, blue: 0.46).opacity(0.38)
            pressedFill = Color(red: 0.875, green: 0.85, blue: 0.825)
            pressedShade = Color(red: 0.62, green: 0.56, blue: 0.5).opacity(0.75)
        }
        func inflated(_ size: CGFloat) -> NotchElementStyle {
            NotchElementStyle(
                fill: .color(raisedFill, lift: 0.3),
                outer: [NotchShadow(color: drop, radius: size * 1.4, y: size)],
                inner: [NotchShadow(color: highlight, radius: size * 0.7, x: size * 0.5, y: size * 0.5),
                        NotchShadow(color: shade, radius: size * 0.7, x: -size * 0.5, y: -size * 0.5)],
                cornerScale: 1.7,
                drawsWhenIdle: true
            )
        }
        return NotchStyle(
            language: .clay,
            isDark: isDark,
            ink: ink,
            surface: NotchSurfaceStyle(
                base: base,
                gradient: [.white.opacity(isDark ? 0.04 : 0.25), .clear],
                shadow: NotchShadow(color: drop, radius: 18, y: 8),
                vibrancyMaterial: isDark ? .hudWindow : .popover
            ),
            tile: inflated(3),
            // Chosen things are pressed into the clay: a darker dent with its shadow inside, top
            // left. A raised button beside raised chips looked the same as all of them, so the
            // chosen rhythm or tab could not be told from the rest.
            button: NotchElementStyle(
                fill: .color(pressedFill, lift: 0.25),
                inner: [NotchShadow(color: pressedShade, radius: 2.5, x: 1.5, y: 1.5),
                        NotchShadow(color: highlight.opacity(isDark ? 0.6 : 1), radius: 2, x: -1, y: -1)],
                cornerScale: 1.5
            ),
            module: inflated(5),
            transport: NotchTransportStyle(disc: inflated(2.5), primaryDisc: inflated(3.5)),
            track: NotchTrackStyle(
                groove: NotchElementStyle(
                    fill: .color(isDark ? Color(red: 0.11, green: 0.105, blue: 0.135) : Color(red: 0.87, green: 0.84, blue: 0.81), lift: 0),
                    inner: [NotchShadow(color: shade, radius: 1.5, x: 1, y: 1)],
                    drawsWhenIdle: true
                ),
                fillHighlight: .white.opacity(0.3)
            ),
            artwork: NotchArtworkStyle(
                cornerScale: 1.8,
                border: nil,
                shadow: NotchShadow(color: drop, radius: 10, y: 6)
            ),
            glow: NotchGlowStyle(intensityScale: 0.8),
            moduleGap: 14
        )
    }

    // MARK: Skeuomorphic

    /// A physical object, kept restrained: a faintly grained surface with a bevel along its edge,
    /// modules and grooves set into it, and keys that stand proud of it with a light top edge.
    /// The accent fill reads as a lit tube. No leather, no wood, no stitching.
    private static func skeuomorphism(isDark: Bool) -> NotchStyle {
        if isDark {
            let inset = NotchBorder(top: .black.opacity(0.7), bottom: .white.opacity(0.09))
            let proud = NotchBorder(top: .white.opacity(0.2), bottom: .black.opacity(0.6))
            return NotchStyle(
                language: .skeuomorphism,
                isDark: true,
                ink: Color(red: 0.93, green: 0.93, blue: 0.94),
                surface: NotchSurfaceStyle(
                    base: Color(red: 0.12, green: 0.125, blue: 0.135),
                    gradient: [Color(red: 0.2, green: 0.205, blue: 0.22), Color(red: 0.09, green: 0.092, blue: 0.1)],
                    grain: 0.08,
                    border: NotchBorder(top: .white.opacity(0.16), bottom: .black.opacity(0.7)),
                    shadow: NotchShadow(color: .black.opacity(0.55), radius: 14, y: 7)
                ),
                tile: NotchElementStyle(
                    fill: .gradient(top: Color(red: 0.2, green: 0.205, blue: 0.22), bottom: Color(red: 0.145, green: 0.15, blue: 0.16), lift: 0.4),
                    border: proud,
                    outer: [NotchShadow(color: .black.opacity(0.5), radius: 1.5, y: 1)]
                ),
                button: NotchElementStyle(
                    fill: .color(Color(red: 0.08, green: 0.082, blue: 0.09), lift: 0.3),
                    border: inset,
                    inner: [NotchShadow(color: .black.opacity(0.7), radius: 2, y: 1.5)]
                ),
                module: NotchElementStyle(
                    fill: .color(Color(red: 0.075, green: 0.078, blue: 0.085), lift: 0),
                    border: inset,
                    inner: [NotchShadow(color: .black.opacity(0.65), radius: 3, y: 2)],
                    cornerScale: 0.8,
                    drawsWhenIdle: true
                ),
                transport: NotchTransportStyle(
                    disc: NotchElementStyle(
                        fill: .gradient(top: Color(red: 0.24, green: 0.245, blue: 0.26), bottom: Color(red: 0.13, green: 0.135, blue: 0.145), lift: 0.3),
                        border: proud,
                        outer: [NotchShadow(color: .black.opacity(0.6), radius: 2, y: 1.5)],
                        drawsWhenIdle: true
                    ),
                    primaryDisc: NotchElementStyle(
                        fill: .gradient(top: Color(red: 0.28, green: 0.285, blue: 0.3), bottom: Color(red: 0.14, green: 0.145, blue: 0.155), lift: 0.3),
                        border: proud,
                        outer: [NotchShadow(color: .black.opacity(0.65), radius: 2.5, y: 2)],
                        drawsWhenIdle: true
                    )
                ),
                track: NotchTrackStyle(
                    groove: NotchElementStyle(
                        fill: .color(Color(red: 0.04, green: 0.04, blue: 0.045), lift: 0),
                        border: NotchBorder(top: .black.opacity(0.8), bottom: .white.opacity(0.1), width: 0.5),
                        drawsWhenIdle: true
                    ),
                    fillHighlight: .white.opacity(0.45)
                ),
                artwork: NotchArtworkStyle(
                    cornerScale: 0.7,
                    border: NotchBorder(top: .white.opacity(0.18), bottom: .black.opacity(0.5), width: 0.5),
                    shadow: NotchShadow(color: .black.opacity(0.6), radius: 3, y: 2)
                ),
                glow: NotchGlowStyle(intensityScale: 0.7),
                moduleGap: 10
            )
        }
        let inset = NotchBorder(top: .black.opacity(0.22), bottom: .white.opacity(0.95))
        let proud = NotchBorder(top: .white, bottom: .black.opacity(0.22))
        return NotchStyle(
            language: .skeuomorphism,
            isDark: false,
            ink: Color(red: 0.17, green: 0.17, blue: 0.18),
            surface: NotchSurfaceStyle(
                base: Color(red: 0.9, green: 0.895, blue: 0.885),
                gradient: [Color(red: 0.96, green: 0.955, blue: 0.948), Color(red: 0.84, green: 0.835, blue: 0.825)],
                grain: 0.06,
                border: NotchBorder(top: .white, bottom: .black.opacity(0.28)),
                shadow: NotchShadow(color: .black.opacity(0.25), radius: 14, y: 7),
                vibrancyMaterial: .popover
            ),
            tile: NotchElementStyle(
                fill: .gradient(top: .white, bottom: Color(red: 0.92, green: 0.915, blue: 0.905), lift: 0.3),
                border: proud,
                outer: [NotchShadow(color: .black.opacity(0.16), radius: 1.5, y: 1)]
            ),
            button: NotchElementStyle(
                fill: .color(Color(red: 0.86, green: 0.855, blue: 0.845), lift: 0.3),
                border: inset,
                inner: [NotchShadow(color: .black.opacity(0.2), radius: 2, y: 1.5)]
            ),
            module: NotchElementStyle(
                fill: .color(Color(red: 0.875, green: 0.87, blue: 0.86), lift: 0),
                border: inset,
                inner: [NotchShadow(color: .black.opacity(0.14), radius: 3, y: 2)],
                cornerScale: 0.8,
                drawsWhenIdle: true
            ),
            transport: NotchTransportStyle(
                disc: NotchElementStyle(
                    fill: .gradient(top: .white, bottom: Color(red: 0.89, green: 0.885, blue: 0.875), lift: 0.3),
                    border: proud,
                    outer: [NotchShadow(color: .black.opacity(0.22), radius: 2, y: 1.5)],
                    drawsWhenIdle: true
                ),
                primaryDisc: NotchElementStyle(
                    fill: .gradient(top: .white, bottom: Color(red: 0.86, green: 0.855, blue: 0.845), lift: 0.3),
                    border: proud,
                    outer: [NotchShadow(color: .black.opacity(0.26), radius: 2.5, y: 2)],
                    drawsWhenIdle: true
                )
            ),
            track: NotchTrackStyle(
                groove: NotchElementStyle(
                    fill: .color(Color(red: 0.78, green: 0.775, blue: 0.765), lift: 0),
                    border: NotchBorder(top: .black.opacity(0.28), bottom: .white.opacity(0.9), width: 0.5),
                    drawsWhenIdle: true
                ),
                fillHighlight: .white.opacity(0.5)
            ),
            artwork: NotchArtworkStyle(
                cornerScale: 0.7,
                border: NotchBorder(top: .black.opacity(0.2), bottom: .white.opacity(0.8), width: 0.5),
                shadow: NotchShadow(color: .black.opacity(0.25), radius: 3, y: 2)
            ),
            glow: NotchGlowStyle(intensityScale: 0.7),
            moduleGap: 10
        )
    }
}
